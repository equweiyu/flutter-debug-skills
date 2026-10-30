---
name: flutter-visual-handoff
description: >-
  Capture screenshots or recordings of a running Flutter app for visual
  handoff. Default to local file paths without viewing image content; show
  artifacts inline or inspect the evidence needed for diagnosis only when the
  user requests it. Use for visual acceptance; do not use for Widget/Golden
  tests, automated pixel comparison, or source assets.
metadata:
  short-description: Hand off Flutter visuals with optional inline review
---

# Flutter 视觉验收交付

当动画、转场、间距、颜色、层级或图标位置需要最终验收时，默认生成本地截图或录屏文件并交给用户查看。只有用户明确要求 Agent 看图或分析视觉问题时，才把判断所需的视觉证据读取到上下文。

## 默认策略与例外

- **默认文件模式**：不调用 `view_image`，不把图片作为工具输入，不把 base64、像素数据或完整图片工具 JSON 写入上下文。
- **用户界面展示模式**：用户明确说“发出来看”“直接展示截图”等时，可在最终回复中用本地绝对路径的 Markdown 图片语法展示。该模式只负责让用户看到，不先调用图片读取工具。
- **Agent 视觉分析模式**：用户明确说“你来看”“帮我判断动画/间距/颜色”或长期规则已授权时，才读取图片。按正确判断所需的证据范围读取，不预设图片数量；单张画面足够时不扩展，涉及动画、时序或前后差异时读取必要的多张图或关键帧。避免重复、无关或没有目的的全量读取。
- 不新增 Widget/Golden 测试，不把截图文件加入源码资源或提交产物。
- 不使用真实支付、认证、凭据或敏感用户数据作为展示状态。需要敏感画面时请用户自行验收，或使用隔离的测试数据。
- 用户用文字描述视觉问题时，直接修改并生成一组新的文件；除非用户要求分析，不自动读取修改前后的图片。

## 准备

1. 优先复用当前 Debug App；需要改变页面状态时，通过 `flutter-live-control` 执行最小且可恢复的操作。
2. 明确目标设备。存在多个模拟器或设备时使用准确 UDID/序列号，不使用含义不明的 `booted` 或“当前设备”。
3. 创建独立输出目录：

   ```text
   .tmp/visual-handoff/<YYYYMMDD-HHMMSS>-<short-task>/
   ```

4. 截图文件名使用稳定语义，例如 `before.png`、`after.png`、`empty-state.png`；录屏使用 `interaction.mp4`。

## 生成文件

优先使用当前 Flutter/Dart MCP 中“直接写入文件”的截图能力。默认模式下，如果工具只返回图片或 base64，改用操作系统级截图，避免图片内容进入模型上下文。

iOS 模拟器：

```bash
xcrun simctl list devices booted
SIMULATOR_UDID='<目标模拟器 UDID>'
OUTPUT_PNG='<输出目录>/after.png'
xcrun simctl io "$SIMULATOR_UDID" screenshot "$OUTPUT_PNG"
```

Android 设备或模拟器：

```bash
adb devices -l
DEVICE_SERIAL='<目标设备序列号>'
OUTPUT_PNG='<输出目录>/after.png'
adb -s "$DEVICE_SERIAL" exec-out screencap -p > "$OUTPUT_PNG"
```

录屏优先使用现有 Flutter 工具；需要平台命令时先确认设备唯一，再开始录制，完成后停止录制并保存到同一目录。不要捕获或转述系统通知、账号信息和敏感用户内容。

如果当前环境无法把截图直接写成文件，或对应平台工具未安装，停止并报告工具限制。不要用 base64 或未落盘的图片数据作为替代方案。

## 用户展示与 Agent 分析

用户要求直接在界面查看时，在最终回复中使用绝对路径：

```markdown
![after](</absolute/path/to/visual-handoff/after.png>)
```

这不会主动把图片内容加载到模型上下文。

用户要求 Agent 分析时：

1. 先完成文件生成和非视觉检查。
2. 先读取与问题最直接相关的图片或裁剪区域；单张图能回答时不必读取更多。
3. 如果问题涉及动画、转场、滚动或时序，先用 `ffprobe` 确认时长，再按需要抽取多个关键帧或分段分析录屏。不要无目的地扫描整段视频，但也不要为了限制图片数量而漏掉判断动画所需的关键时序。
4. 需要前后对比时，可以读取必要的 before/after 图片。只有当合成对比图更清楚时才优先合成，不强制合并。
5. 视觉结论明确标注为“基于图片的视觉判断”，不要把它当成编译、测试或运行时验证。

## 非视觉验证

生成后只做文件级检查：

- 文件存在且大小非零。
- `file <artifact>` 识别为预期图片或视频格式。
- 必要时用 `sips -g pixelWidth -g pixelHeight <PNG>` 或 `ffprobe <VIDEO>` 检查维度/时长。
- 检查 App 编译、运行时错误、关键路由或操作结果，不判断颜色、间距、动画观感是否正确。

## 交给用户

回复中提供：

- 每个截图或录屏的绝对文件路径。
- 目标设备、页面和已执行的操作步骤。
- 3–5 条明确的视觉检查项，例如动画是否连贯、元素是否重叠、间距是否符合预期。
- Agent 已完成的非视觉验证结果。

默认只返回文件路径。用户明确要求展示时再内嵌本地图片；用户明确要求分析时才读取关键图片。
