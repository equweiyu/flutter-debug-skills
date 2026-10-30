# Flutter Debug Skills

[English](README.md) | [简体中文](README.zh-CN.md)

Task-oriented agent skills for Flutter debugging. iOS database inspection is included as supporting platform tooling; Android tools will be added as the collection grows.

## Quick Start

Copy the skill directories into your Flutter project, then reload or rediscover them in your agent:

```bash
mkdir -p /path/to/flutter-project/.agents/skills
cp -R skills/* /path/to/flutter-project/.agents/skills/
```

Adjust the destination if your agent uses a different Skill directory.

## Requirements

- Flutter and Dart with DTD and VM Service available for runtime debugging.
- Node.js 22 or later with the global `WebSocket` API for the VM Service control helper.
- macOS and Xcode command-line tools for iOS skills; `sqlite3` is required for database inspection.
- Use only local debug apps, explicit devices, and loopback debug endpoints.

## Skills

### Flutter Runtime

- [Flutter Console Logs](skills/flutter-live-console-logs/SKILL.md): Capture and replay Flutter console logs.
- [Flutter Live Control](skills/flutter-live-control/SKILL.md): Perform scoped taps, text entry, scrolling, and navigation in a running debug app.
- [Flutter Live Debugging](skills/flutter-live-debug/SKILL.md): Identify the target app through DTD, inspect runtime errors and widget state, and control hot reloads or restarts.
- [Flutter Visual Handoff](skills/flutter-visual-handoff/SKILL.md): Generate screenshots or recordings for visual acceptance by the user.

### Platform Diagnostics

- [iOS Simulator Database Inspection](skills/ios-simulator-database-inspection/SKILL.md): Inspect iOS Simulator databases using read-only queries.
- [iOS Physical-Device Database Inspection](skills/ios-physical-device-database-inspection/SKILL.md): Export selected app databases from a connected physical iOS device for read-only inspection.

Android platform tools are planned.

## Design Principles

- Each skill solves one specific Flutter debugging task.
- Each skill remains self-contained, discoverable, and loadable on demand by agents.
- Code and commands use English; explanatory documentation may use Chinese.
- Never commit secrets, internal addresses, private code, or sensitive data.

## License

This project is licensed under the [MIT License](LICENSE).

## Security

Report vulnerabilities privately according to the [security policy](SECURITY.md).
