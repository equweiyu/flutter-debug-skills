---
name: ios-physical-device-database-inspection
description: >-
  Inspect SQLite and SQLite-backed Core Data databases in an app or App Group
  container on a connected physical iOS device through xcrun devicectl. Use
  when locating or querying a debug-device database, exporting selected files
  for read-only inspection, or diagnosing missing or stale rows; do not use for
  simulator containers, live data mutation, or credential extraction.
metadata:
  short-description: Inspect app databases on a connected physical iOS device
  starchild:
    skillKey: ios-physical-device-database-inspection
    requires:
      bins: [xcrun, sqlite3]
---

# iOS 真机数据库检查

通过 `xcrun devicectl` 定位已连接物理设备中的 App 数据，只导出需要检查的
SQLite 文件，在本机以只读方式查询。默认不向设备写文件、不修改数据库，也不读取
密码、认证 token、密钥材料或其他凭据。

## 前置条件

- 使用 Xcode 附带的 `xcrun devicectl`；先用 `xcrun devicectl --version` 确认可用。
- 真机已解锁、已信任这台 Mac，并已开启 Developer Mode。
- App 通常需要是使用 Xcode/开发签名安装的第三方 App。设备上的系统 App、
  企业签名 App 或无法访问容器校验信息的 App 不保证开放数据容器。

## 操作流程

### 1. 明确选择物理设备

列出 CoreDevice 已知设备，确认 `Reality` 为 `physical`，并使用完整 UDID：

```bash
xcrun devicectl list devices
```

设备名称可能重复；不要长期依赖可变的设备名。连接多台设备或后续报告结果时，
固定使用 UDID、序列号或 ECID，并确认目标处于 `connected` 状态。

### 2. 确认 App 与数据容器

从项目配置或设备安装列表获取真实 bundle identifier，不要猜测：

```bash
xcrun devicectl device info apps \
  --device "<DEVICE_UDID>" \
  --bundle-id "<APP_BUNDLE_ID>" \
  --include-container-paths \
  --include-app-group-identifiers \
  --json-output -
```

重点核对 `dataContainerPath`、`bundleContainerPath` 和
`groupContainerPaths`。路径位于真机的 `/private/var/mobile/...` 命名空间，
不能直接从 macOS 文件系统访问。

### 3. 查找数据库

普通 App 数据库使用 `appDataContainer`，App Group 数据库使用
`appGroupDataContainer`。按扩展名搜索，不假设目录或文件名：

```bash
xcrun devicectl device info files \
  --device "<DEVICE_UDID>" \
  --domain-type appDataContainer \
  --domain-identifier "<APP_BUNDLE_ID>" \
  --search ".db" \
  --columns "*"
```

再搜索 `.sqlite`、`.sqlite3`，以及可能的无扩展名 SQLite 文件。输出中的
`Name` 是相对容器根目录的路径，后续 `--source` 使用这个路径。

App Group 容器改用：

```bash
xcrun devicectl device info files \
  --device "<DEVICE_UDID>" \
  --domain-type appGroupDataContainer \
  --domain-identifier "<APP_GROUP_IDENTIFIER>" \
  --columns "*"
```

### 4. 导出选中文件

真机没有可供 `sqlite3` 直接打开的本机路径；需要查询内容时，至少导出目标
数据库。先创建权限受限的临时目录：

```bash
EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ios-device-database.XXXXXX")"

xcrun devicectl device copy from \
  --device "<DEVICE_UDID>" \
  --domain-type appDataContainer \
  --domain-identifier "<APP_BUNDLE_ID>" \
  --source "<RELATIVE_DATABASE_PATH>" \
  --destination "$EXPORT_DIR/"
```

文件结果形如：

```text
Documents/app_example.db
Documents/app_example.db-wal
Documents/app_example.db-shm
```

如果远端存在 `-wal` 或 `-shm` sidecar，把每个 sidecar 也逐一复制到同一个
目录。不要只复制主 `.db` 后据此判断“没有新数据”；未合并的提交可能仍在 WAL。

`devicectl` 只提供文件传输，不提供运行中 SQLite 数据库的事务快照。App 活跃时
导出属于 best-effort：

- 能接受短时间窗口内的轻微不一致时，可复制主库和当时存在的 sidecar 后直接检查。
- 需要确定的快照时，先请用户退出 App，再导出并核对导出前后文件列表。
- 必要时可在获得用户明确授权后，用
  `xcrun devicectl device process terminate --device "<DEVICE_UDID>" --pid "<PID>"`
  停止目标进程；先用
  `xcrun devicectl device info processes --device "<DEVICE_UDID>" --search "<APP_BUNDLE_ID>"`
  确认 PID。不要默认强制退出。

### 5. 建立本地只读快照

对导出的主库执行 SQLite backup，再查询快照；这一步只写本机临时文件：

```bash
DB_COPY="$EXPORT_DIR/<DATABASE_FILENAME>"
SNAPSHOT="$EXPORT_DIR/snapshot.db"

sqlite3 "$DB_COPY" ".backup '$SNAPSHOT'"
sqlite3 -readonly -header -column "$SNAPSHOT" \
  "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
```

然后按已发现的 schema 精确查询：

```bash
sqlite3 -readonly "$SNAPSHOT" ".schema <TABLE_NAME>"
sqlite3 -readonly -header -column "$SNAPSHOT" \
  "SELECT * FROM <TABLE_NAME> LIMIT 20;"
```

只使用受信任的表名和列名；不要拼接用户输入。Core Data 或 ORM 生成的表名和
关系需要结合项目模型解释，不能仅凭表名推断业务含义。

## 安全与解释边界

- 导出的数据库是真实用户数据，不提交、不上传、不写入项目目录；用完立即移除
  临时导出目录。
- 只返回回答当前问题所需的字段。不要转贴完整表、密钥材料、认证 token 或无关
  个人数据。
- Realm、Isar、ObjectBox 等非 SQLite 文件即使位于同一容器也不能用 `sqlite3`
  查询。
- 查不到预期行时，依次核对物理设备、bundle identifier、App/App Group 域、
  数据库路径、WAL/SHM 和 App 版本；不要先下“数据不存在”的结论。
- 不提供把本地副本写回真机来修改线上数据的流程；这可能在 App 正在使用数据库
  时破坏 WAL、触发数据损坏或覆盖后续写入。

## 交付记录

报告至少包含设备 UDID、App bundle identifier、数据域和标识符、远端相对路径、
是否导出了 sidecar、快照是否为 best-effort，以及实际执行的只读查询。其他内容
按问题最小化输出。
