---
name: flutter-live-control
description: >-
  Operate an already-running Flutter debug app as part of a development,
  reproduction, or verification task. Use for scoped taps, text input,
  scrolling, navigation, and safe app-state actions through iOS IDB, VM
  Service, or Flutter Driver after the target device is confirmed by the user;
  do not use for permanent tests, general diagnosis, release apps, or visual
  acceptance.
metadata:
  short-description: Operate a running Flutter app for development verification
---

# Flutter 运行态控制

在开发、复现或验证 Flutter UI 时，操作当前运行中的 Debug App。先确认能力通道，再执行最小、可恢复的操作；Driver 不可用不等于必须停止，可以按目标切换 IDB 或受限 VM Service。

## 任务授权

用户要求实现、修复或验证当前功能时，任务范围本身包含完成该验证所需的 App 操作，不需要再要求用户逐次确认点击、输入、滚动、页面导航、打开弹层或切换安全展示状态。

Flutter Driver 是例外：首次使用、切换目标设备或切换启动方式前，必须让用户确认设备。可以让用户自行启动 Driver，也可以在用户指定目标设备后使用现有 Driver 启动配置。Flutter Driver 本身不会卸载 App 或删除数据；风险来自会安装/卸载 App 的启动或测试流程。

以下操作即使位于当前任务中，也必须先停止并取得用户明确授权：

- 执行支付、发布、认证、不可逆业务提交或其他具有真实外部副作用的操作。
- 导出或读取密码、认证 token、会话凭据、密钥材料或其他机密信息。
- 删除用户数据、清空数据库、卸载 App、重置设备或其他难以恢复的数据操作。
- 连接非回环地址，或把调试端口暴露给其他机器。
- 无法唯一确认目标 App、设备、页面或被测对象。

## 边界

- 只控制本机 Debug App，连接不离开回环地址。
- 不把运行态操作固化成 `integration_test`、Widget Test 或永久 Driver 配置。
- 不通过运行态控制改变生产数据或用 mock 结果伪造成功。验证需要特殊数据时，优先使用现有 Debug 配置和可恢复的安全状态。
- Flutter Driver 只能用于用户确认过的设备和启动方式；同一任务内，同一设备和启动方式的一次确认可覆盖后续操作。切换设备或启动方式时需要重新确认；未获得确认时，继续使用当前 App 可用的 DTD、IDB 或受限 VM Service。
- `flutter_driver_command` 直接连接用户已启动的 Driver App 时不会安装或卸载 App。Agent 使用 `flutter run -t test_driver/app.dart` 启动后连接；不得在承载真实数据的设备上使用 `flutter drive` 的默认卸载流程，必须使用 `--keep-app-running` 或 `--use-existing-app`。
- `invoke`、`evaluate` 和任意应用代码执行都不是通用接口。目标对象、方法和副作用必须已知且与当前验证目标直接相关。
- 不记录 VM Service token、对象中的敏感字段、密码、凭据、密钥材料或签名载荷。

## 确认目标

先按 `flutter-live-debug` 的 DTD 流程确认唯一 App，并记录 workspaces、设备、包名和启动时间。目标不唯一时停止，不要凭端口或 App 名称猜测。

## 选择执行通道

按可用性和风险从高到低选择：

1. **Flutter Driver**：用户已确认目标设备和启动方式，且 `get_health` 正常时，使用语义 Finder、文本或 Key 完成交互。用户自行启动时直接连接；用户指定设备并允许 Agent 启动时，使用现有 Driver 启动配置。
2. **iOS IDB**：Driver 不可用、尚未获得 Driver 授权或当前任务不需要 Driver 时，使用 `idb list-targets` 确认设备，再读取 UI 层级并操作当前 Debug App：

   ```bash
   idb list-targets
   DEVICE_UDID='<已确认的目标设备 UDID>'
   idb ui describe-all --udid "$DEVICE_UDID"
   ```

   优先使用 `idb ui tap` 点击已从 UI 层级确认的元素，使用 `idb ui text` 输入普通测试文本。不要根据截图猜测坐标，也不要操作支付、认证、敏感写入或凭据相关控件。

3. **受限 VM Service**：UI 自动化不可用，但任务只需要切换已知页面/Controller 状态时，读取 [VM Service 状态控制](references/vm-service-state-control.md)并严格按参考步骤执行。

VM Service 无法安全完成操作时，应提示用户自行启用 Driver，或指定允许使用 Driver 的目标设备。典型情况包括：

- 无法读取到稳定的 Controller/Service 实例。
- 目标方法需要字符串、枚举、对象等参数，而受限 `invoke` 无法安全表达。
- 无法确认目标对象、方法或副作用。
- 操作依赖真实手势、页面动画、Semantics 或 Widget 交互。

提示时说明当前阻塞点、可使用的启动配置，以及启用后可以继续完成哪些验证。用户确认设备或启动 Driver 后，重新枚举 DTD，并先执行 `get_health`，不要复用旧 App URI。不要混淆 Driver 连接与安装/卸载 App 的测试流程。

不要自动安装 IDB、修改入口文件或增加测试依赖。未经用户确认，不得启动 Driver 或切换目标设备；现有通道都不足以安全完成操作时停止并报告。

## 执行交互

Driver 通道：

- 每次操作前确认元素存在，操作后读取目标状态或等待预期元素。
- 使用可读文本、`ValueKey` 或明确组件类型定位；避免猜测坐标。
- 一次只推进一个业务步骤。页面进入、动画完成或异步请求结束后再继续。

IDB 通道：

- 使用 `describe-all` 的语义标签、类型和 bounds 定位，不凭经验直接猜坐标。
- 操作前确认目标文本、按钮状态和目标设备均与当前任务一致。
- 点击、输入后重新读取 UI 或通过 DTD 验证页面状态；不要连续快速点击造成重复提交。
- 涉及滚动时先读取当前 UI 层级，选择可见容器并限制滚动次数。

VM Service 通道：

- 只使用已经确认的 isolate、类和对象，优先调用无参数、无外部副作用的已知方法。
- 对象 ID、isolate ID、端口和 token 都只对当前运行会话有效，不缓存复用。
- 无法确定参数语义、实例唯一性或副作用时停止。不要用通用 `evaluate` 绕过缺失的 Driver 能力。

## 验证与恢复

1. 修改会持久化的页面状态前，记录能够恢复的最小状态信息；普通导航、展开/收起和临时输入不需要额外询问。
2. 操作结束后检查运行时错误，并导航回原页面或恢复原 Controller 状态。
3. 如果操作失败，保留首个根因、当前页面和未恢复状态，不要连续盲重试。
4. 汇报实际使用的通道、执行过的动作、验证结果、恢复结果和未解决的阻塞。
