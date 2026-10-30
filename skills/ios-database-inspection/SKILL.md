---
name: ios-database-inspection
description: >-
  Inspect SQLite and SQLite-backed Core Data databases inside iOS Simulator or
  physical iOS device app and App Group containers. Use when locating,
  exporting, snapshotting, or querying a debug app database through simctl or
  devicectl, or when a user explicitly requests a scoped Simulator mutation.
  Keep inspection read-only by default; do not use for physical-device writes,
  credential extraction, or non-SQLite stores.
metadata:
  short-description: Inspect iOS databases with guarded Simulator writes
  starchild:
    skillKey: ios-database-inspection
    requires:
      bins: [xcrun, sqlite3]
---

# iOS 数据库检查

检查 iOS Simulator 或已连接物理 iOS 设备中 App 与 App Group 的 SQLite
数据库。默认只读。定位、导出、诊断和查询请求都不授权写入；只有当前请求明确
指定了写入目标与变更，或用户确认了精确写入计划后，才可进入模拟器写入流程。

## 选择设备与访问方式

1. 明确目标设备和 Bundle ID。优先使用用户提供的完整 UDID；存在多个设备时不要
   使用有歧义的设备名，也不要猜测 Bundle ID。
2. 设备类型不明确时，列出设备并读取 `Reality`：

   ```bash
   xcrun devicectl list devices
   ```

   选择与 UDID 对应的行，并根据项目配置或已安装 App 列表确认 Bundle ID。
   `devicectl` 不列出目标模拟器时，再用 `xcrun simctl list devices booted`
   确认。

3. 根据 `Reality` 进入对应流程，并且只读取该模式需要的参考文档：

   | `Reality` | 数据访问方式 | 详细流程 |
   | --- | --- | --- |
   | `simulated` | 模拟器容器位于 Mac 本机文件系统 | [references/simulator.md](references/simulator.md) |
   | `physical` | 从真机容器导出选定文件后在本机查询 | [references/physical-device.md](references/physical-device.md) |

   `devicectl` 可能识别并列出模拟器，但模拟器不支持它的列文件和文件传输能力。
   因此模拟器仍使用 `simctl` 解析容器并直接访问本机路径；真机使用
   `devicectl` 查询及导出文件。不要把真机导出步骤套用到模拟器。

## 写入授权门禁

以下操作都视为写入或状态变更：`INSERT`、`UPDATE`、`DELETE`、`REPLACE`、
架构变更、会写数据库的 `PRAGMA`、替换数据库文件、删除或改名 WAL/SHM、停止或
重启 App，以及恢复备份。

满足以下任一条件才能执行这些操作：

- 当前请求明确授权了具体设备、应用、数据库、变更内容和预期结果。
- 先向用户展示精确计划，并收到明确确认。计划至少包含 UDID、Bundle ID、
  Container、数据库相对路径、预检查询及预期行数、SQL、备份、App 停止/重启、
  WAL/SHM 处理和恢复方式。

一次确认只覆盖已经展示且没有实质变化的计划。目标、行数、SQL、写入文件、停止
App 或恢复方式发生变化时，重新确认。用户只说“修一下”“让数据正确”或要求排查
异常，不构成写入授权。

写入流程仅适用于 `simulated` 设备。真机当前只支持导出和只读检查，不提供把本地
副本写回物理设备的流程；用户要求真机写入时停止并说明限制。

## 只读检查

按所选参考文档定位数据库。App 数据库通常位于 App Data Container；共享数据库
需要检查 App Group Container，不要只根据文件扩展名或固定目录判断。

使用只读 SQLite 连接检查已确认的数据库或本机快照：

```bash
sqlite3 -readonly -header -column "<DATABASE_PATH>" \
  "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"

sqlite3 -readonly "<DATABASE_PATH>" ".schema <TABLE_NAME>"

sqlite3 -readonly -header -column "<DATABASE_PATH>" \
  "SELECT * FROM <TABLE_NAME> LIMIT 20;"
```

只使用从 schema 中确认的可信表名和列名构造无参数诊断查询。路径可能包含空格，
必须加引号。SQLite-backed Core Data 可以检查，但生成的 schema 属于实现细节；
不要仅凭表名推断业务语义。

SQLite 可能把近期提交保存在 `-wal`，协调状态保存在 `-shm`。需要稳定产物时，
按参考文档保留匹配的 sidecar 或建立 SQLite backup；不要只复制或读取主库后据此
判断“没有新数据”。Realm、Isar、ObjectBox 等非 SQLite 存储不能使用 `sqlite3`
查询，即使文件位于同一容器中。

## 安全与交付

- 导出的数据库可能包含真实用户数据，不提交、不上传、不写入项目目录；用完立即
  清理临时文件。
- 只读取回答当前问题所需的字段。不要在日志或摘要中输出凭据、认证 token、密钥
  材料或无关个人数据。
- 记录设备 UDID、Bundle ID、数据域、数据库相对路径、WAL/SHM 处理方式和实际
  查询。查不到预期数据时，先核对设备、容器、数据库文件和快照方式，不要直接得出
  “数据不存在”的结论。
- 满足写入门禁后，只读取
  [references/simulator-mutation.md](references/simulator-mutation.md)，并在
  报告中记录备份、受影响行数、完整性检查、App 状态和恢复结果。任何恢复操作也
  必须属于已确认计划，或再次获得确认。
