# Flutter Debug Skills

[English](README.md) | [简体中文](README.zh-CN.md)

面向 Flutter 调试的任务型 Agent Skills，包含 iOS 与 Android 的数据库检查，以及需要显式授权的调试数据修改流程。

## 快速开始

### 使用 Skills CLI 安装

请在 Flutter 项目根目录执行以下命令，从 GitHub 使用 Skills CLI 安装：

```bash
npx skills add equweiyu/flutter-debug-skills
```

命令默认安装到当前项目，并在需要时提示选择目标 Agent。安装前可以先查看仓库中可用的 Skill：

```bash
npx skills add equweiyu/flutter-debug-skills --list
```

安装仓库中的全部 Skill，或按名称安装指定 Skill：

```bash
npx skills add equweiyu/flutter-debug-skills --skill '*'
npx skills add equweiyu/flutter-debug-skills --skill flutter-live-debug
```

添加 `-g` 可以安装到当前用户目录，而不是当前项目：

```bash
npx skills add equweiyu/flutter-debug-skills --skill '*' -g
```

安装后，让 Agent 重新加载或发现 Skill。可以使用 `npx skills list` 检查项目级安装，或使用 `npx skills list -g` 检查用户级安装。

### 交给 AI Agent 安装

将下面这段提示词交给有终端访问权限的 AI 编码 Agent：

```text
请使用 Skills CLI 将 GitHub 仓库 equweiyu/flutter-debug-skills 中的全部 Skill 安装到当前 Flutter 项目。在项目根目录运行 `npx skills add equweiyu/flutter-debug-skills --skill '*' -y`，并将你当前运行的 AI Agent 作为安装目标。使用 `npx skills list` 验证安装结果，并报告失败项。不要修改项目源文件。
```

### 手动安装

如果无法使用 Skills CLI，可以将 Skill 目录复制到 Flutter 项目，然后让 Agent 重新加载或发现它们：

```bash
mkdir -p /path/to/flutter-project/.agents/skills
cp -R skills/* /path/to/flutter-project/.agents/skills/
```

如果你的 Agent 使用其他 Skill 目录，请相应调整目标路径。

## 前置条件

- Flutter 和 Dart，并确保运行态调试所需的 DTD 与 VM Service 可用。
- Node.js 22 或更高版本，并支持全局 `WebSocket` API，供 VM Service 控制辅助脚本使用。
- iOS 相关 Skill 需要 macOS 和 Xcode Command Line Tools；数据库检查还需要 `sqlite3`。
- Android 数据库检查需要 Android SDK Platform-Tools（`adb`）和 `sqlite3`。
- 只操作本机 Debug App、明确指定的设备，并使用回环调试地址。

## Skills

### Flutter 运行态

- [Flutter 控制台日志](skills/flutter-live-console-logs/SKILL.md)：采集和回放 Flutter 控制台日志。
- [Flutter 运行态控制](skills/flutter-live-control/SKILL.md)：在已运行的 Debug App 中执行点击、输入、滚动和导航等受限操作。
- [Flutter 运行态诊断](skills/flutter-live-debug/SKILL.md)：通过 DTD 确认目标 App，读取异常与 Widget 状态，并受控执行热重载或热重启。
- [Flutter 视觉验收交付](skills/flutter-visual-handoff/SKILL.md)：生成截图或录屏文件，供用户完成视觉验收。

### 平台诊断工具

- [Android 数据库检查](skills/android-database-inspection/SKILL.md)：检查 debuggable App 的 SQLite 数据库，仅在显式授权后执行带备份和校验的修改。
- [iOS 模拟器与真机数据库检查](skills/ios-database-inspection/SKILL.md)：默认只读检查 iOS App 数据库，并支持经过显式授权的模拟器备份、修改、校验和恢复流程。

## 设计原则

- 每个 Skill 面向一个明确的 Flutter 调试任务。
- 每个 Skill 保持自包含，便于 Agent 发现和按需加载。
- 代码和命令使用英文；说明文档可使用中文。
- 不提交机密信息、内网地址、私有代码或敏感数据。

## 许可证

本项目使用 [MIT License](LICENSE) 授权。

## 安全

请按照[安全策略](SECURITY.md)私下报告漏洞。
