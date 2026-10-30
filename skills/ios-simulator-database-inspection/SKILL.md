---
name: ios-simulator-database-inspection
version: 1.0.0
description: Inspect SQLite and SQLite-backed Core Data databases inside iOS Simulator app or App Group containers. Use when locating a simulator database, reviewing schemas or rows, taking a consistent debug snapshot, or diagnosing WAL-related missing data without mutating the database.
metadata:
  short-description: Inspect iOS Simulator app databases without mutation
  starchild:
    skillKey: ios-simulator-database-inspection
    requires:
      bins: [xcrun, sqlite3]
user-invocable: true
disable-model-invocation: false
---

# iOS Simulator 数据库检查

默认以只读方式检查 Simulator 数据库。除非用户明确要求修改数据且目标已经核实，
否则不要执行 `UPDATE`、`DELETE`、架构变更或删除数据库附属文件。

## 操作流程

1. 列出已启动的设备；存在多个设备时，明确选择 UDID：

   ```bash
   xcrun simctl list devices booted
   ```

2. 从项目配置或已安装 App 列表确认 Bundle ID，不要猜测：

   ```bash
   xcrun simctl listapps "<SIMULATOR_UDID>"
   ```

3. 每次检查都重新解析数据容器；重装 App 会改变容器 UUID：

   ```bash
   SIM_DATA_CONTAINER="$(xcrun simctl get_app_container \
     "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" data)"
   ```

   对 App Group 存储，先列出分组或解析已知的分组标识：

   ```bash
   xcrun simctl get_app_container \
     "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" groups

   xcrun simctl get_app_container \
     "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" "<APP_GROUP_IDENTIFIER>"
   ```

4. 在解析出的容器中搜索数据库，不要预设目录或文件名：

   ```bash
   find "$SIM_DATA_CONTAINER" -type f \
     \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print
   ```

5. 使用只读 SQLite 连接检查选定的数据库：

   ```bash
   sqlite3 -readonly -header -column "<DATABASE_PATH>" \
     "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"

   sqlite3 -readonly "<DATABASE_PATH>" ".schema <TABLE_NAME>"

   sqlite3 -readonly -header -column "<DATABASE_PATH>" \
     "SELECT * FROM <TABLE_NAME> LIMIT 20;"
   ```

   只使用从 schema 中确认的可信表和列名构造无参数诊断查询。路径可能变化或包含
   空格，因此必须加引号。

## 一致性快照

SQLite 可能把近期提交保存在 `-wal`，协调状态保存在 `-shm`。App 运行期间不要只
复制主 `.db` 文件，否则可能得到过期或不一致的快照。

需要稳定产物时，先终止 App，再使用 SQLite backup：

```bash
xcrun simctl terminate "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>"
sqlite3 -readonly "<DATABASE_PATH>" \
  ".backup '/tmp/ios-simulator-database-snapshot.db'"
```

如果必须直接复制文件，先终止 App，并同时保留匹配的 `.db`、`-wal` 和 `-shm`。

## 解释边界

- SQLite-backed Core Data 可以检查，但生成的 schema 属于实现细节；不要仅凭表名
  推断业务语义。
- Realm、Isar、ObjectBox 等非 SQLite 存储不能用 `sqlite3` 查询，即使文件位于
  同一容器中。
- 记录缺失可能来自错误的 Simulator、Bundle ID、App Group、数据库文件或 WAL
  处理方式；确认这些边界后才能判断数据不存在。
- 交付结果时记录 Simulator UDID、Bundle ID、解析后的数据库路径和精确的只读
  查询。日志和摘要中不要包含机密信息或无关用户数据。
