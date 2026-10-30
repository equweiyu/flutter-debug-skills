---
name: android-device-database-inspection
description: >-
  Inspect SQLite and SQLite-backed databases inside a debuggable Flutter app
  on a connected Android phone, tablet, or emulator through adb. Use when
  locating, exporting, or querying a debug-app database, diagnosing missing
  or stale rows, or performing an explicitly requested scoped mutation. Keep
  inspection read-only by default; do not use for non-debuggable production
  apps, remote databases, or encrypted stores without their operational access.
metadata:
  short-description: Inspect Android debug databases with guarded writes
  starchild:
    skillKey: android-device-database-inspection
    requires:
      bins: [adb, sqlite3]
---

# Android 设备数据库检查

通过 `adb` 检查已连接 Android 真机或模拟器中 debuggable App 的私有数据库。
默认只读：只将选定的数据库导出到本机临时目录并以只读方式查询，不要求 root，也不读取
无关凭据或个人数据。定位、导出、诊断和查询请求都不授权修改；只有当前请求明确
指定了写入目标与变更，或用户确认了精确写入计划后，才可进入写入流程。

## 写入授权门禁

以下操作都视为写入或状态变更：`INSERT`、`UPDATE`、`DELETE`、`REPLACE`、
架构变更、会写数据库的 `PRAGMA`、替换数据库文件、删除或改名 WAL/SHM、停止或
重启 App，以及恢复备份。

满足以下任一条件才能执行这些操作：

- 当前请求明确授权了具体设备、应用、数据库、变更内容和预期结果。
- 先向用户展示精确计划，并收到明确确认。计划至少包含设备序列号、application
  ID、数据库相对路径、预检查询及预期行数、SQL、备份、App 停止/重启、WAL/SHM
  处理、远程临时文件和恢复方式。

一次确认只覆盖已经展示且没有实质变化的计划。目标、行数、SQL、写入文件、停止
App 或恢复方式发生变化时，重新确认。用户只说“修一下”“把数据改对”或要求排查
异常，不构成写入授权。非 debuggable App 始终不进入写入流程。

## 前置条件

- 安装 Android SDK Platform-Tools 和本机 `sqlite3`。`adb` 可以位于 `PATH` 中，
  也可以从 Android SDK 的 `platform-tools/` 目录直接定位。
- 真机已开启开发者选项和 USB 调试，且已授权当前主机。
- 目标 App 是可调试构建。`flutter run` 通常安装 debug variant，但 build flavor
  可能给 application ID 添加 `.debug` 等后缀。
- 模拟器与真机使用同一流程。不要把 `adb root` 当作默认步骤；它在普通零售版
  真机上通常不可用。

如果目标是 release、非 debuggable 包或线上用户数据，停止操作并说明限制，不要
尝试绕过 Android 沙箱。

## 操作流程

### 1. 固定目标设备与 App

先定位 `adb`。macOS 上的 Android Studio 不一定会把 Platform-Tools 加入 Shell
的 `PATH`；不要因此判断设备不可用。优先使用 `PATH`，缺失时从 Flutter 报告的
Android SDK 中定位：

```bash
ADB="$(command -v adb || true)"

if [[ -z "$ADB" ]]; then
  flutter doctor -v
  ANDROID_SDK="<Android SDK path shown after 'Android SDK at'>"
  ADB="$ANDROID_SDK/platform-tools/adb"
fi

[[ -x "$ADB" ]] || {
  printf 'adb executable not found\n' >&2
  exit 1
}

"$ADB" devices -l

SERIAL="<DEVICE_SERIAL_OR_EMULATOR_ID>"
PACKAGE="<ACTUAL_APPLICATION_ID>"
```

不要写入某台机器的固定 SDK 路径，也不需要为了本技能永久修改 `.zshrc`。后续每条
命令都显式使用 `"$ADB" -s "$SERIAL"`，避免连接多台设备时操作错误目标。从项目
配置、`flutter run -v` 输出或已安装包列表确认实际 application ID，不要猜测：

```bash
"$ADB" -s "$SERIAL" shell pm path "$PACKAGE"
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" id
```

`run-as` 成功说明已选中可调试 App。若返回 `package not debuggable`、包不存在或
权限错误，先核对构建类型、application ID 和设备；不要改用破坏性的提权方案。

### 2. 定位数据库

`run-as` 启动命令时位于 App 私有数据目录。按常见 SQLite 扩展名查找时，把
`find` 表达式作为一个完整的远端 Shell 参数传入，避免 `adb shell` 将未转义括号
重新解释：

```bash
"$ADB" -s "$SERIAL" shell \
  "run-as '$PACKAGE' find . -maxdepth 4 -type f \
  \\( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \\)"
```

如果目标可能没有扩展名，再按目录检查，但只保留与当前问题相关的候选文件：

```bash
"$ADB" -s "$SERIAL" shell run-as "$PACKAGE" find . -maxdepth 4 -type f
```

`sqflite` 通常位于 `databases/`；使用 `path_provider`、Drift 或自定义路径的
数据库可能位于 `files/` 下。不要只检查固定的 `databases/` 目录，也不要根据文件
扩展名认定其一定是 SQLite。

### 3. 导出数据库与 sidecar

优先使用技能目录中的窄范围导出脚本。它要求目标数据库使用相对于 App 数据目录
的路径，并通过 `adb exec-out` 二进制安全地导出主库、存在的 `-wal` 和 `-shm`。
同时传入已定位的 `ADB_BIN`：

```bash
EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-database.XXXXXX")"

ADB_BIN="$ADB" bash "<SKILL_DIR>/scripts/export_android_database.sh" \
  "$SERIAL" \
  "$PACKAGE" \
  "databases/app.db" \
  "$EXPORT_DIR"
```

脚本拒绝绝对路径、`..` 路径、Shell 元字符、非绝对输出目录和同名文件覆盖。
输出文件名沿用远端 basename，例如主库为 `app.db` 时，sidecar 为 `app.db-wal`
和 `app.db-shm`。

如果无法使用脚本，至少逐文件执行：

```bash
"$ADB" -s "$SERIAL" exec-out run-as "$PACKAGE" \
  cat "databases/app.db" > "$EXPORT_DIR/app.db"
```

先确认远端确实存在 `app.db-wal` 或 `app.db-shm`，再按完全相同的主库 basename
导出 sidecar。使用 `adb exec-out` 而不是普通 `adb shell` 重定向，避免二进制内容
被换行转换。不要使用 `adb pull /data/data/...` 作为通用方案。

### 4. 建立只读本地快照

如果 App 正在写入，分多次复制的文件不构成原子快照。需要确定结果时，先请用户
退出目标 App，再重新导出；除非用户明确授权，不要自动执行 `am force-stop`。

在本机从已导出的文件建立快照：

```bash
SNAPSHOT="$EXPORT_DIR/snapshot.db"
sqlite3 -readonly "$EXPORT_DIR/app.db" ".backup '$SNAPSHOT'"
sqlite3 -readonly -header -column "$SNAPSHOT" \
  "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
```

然后依据已发现的 schema 精确查询：

```bash
sqlite3 -readonly "$SNAPSHOT" ".schema <TABLE_NAME>"
sqlite3 -readonly -header -column "$SNAPSHOT" \
  "SELECT * FROM <TABLE_NAME> LIMIT 20;"
```

只使用已经确认的可信表名和列名，不拼接外部输入。记录缺失时，依次核对设备、
包名、数据库路径、WAL/SHM、App 版本和快照时间，不要先判断“数据不存在”。

## 可选 GUI

Android Studio 的 **View > Tool Windows > App Inspection > Database Inspector**
可连接 API 26 及以上的真机或模拟器检查运行中的普通 SQLite 数据库。它适合交互式
浏览；Flutter 插件如果直接使用原生 SQLite，未必能被发现，此时仍以 `adb` 文件
导出为准。使用 GUI 修改表值同样必须满足写入门禁，且修改后仍需验证 App 缓存、
业务状态和异常日志。

## 显式写入

满足写入门禁、确认目标为 debuggable App 中的普通 SQLite，并完成只读预检后，
读取 [references/mutation.md](references/mutation.md)。写入会停止 App、创建
设备内可回滚副本并将经过事务和完整性检查的本地数据库安全写回；不要用普通
`adb push` 直接覆盖 App 私有目录。

## 安全与解释边界

- 导出的数据库属于真实用户数据，只放在权限受限的临时目录；不提交、不上传、
  不写入 Flutter 项目目录，使用后删除。
- 只返回回答当前问题所需的最小字段；不要转贴整表、认证 token、密钥或无关个人
  数据。
- SQLCipher 等加密 SQLite 文件需要持有正确密钥才能查询；本技能不提供密钥提取。
- Realm、Isar、ObjectBox、Hive 等非 SQLite 存储不能使用 `sqlite3` 查询。
- 修改后的数据库只能通过已授权的
  [references/mutation.md](references/mutation.md) 流程写回。不得绕过写入门禁，
  直接把本地副本推送到 `/data/data` 或其他 App 私有目录。
- 设备重启、App 重装、clear-data 或存储迁移后，重新解析实际数据库路径。

## 交付记录

报告至少包含设备序列号或 emulator ID、application ID、远端相对路径、导出了哪些
sidecar、导出是否为 best-effort 快照，以及实际执行的查询。发生写入时，还要报告
已确认的 DML、`changed_rows`、备份与完整性检查、App 停止/重启状态和恢复结果。
其他内容按当前问题最小化输出。
