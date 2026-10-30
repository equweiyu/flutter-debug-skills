# Android Debug 数据库写入

仅在已通过 `SKILL.md` 显式授权写入门禁后使用本流程。只操作用户明确指定的 Android 真机
或模拟器、application ID、App Data Container 和普通 SQLite 数据库。目标必须
可由 `run-as` 访问；不要绕过 Android 沙箱，也不要操作不持有正确密钥的加密库。

## 精确计划与只读预检

记录设备序列号或 emulator ID、application ID、远端数据库相对路径、schema、
预检 `SELECT` 与预期行数、精确 DML、预期修改行数、App 停止/重启授权、备份位置、
设备内回滚目录和恢复方式。数据库路径必须是 App 数据目录内的普通相对路径，拒绝
绝对路径、`..`、空字节和 Shell 元字符。

确认 App 可调试且数据库属于当前目标：

```bash
DATABASE_RELATIVE_PATH="<RELATIVE_DATABASE_PATH>"

"$ADB" -s "$SERIAL" shell pm path "$PACKAGE"
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" id
```

通过临时只读导出确认 SQLite 可解析、schema 和预检行数都符合已确认计划。这个
预览目录可能早于最终 `force-stop`，不能用于写回：

```bash
PRECHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-database-precheck.XXXXXX")"

ADB_BIN="$ADB" bash "<SKILL_DIR>/scripts/export_android_database.sh" \
  "$SERIAL" \
  "$PACKAGE" \
  "$DATABASE_RELATIVE_PATH" \
  "$PRECHECK_DIR"

PRECHECK_DB="$PRECHECK_DIR/<DATABASE_FILENAME>"
sqlite3 -readonly "$PRECHECK_DB" "PRAGMA quick_check;"
sqlite3 -readonly -header -column "$PRECHECK_DB" \
  "<PRECONDITION_SELECT>"
```

行数或值不符合已确认计划时停止。只使用已核实的表和列；不要拼接未经处理的用户
输入。复杂值应通过可信 SQL 脚本或参数机制写入。

## 停止 App 并修改本地工作库

计划已经允许停止 App 后，再执行：

```bash
"$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE"

if "$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  test -e "$DATABASE_RELATIVE_PATH-journal"; then
  printf 'hot rollback journal present; stop file replacement\n' >&2
  exit 1
fi
```

确认应用进程已经退出且不存在 `-journal` 后，重新导出最终备份。不要复用
`PRECHECK_DIR`：

```bash
EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-database-mutation.XXXXXX")"

ADB_BIN="$ADB" bash "<SKILL_DIR>/scripts/export_android_database.sh" \
  "$SERIAL" \
  "$PACKAGE" \
  "$DATABASE_RELATIVE_PATH" \
  "$EXPORT_DIR"
```

最终导出目录应包含主库以及停止后仍存在的 `-wal` / `-shm`。建立包含已提交 WAL
内容的合并备份，再创建只用于写入回传的工作库：

```bash
SOURCE_DB="$EXPORT_DIR/<DATABASE_FILENAME>"
BACKUP="$EXPORT_DIR/before.db"
WORK_DB="$EXPORT_DIR/mutation-working.db"

sqlite3 -readonly "$SOURCE_DB" ".backup '$BACKUP'"
sqlite3 -readonly "$BACKUP" "PRAGMA quick_check;"
sqlite3 -readonly "$BACKUP" ".backup '$WORK_DB'"
sqlite3 "$WORK_DB" \
  "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode = DELETE;"

test ! -e "$WORK_DB-wal"
test ! -e "$WORK_DB-shm"
sqlite3 -readonly -header -column "$WORK_DB" \
  "<PRECONDITION_SELECT>"
```

备份检查不是 `ok`、停止后的预检结果不符合计划或工作库仍有 sidecar 时停止。
工作库切换为 rollback journal 后再修改，避免把孤立的 WAL/SHM 随主库一起替换。

最终备份完成且不再需要预览后，按项目临时数据处理规则清理 `PRECHECK_DIR`。
以下结构用于工作库的单库事务，实际表名、条件和值必须来自已确认计划：

```bash
sqlite3 "$WORK_DB" <<'SQL'
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

预期修改行数不一致时视为失败。提交后执行：

```bash
sqlite3 -readonly -header -column "$WORK_DB" "<EXPECTED_ROW_SELECT>"
sqlite3 -readonly "$WORK_DB" \
  "PRAGMA quick_check; PRAGMA foreign_key_check;"
test ! -e "$WORK_DB-wal"
test ! -e "$WORK_DB-shm"
```

任何检查失败都不要写回设备；保留工作目录并以只读方式调查。

## 写回设备

先在 App 私有目录同一文件系统中创建唯一暂存文件和回滚目录，使用 `run-as`
接收二进制数据库，不能使用普通 `adb push` 写入私有数据目录。以下变量必须来自
已通过路径校验的已确认计划：

```bash
REMOTE_DIR="$(dirname "$DATABASE_RELATIVE_PATH")"
REMOTE_NAME="$(basename "$DATABASE_RELATIVE_PATH")"
STAMP="$(date +%Y%m%d%H%M%S)"
REMOTE_WORK_DIR="$REMOTE_DIR/.$REMOTE_NAME.codex-$STAMP"
REMOTE_STAGING="$REMOTE_WORK_DIR/main.db"
REMOTE_ROLLBACK="$REMOTE_WORK_DIR/before"

"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  mkdir "$REMOTE_WORK_DIR"

"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  mkdir "$REMOTE_ROLLBACK"

"$ADB" -s "$SERIAL" exec-in run-as "$PACKAGE" \
  sh -c 'cat > "$1"' _ "$REMOTE_STAGING" < "$WORK_DB"
```

任何 `mkdir` 失败都停止，不要覆盖已有暂存目录。传输后比较本地与远端 staging
的字节数：

```bash
LOCAL_BYTES="$(wc -c < "$WORK_DB" | tr -d '[:space:]')"
REMOTE_BYTES="$(
  "$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
    wc -c "$REMOTE_STAGING" | awk '{print $1}'
)"
[[ "$REMOTE_BYTES" == "$LOCAL_BYTES" ]]
```

需要完整字节校验时，再通过 `exec-out cat` 流式比较 SHA-256。大小或校验不一致时
停止，不要移动现有数据库。

把原主库和存在的 sidecar 移入回滚目录，再安装 staging：

```bash
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  mv "$DATABASE_RELATIVE_PATH" "$REMOTE_ROLLBACK/main.db"

for sidecar in -wal -shm; do
  if "$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
    test -e "$DATABASE_RELATIVE_PATH$sidecar"; then
    "$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
      mv "$DATABASE_RELATIVE_PATH$sidecar" \
      "$REMOTE_ROLLBACK/main.db$sidecar"
  fi
done

"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  mv "$REMOTE_STAGING" "$DATABASE_RELATIVE_PATH"
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" \
  chmod 600 "$DATABASE_RELATIVE_PATH"
```

再次通过 `exec-out` 读取已安装主库并与 `WORK_DB` 比较大小或哈希。只有计划允许时
才用项目正常方式重新启动 App，并验证目标记录、业务状态、关键页面和异常日志。

## 失败与恢复

- staging 传输或校验失败：保持 App 停止，删除本次 staging 前先确认计划允许；
  原数据库尚未移动。
- 原文件移动或新库安装失败：使用 `REMOTE_ROLLBACK/main.db` 和已导出的主库、
  sidecar 恢复，先核对文件完整性，再替换。
- 已安装但记录、完整性或 App 行为不符合预期：停止新的写入，报告实际
  `changed_rows` 和检查结果。
- 设备内回滚目录与主机临时备份都可能包含用户数据。完成验证前不要清理；清理也是
  写操作，必须属于已确认计划或再次获得确认。

恢复本身也是写操作。恢复时应保持 App 停止，把失败主库和 sidecar 移到新的唯一
目录而不是直接删除，再放回 `REMOTE_ROLLBACK/main.db`。随后校验主库完整性、文件
权限和目标记录，并在获得允许后重新启动 App。若设备内回滚目录不可用，再用
`BACKUP` 按相同 staging 流程重建数据库，不能直接覆盖正在使用的 WAL/SHM。

## 交付记录

报告设备序列号、application ID、远端相对路径、已确认的 DML、修改前后结果、
`changed_rows`、主机备份与设备内回滚目录、完整性检查、App 停止/重启状态和恢复
结果。
