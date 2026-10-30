# iOS Simulator 数据库写入

仅在已通过 `SKILL.md` 显式授权写入门禁后使用本流程。只操作用户明确指定的
`simulated` 设备、Debug App、App Data Container 或 App Group Container 和
SQLite 数据库。不要操作生产数据，也不要尝试写回物理设备。

## 精确计划与预检

执行写入前核对并记录：

- Simulator UDID、Bundle ID、Container 类型和标识符。
- 数据库相对路径、schema、主库与 `-wal` / `-shm` 是否存在。
- 预检 `SELECT` 和预期行数、精确 DML、预期修改行数。
- 是否允许停止和重新启动 Debug App。
- 备份位置、完整性检查命令，以及用户已授权的恢复方式。

任何目标不一致、行数不符合预期或数据库不是可读 SQLite 时停止。先用只读连接
确认当前状态：

```bash
sqlite3 -readonly -header -column "<DATABASE_PATH>" \
  "<PRECONDITION_SELECT>"

sqlite3 -readonly "<DATABASE_PATH>" "PRAGMA quick_check;"
```

只使用已核实的表和列。不要执行未经确认的批量更新，不要把用户输入直接拼进
Shell；复杂值应使用可信 SQL 脚本或 SQLite 参数机制。

## 停止 App 与建立备份

计划已经允许停止 App 后，再执行：

```bash
xcrun simctl terminate "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>"
```

如果 App 本来没有运行，确认这一点即可，不要把失败当作成功。创建仅当前用户可访问
的临时目录，记录数据库文件信息并建立合并 WAL 的 SQLite backup：

```bash
MUTATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ios-simulator-mutation.XXXXXX")"
BACKUP="$MUTATION_DIR/before.db"

for file in "$DATABASE_PATH" "$DATABASE_PATH-wal" "$DATABASE_PATH-shm"; do
  if [[ -e "$file" ]]; then
    shasum -a 256 "$file"
  fi
done | tee "$MUTATION_DIR/before.sha256"

sqlite3 -readonly "$DATABASE_PATH" ".backup '$BACKUP'"
sqlite3 -readonly "$BACKUP" "PRAGMA quick_check;"
sqlite3 -readonly -header -column "$BACKUP" \
  "<PRECONDITION_SELECT>"
```

备份检查不是 `ok` 时停止。停止 App 后再次执行预检查询仍必须符合已确认计划；
否则说明预检与当前快照不一致，不要继续修改。不要直接编辑、删除或复制正在使用的
WAL/SHM 来替代 backup。

## 在事务中执行已确认变更

只运行用户已经确认的 DML。以下结构用于单库事务，实际表名、条件和值必须来自
已确认计划：

```bash
sqlite3 "$DATABASE_PATH" <<'SQL'
.bail on
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
UPDATE <TABLE_NAME>
SET <COLUMN_NAME> = <CONFIRMED_VALUE>
WHERE <CONFIRMED_PREDICATE>;
SELECT changes() AS changed_rows;
COMMIT;
SQL
```

预期修改行数不一致时视为失败。若 SQLite 报错或进程中断，先以只读方式检查事务
是否已经提交，不要盲目重试。

提交后执行精确查询和完整性检查：

```bash
sqlite3 -readonly -header -column "$DATABASE_PATH" \
  "<EXPECTED_ROW_SELECT>"

sqlite3 -readonly "$DATABASE_PATH" \
  "PRAGMA quick_check; PRAGMA foreign_key_check;"
```

只有计划允许时才重新启动 App：

```bash
xcrun simctl launch "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>"
```

随后验证关键状态和异常日志。数据库可读不等于应用缓存、业务状态或 UI 已经正确
刷新。

## 失败与恢复

- 事务未提交：保留现场，以只读方式检查数据库，然后重新确认计划。
- 已提交但查询、完整性检查或 App 行为不符合预期：停止新的写入，报告实际
  `changed_rows` 和检查结果。
- 需要恢复时，继续使用本任务的 `before.db`，不要手工删除主库或 WAL。

恢复本身也是写操作。它应属于用户已经确认的恢复方案；否则先展示恢复命令和影响
范围并再次确认。获得确认后，确认 App 已停止，再执行：

```bash
sqlite3 "$DATABASE_PATH" ".restore '$BACKUP'"
sqlite3 -readonly "$DATABASE_PATH" "PRAGMA quick_check;"
```

恢复后按确认范围重新启动 App 并验证。备份和使用后的临时目录可能包含用户数据，
只能保留到回滚决策完成；得到可以清理的确认后立即删除。

## 交付记录

报告 UDID、Bundle ID、Container、数据库相对路径、已确认的 DML、修改前后结果、
`changed_rows`、备份是否通过检查、WAL/SHM 处理、App 停止/重启状态和恢复结果。
