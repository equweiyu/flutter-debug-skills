# iOS Simulator 数据库访问

在设备 `Reality` 为 `simulated` 时使用本流程。模拟器的数据容器位于 Mac 文件
系统，不需要通过 `devicectl` 传输文件。

## 定位容器与数据库

1. 列出已启动的设备；存在多个设备时，明确选择完整 UDID：

   ```bash
   xcrun simctl list devices booted
   ```

2. 从项目配置或已安装 App 列表确认 Bundle ID，不要猜测：

   ```bash
   xcrun simctl listapps "<SIMULATOR_UDID>"
   ```

3. 每次检查都重新解析数据容器；重装 App 会改变容器 UUID：

   ```bash
   SIM_DATA_CONTAINER="$(
     xcrun simctl get_app_container \
       "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" data
   )"
   ```

   App Group 数据库先列出分组，再解析已知分组标识：

   ```bash
   xcrun simctl get_app_container \
     "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" groups

   xcrun simctl get_app_container \
     "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>" "<APP_GROUP_IDENTIFIER>"
   ```

4. 在解析出的容器中搜索候选数据库，不要预设目录或文件名：

   ```bash
   find "$SIM_DATA_CONTAINER" -type f \
     \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print
   ```

   如果已知应用可能使用无扩展名 SQLite 文件，再按应用代码中的路径或文件类型
   缩小范围，不要遍历并查询所有文件。

## 一致性快照

模拟器文件可以直接用 `sqlite3 -readonly` 查询。App 活跃时，读取会使用同目录下
已有的 WAL/SHM；单次查询可以工作，但多次查询不保证对应同一应用时刻。

需要稳定的本地产物时，先确认停止 Debug App 不影响用户当前工作，再执行：

```bash
xcrun simctl terminate "<SIMULATOR_UDID>" "<APP_BUNDLE_ID>"
sqlite3 -readonly "<DATABASE_PATH>" \
  ".backup '/tmp/ios-simulator-database-snapshot.db'"
```

如果必须直接复制文件，先停止 App，并同时保留匹配的 `.db`、`-wal` 和 `-shm`。
不要尝试用 `xcrun devicectl device info files` 或
`xcrun devicectl device copy from` 处理模拟器；这两个能力只适用于真机。

## 交付记录

报告 Simulator UDID、Bundle ID、解析后的容器类型与路径、数据库路径、是否建立
快照以及实际执行的只读查询。
