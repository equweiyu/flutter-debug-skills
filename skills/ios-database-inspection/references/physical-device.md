# iOS 真机数据库访问

在设备 `Reality` 为 `physical` 时使用本流程。通过 `xcrun devicectl` 定位已连接
物理设备中的 App 数据，只导出需要检查的 SQLite 文件，再在本机只读查询。

## 前置条件

- 使用 Xcode 附带的 `xcrun devicectl`；先用 `xcrun devicectl --version`
  确认可用。
- 真机已解锁、已信任这台 Mac，并已开启 Developer Mode。
- App 通常需要是使用 Xcode/开发签名安装的第三方 App。设备上的系统 App、企业
  签名 App 或无法访问容器校验信息的 App 不保证开放数据容器。

## 选择设备并确认 App

使用完整 UDID 选择目标设备，并确认对应行的 `Reality` 为 `physical`、状态可以
连接：

```bash
xcrun devicectl list devices
```

从项目配置或设备安装列表获取真实 Bundle ID，不要猜测：

```bash
xcrun devicectl device info apps \
  --device "<DEVICE_UDID>" \
  --bundle-id "<APP_BUNDLE_ID>" \
  --include-container-paths \
  --include-app-group-identifiers \
  --json-output -
```

重点核对 `dataContainerPath`、`bundleContainerPath` 和
`groupContainerPaths`。这些路径位于真机的 `/private/var/mobile/...`
命名空间，不能直接从 macOS 文件系统读取。

## 查找数据库

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

再搜索 `.sqlite`、`.sqlite3`，以及已知可能存在的无扩展名 SQLite 文件。输出中的
`Name` 是相对容器根目录的路径，后续 `--source` 使用这个路径。

App Group 容器改用：

```bash
xcrun devicectl device info files \
  --device "<DEVICE_UDID>" \
  --domain-type appGroupDataContainer \
  --domain-identifier "<APP_GROUP_IDENTIFIER>" \
  --columns "*"
```

## 导出并建立本地快照

真机路径不能由本机 `sqlite3` 直接打开。先创建权限受限的临时目录，再只导出选定
数据库：

```bash
EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ios-device-database.XXXXXX")"

xcrun devicectl device copy from \
  --device "<DEVICE_UDID>" \
  --domain-type appDataContainer \
  --domain-identifier "<APP_BUNDLE_ID>" \
  --source "<RELATIVE_DATABASE_PATH>" \
  --destination "$EXPORT_DIR/"
```

文件结果通常形如 `Documents/app.db`。如果远端存在匹配的 `-wal` 或 `-shm`，
把每个 sidecar 也逐一复制到相同相对路径。不要只复制主库后判断“没有新数据”。

`devicectl` 不提供运行中 SQLite 数据库的事务快照。App 活跃时导出属于
best-effort：

- 能接受短时间窗口内轻微不一致时，复制主库和当时存在的 sidecar 后检查。
- 需要确定快照时，先请用户退出 App，再导出并核对导出前后的文件列表。
- 必要时可在获得用户明确授权后停止目标进程。先用
  `xcrun devicectl device info processes` 确认 PID，再用
  `xcrun devicectl device process terminate`；不要默认强制退出。

对导出的主库执行 SQLite backup，再查询本地快照：

```bash
SNAPSHOT="$EXPORT_DIR/snapshot.db"
DB_COPY="$EXPORT_DIR/<DATABASE_FILENAME>"

sqlite3 "$DB_COPY" ".backup '$SNAPSHOT'"
sqlite3 -readonly -header -column "$SNAPSHOT" \
  "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
```

完成后立即清理由本次任务创建的临时导出目录。

## 写入限制

当前流程不提供修改后的数据库写回物理设备的步骤。不要在本地修改导出副本后尝试
覆盖真机数据库，也不要借此修改线上或生产数据。用户要求真机写入时停止并说明
当前只支持导出与只读检查。

## 交付记录

报告设备 UDID、Bundle ID、数据域和标识符、数据库相对路径、是否导出 sidecar、
快照是否属于 best-effort，以及实际执行的只读查询。
