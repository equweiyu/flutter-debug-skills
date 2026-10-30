---
name: flutter-live-debug
description: >-
  Inspect and diagnose an already-running Flutter debug app through DTD,
  including target identification, runtime errors, Widget Inspector state,
  and controlled hot reload or restart. Use when live runtime evidence is
  needed during debugging or verification; do not use for console-log capture,
  UI interaction, permanent tests, release builds, or visual acceptance.
metadata:
  short-description: Diagnose and reload a running Flutter debug app
---

# Flutter 运行态诊断

在不重新启动 App 的前提下定位当前 Flutter Debug App，并读取运行态证据。默认只读；只有用户要求或当前验证确实需要时才热重载或热重启。

## 职责边界

- 只处理本机、当前工作区的 Debug App。
- 日志采集交给 `flutter-live-console-logs`；点击、输入、滚动或 Controller 调用交给 `flutter-live-control`；截图和录屏交给 `flutter-visual-handoff`。
- 不在承载真实用户数据的主要设备上安装、卸载或启动 Flutter Driver。热重载会重新执行应用代码，必须确认目标 App 不含正在进行的高风险或不可恢复操作。
- VM Service 只能使用回环地址 `127.0.0.1`。禁止绑定 `0.0.0.0`、连接局域网地址或转发调试端口。
- 不输出 VM Service token、密码、凭据、密钥材料、签名载荷或其他敏感数据。

## 选择目标 App

1. 使用当前 Dart MCP 的 `dtd listDtdUris` 枚举 DTD。
2. 选择 `Workspace Root` 与当前仓库完全一致的 DTD，再执行 `dtd connect`。
3. 使用 `dtd listConnectedApps` 查看已连接 App。不能只取第一个；结合 workspaces、设备、包名、启动时间和当前任务确认唯一目标。
4. 目标不唯一或身份不一致时停止操作，说明候选 App 和需要用户确认的差异。

如果 DTD 不可用，只能使用当前终端 `flutter attach` 输出中的回环 URI，并按上述条件确认 App 身份。不要扫描端口、猜测 URI 或复用上一次会话的 token。

## 读取运行态证据

按当前 MCP schema 使用最小范围读取：

- 先读取运行时异常，再判断是否需要 Widget Tree。
- 通过 DTD 或 VM Service 确认 isolate、Flutter extension 和 Driver extension 是否可用。
- Widget Tree 很大时只读取与目标页面、错误节点或 Key 相关的分支，不默认倾倒完整树。
- 普通 `developer.log` 事件使用 `flutter-live-console-logs`，不要用 `get_runtime_errors` 代替日志。
- 结论中区分“已确认事实”和“推测”，记录 App 身份、命中的异常或节点，以及验证时间点。

## 热重载与热重启

默认不执行。确需验证代码修改时：

1. 确认仍然是同一个 App 和目标 isolate，且当前没有支付、认证、敏感写入或其他高风险流程。
2. 优先热重载；只有热重载无法应用改动时才热重启。
3. 热重启后重新枚举 DTD/App URI，并重新检查运行时错误。
4. 不连续盲重试。连续失败或连接断开时保留错误证据并停止。

## 交付

最终只返回与问题相关的诊断结果：

- 目标 App 的可验证身份，不复述完整 token URI。
- 命中的运行时异常、Widget/Extension 状态或热重载结果。
- 已执行的状态变更，以及是否重新检查过运行时错误。
- 后续操作用户需要完成的事项或阻塞原因。
