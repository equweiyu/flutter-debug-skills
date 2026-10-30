# Flutter Debug Skills

[English](README.md) | [简体中文](README.zh-CN.md)

Task-oriented agent skills for Flutter debugging, including database inspection and explicitly authorized debug-data mutation for iOS Simulator and Android.

## Quick Start

### Use the Skills CLI

Run these commands from the root of your Flutter project. Install from GitHub with the Skills CLI:

```bash
npx skills add equweiyu/flutter-debug-skills
```

The command installs at project scope by default and prompts for choices when needed. To inspect the available skills without installing them:

```bash
npx skills add equweiyu/flutter-debug-skills --list
```

Install all skills from this repository, or select one by name:

```bash
npx skills add equweiyu/flutter-debug-skills --skill '*'
npx skills add equweiyu/flutter-debug-skills --skill flutter-live-debug
```

Add `-g` to install for the current user instead of the current project:

```bash
npx skills add equweiyu/flutter-debug-skills --skill '*' -g
```

After installation, reload or rediscover skills in your agent. You can verify project-level installations with `npx skills list`, or user-level installations with `npx skills list -g`.

### Ask an AI Agent to Install

Paste this prompt into an AI coding agent with terminal access:

```text
Install all skills from the GitHub repository equweiyu/flutter-debug-skills into the current Flutter project using the Skills CLI. From the project root, run `npx skills add equweiyu/flutter-debug-skills --skill '*' -y`, targeting the AI agent you are running in. Verify the installation with `npx skills list` and report any failures. Do not modify the project source files.
```

### Install Manually

If the Skills CLI is unavailable, copy the skill directories into your Flutter project, then reload or rediscover them in your agent:

```bash
mkdir -p /path/to/flutter-project/.agents/skills
cp -R skills/* /path/to/flutter-project/.agents/skills/
```

Adjust the destination if your agent uses a different Skill directory.

## Requirements

- Flutter and Dart with DTD and VM Service available for runtime debugging.
- Node.js 22 or later with the global `WebSocket` API for the VM Service control helper.
- macOS and Xcode command-line tools for iOS skills; `sqlite3` is required for database inspection.
- Android database inspection requires Android SDK Platform-Tools (`adb`) and `sqlite3`.
- Use only local debug apps, explicit devices, and loopback debug endpoints.

## Skills

### Flutter Runtime

- [Flutter Console Logs](skills/flutter-live-console-logs/SKILL.md): Capture and replay Flutter console logs.
- [Flutter Live Control](skills/flutter-live-control/SKILL.md): Perform scoped taps, text entry, scrolling, and navigation in a running debug app.
- [Flutter Live Debugging](skills/flutter-live-debug/SKILL.md): Identify the target app through DTD, inspect runtime errors and widget state, and control hot reloads or restarts.
- [Flutter Visual Handoff](skills/flutter-visual-handoff/SKILL.md): Generate screenshots or recordings for visual acceptance by the user.

### Platform Diagnostics

- [Android Database Inspection](skills/android-database-inspection/SKILL.md): Inspect SQLite databases in a debuggable app, with guarded mutations only after explicit authorization.
- [iOS Database Inspection](skills/ios-database-inspection/SKILL.md): Inspect iOS app databases and perform explicitly authorized Simulator mutations with backup, validation, and recovery.

## Design Principles

- Each skill solves one specific Flutter debugging task.
- Each skill remains self-contained, discoverable, and loadable on demand by agents.
- Code and commands use English; explanatory documentation may use Chinese.
- Never commit secrets, internal addresses, private code, or sensitive data.

## License

This project is licensed under the [MIT License](LICENSE).

## Security

Report vulnerabilities privately according to the [security policy](SECURITY.md).
