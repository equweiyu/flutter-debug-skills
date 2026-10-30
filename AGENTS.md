# Repository Guidelines

This repository publishes task-oriented agent skills for Flutter debugging. iOS database inspection is supporting platform tooling, and Android tools will be added as the collection grows. Keep each skill focused, self-contained, and safe to discover independently.

## Project Structure & Module Organization

- `README.md` is the English skill index; `README.zh-CN.md` is its Chinese counterpart.
- `LICENSE` contains the repository's MIT License.
- `SECURITY.md` defines the private vulnerability-reporting process.
- `skills/<skill-name>/SKILL.md` is required and defines one bounded task.
- `skills/<skill-name>/agents/openai.yaml` provides the agent-facing display name and short description.
- `skills/<skill-name>/scripts/` contains executable helpers.
- `skills/<skill-name>/references/` contains detailed supporting guidance.

There is no application source tree, shared package, or asset directory. Use cross-platform `flutter-*` names and platform-specific `ios-*` or future `android-*` names. The directory must match the `name` field in `SKILL.md`, and the front matter must include a description and `metadata.short-description`.

## Build, Test, and Development Commands

There is no application build. Run the repository check from the root after every change:

```bash
make check
```

`make check` validates repository structure, documentation parity, formatting, Dart analysis, regression tests, and JavaScript syntax. Use `make test` for the Dart regression tests alone.

## Coding Style & Naming Conventions

Follow `.editorconfig`: UTF-8, LF line endings, two-space indentation, a final newline, and no trailing whitespace. Write code, commands, and identifiers in English; Chinese explanatory documentation is acceptable. Keep Markdown headings descriptive and tag code fences with the correct language.

## Testing Guidelines

There is no external test framework or coverage target yet. Run the standalone Dart regression tests before live-environment testing. Test behavior changes against an isolated Flutter debug app, simulator, or explicitly identified device. Record prerequisites, commands, expected results, and affected platform versions. Never use real user activity, credentials, or destructive database operations as test data.

## Commit & Pull Request Guidelines

Use short imperative commit subjects and optional scoped prefixes, such as `feat(flutter-live-debug): add hot reload checks`. Pull requests should describe the affected skills, list validation performed, identify required tools or devices, link related issues, and include screenshot or recording paths for visual changes.

## Security & Agent-Specific Instructions

Default to read-only behavior. Use VM Service only through `127.0.0.1`, require confirmation for destructive or high-risk actions, and never commit credentials, private keys, signed payloads, internal addresses, or sensitive data. Update both README indexes and run `make check` when adding or renaming a skill.
