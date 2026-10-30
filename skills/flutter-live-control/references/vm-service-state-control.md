# VM Service 状态控制

只在 Flutter Driver 和当前可用的 UI 自动化通道都不足以完成当前开发/验证任务，并且目标操作不涉及支付、认证、凭据或不可恢复副作用时使用。优先调用 App 已暴露的 Debug-only VM Service extension；没有 extension 时，才考虑读取已知 Controller 并调用无参数方法。

## 前置确认

- 当前 VM Service URI 必须包含回环地址 `127.0.0.1`，并且来自本次 DTD 或 `flutter attach` 会话。
- 已按 workspace、设备、包名和启动时间确认唯一 App。
- 已确认目标 isolate、Controller 类名、方法名、参数及副作用。
- 已记录操作前状态和恢复动作。

不要在日志或命令输出中显示完整 token URI。若工具会回显 URI，只保留端口和必要的 identify 信息。

## 读取目标

Dart MCP 负责 DTD 发现、Driver 和 Widget Inspector，但不提供通用的 VM Service 对象读取/调用工具。需要直接读取对象时，使用 Skill 自带的受限 RPC 客户端，按以下只读调用顺序执行：

```text
getVM
getIsolate { isolateId }
getClassList { isolateId }
getInstances { isolateId, objectId, limit }
getObject { isolateId, objectId }
```

`getInstances.objectId` 必须是目标类的 Class ID，例如 `classes/123`；不要传历史文档中的 `classId` 字段。

示例：

```bash
VM_SERVICE_WS_URI='<本次 DTD 返回的 127.0.0.1 App URI>'

node .agents/skills/flutter-live-control/scripts/vm_service_rpc.mjs \
  --uri "$VM_SERVICE_WS_URI" \
  --method getVM
```

脚本只接受回环地址、固定方法和结构校验后的参数。需要读取类或对象时，把本轮返回的临时 ID 作为 JSON 参数传入；不要把 ID 写回 Skill 或跨会话复用。

要求：

- 按完整类名和库来源筛选，不能只按短名称匹配。
- `getInstances` 只取完成任务所需的少量实例；存在多个可能实例时停止并请求用户确认。
- 读取对象后确认字段、方法存在且属于预期类型。
- isolate ID、class ID、object ID 都是临时值。下次连接或热重启后重新读取。

## 执行已知方法

仅在方法无参数、无外部副作用，且返回状态可以验证时使用。脚本强制要求 `argIds` 是空数组，并校验 `selector` 为合法 Dart 标识符：

```bash
node .agents/skills/flutter-live-control/scripts/vm_service_rpc.mjs \
  --uri "$VM_SERVICE_WS_URI" \
  --method invoke \
  --params '{"isolateId":"<isolate-id>","targetId":"<object-id>","selector":"<knownMethodName>","argIds":[]}'
```

- 调用前确认 `selector` 是已经读取到的方法，不要尝试猜测。
- 需要字符串、枚举、对象或其他参数时，不要用任意 `evaluate` 构造调用图。优先改用 Driver 或在 App 中增加明确的 Debug-only extension。
- `evaluate` 只允许在执行前向用户说明表达式、目标库和副作用，并获得明确授权后使用。
- 受限客户端不实现 `evaluate`，也不接受任意方法名。
- 禁止调用支付、发布、认证、凭据读取、敏感写入和任何可能产生真实外部副作用的方法。

## 验证与恢复

1. 操作后重新读取目标状态，确认状态变化符合预期。
2. 读取运行时错误，确认没有新增异常。
3. 执行预先确定的恢复动作，并再次验证恢复结果。
4. 连接中断、对象消失或结果不明确时停止；不要复用旧 ID 或猜测新的实例。

## 能力不足时

以下情况说明 VM Service 通道不适合继续：

- 找不到唯一、类型明确的 Controller 或 Service。
- 目标方法有参数，或参数语义、实例生命周期无法确认。
- 操作需要真实点击、输入、滚动、Semantics、动画或 Widget 状态验证。
- `invoke` 返回结果不足以证明目标行为已经发生。

此时停止状态调用，保留已经确认的 isolate/class/instance 证据，并提示用户自行启用 Flutter Driver，或指定允许使用 Driver 的目标设备。说明所需启动方式、阻塞原因和 Driver 可继续执行的步骤；Flutter Driver 本身不卸载 App，安装/卸载风险来自集成测试或 `flutter drive` 的默认卸载流程。未经用户确认，不要启动 Driver、修改入口文件、安装依赖或猜测新的调用方式。
