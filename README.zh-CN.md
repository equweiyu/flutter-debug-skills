# Flutter Debug Skills

[English](README.md) | [简体中文](README.zh-CN.md)

面向 Flutter 调试的任务型 Agent Skills。iOS 数据库检查属于辅助平台工具；后续会随技能集合扩充补充 Android 工具。

## 快速开始

将 Skill 目录复制到 Flutter 项目，然后让 Agent 重新加载或发现它们：

```bash
mkdir -p /path/to/flutter-project/.agents/skills
cp -R skills/* /path/to/flutter-project/.agents/skills/
```

如果你的 Agent 使用其他 Skill 目录，请相应调整目标路径。

## 前置条件

- Flutter 和 Dart，并确保运行态调试所需的 DTD 与 VM Service 可用。
- Node.js 22 或更高版本，并支持全局 `WebSocket` API，供 VM Service 控制辅助脚本使用。
- iOS 相关 Skill 需要 macOS 和 Xcode Command Line Tools；数据库检查还需要 `sqlite3`。
- 只操作本机 Debug App、明确指定的设备，并使用回环调试地址。

## Skills

### Flutter 运行态

- [Flutter 控制台日志](skills/flutter-live-console-logs/SKILL.md)：采集和回放 Flutter 控制台日志。
- [Flutter 运行态控制](skills/flutter-live-control/SKILL.md)：在已运行的 Debug App 中执行点击、输入、滚动和导航等受限操作。
- [Flutter 运行态诊断](skills/flutter-live-debug/SKILL.md)：通过 DTD 确认目标 App，读取异常与 Widget 状态，并受控执行热重载或热重启。
- [Flutter 视觉验收交付](skills/flutter-visual-handoff/SKILL.md)：生成截图或录屏文件，供用户完成视觉验收。

### 平台诊断工具

- [iOS Simulator 数据库检查](skills/ios-simulator-database-inspection/SKILL.md)：对 iOS Simulator 数据库执行只读检查。
- [iOS 真机数据库检查](skills/ios-physical-device-database-inspection/SKILL.md)：从已连接的物理 iOS 设备导出选定的 App 数据库并执行只读检查。

后续计划补充 Android 平台工具。

## 设计原则

- 每个 Skill 面向一个明确的 Flutter 调试任务。
- 每个 Skill 保持自包含，便于 Agent 发现和按需加载。
- 代码和命令使用英文；说明文档可使用中文。
- 不提交机密信息、内网地址、私有代码或敏感数据。

## 许可证

本项目使用 [MIT License](LICENSE) 授权。

## 安全

请按照[安全策略](SECURITY.md)私下报告漏洞。
