# 🎤 DoubleTapTalk

<div align="center">

**macOS 语音转文字 + AI 润色** · **macOS speech-to-text with AI polish**

在任意应用中双击 Control，开口说话，自动得到整洁的文字 —— 持续聆听、由 LLM 润色、直接注入当前输入框。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Stars](https://img.shields.io/github/stars/tychenjiajun/DoubleTapTalk?style=social)](https://github.com/tychenjiajun/DoubleTapTalk/stargazers)

[English](README.md) · [Issues](https://github.com/tychenjiajun/DoubleTapTalk/issues)

</div>

---

## 概述

DoubleTapTalk 把「双击 Control」变成一个随时可用的听写会话。它用 Apple Speech 在**设备端**聆听（音频不会离开你的 Mac），当你停顿片刻，每个段落会被自动插入当前应用 —— 可选地先经过 LLM 润色，让最终落地的文字干净、标点正确，且保持你的原始语言。

这是一个**连续听写**工具：只要你在说话，麦克风就保持开启；段落按静默自动切分；每次插入都会在悬浮胶囊上给出回执，让你随时知道自己在会话中的位置。

## 功能

**🎙️ 核心听写**
- 双击 Control 在任意位置开始 / 结束，无需切换应用。
- 由 Apple Speech 设备端流式识别 —— 说话时实时显示文字，不需要 API 密钥。
- 连续会话：段落按静默自动切分并插入；按退格键（或单击 Control）结束会话并丢弃当前未完成段落。
- 识别语言自动跟随键盘输入法，或固定选择（自动 / EN / 中文 / ES / FR / DE / JA / KO）。
- 悬浮胶囊显示实时波形、转写文本与每段回执 —— 每个流水线阶段都有独立的视觉状态；静默时自动收成细长胶囊，不再遮挡页面。

**✨ AI 润色（可选）**
- 每个段落插入前都可交给 LLM，并把前序段落作为上下文，保证术语与风格一致。
- 默认保守：只修正识别错误与标点，绝不改写、增删或翻译 —— 保留你的语言。
- 服务商：OpenAI、Anthropic (Claude)、Google (Gemini)，或通过自定义 Base URL 接入任意 OpenAI 兼容端点。
- 按应用定制的润色配置：终端、代码注释、聊天、正式邮件、搜索词、代码编辑器、交易终端、通用。

**☁️ 云端转写（可选）**
- 段落结束后可把录音发送到 OpenAI 兼容的 ASR 端点（默认 `qwen3-asr-flash`，如阿里云 DashScope）获取更准确的结果。
- 任何失败都会回退到 Apple 的结果；WAV 录音仅用于上传并自动保留最新的 20 个，可在设置中管理（占用 / 打开文件夹 / 删除）。

**🌐 界面**
- 全界面双语（简体中文 + English），悬浮胶囊、菜单栏与设置窗口都跟随系统语言。
- 菜单栏图标实时反映会话状态并显示已用时长；听写期间有一个置灰的状态行持续更新。

## 系统要求

- macOS 13.0 或更高版本
- 麦克风
- AI 润色需要 OpenAI / Anthropic / Google（或任意 OpenAI 兼容端点）的 API 密钥

## 安装

### 1. 获取应用

从 [GitHub Releases](https://github.com/tychenjiajun/DoubleTapTalk/releases) 下载最新 DMG，挂载后把 `DoubleTapTalk.app` 拖入「应用程序」文件夹。

> 开发者本地构建请直接跳到 [开发](#开发) —— `./install.sh` 一键完成构建、签名、安装并启动。

### 2. 授予权限（一次性）

首次启动时 macOS 会请求麦克风权限。DoubleTapTalk 还需要**辅助功能**权限来读取当前应用上下文（输入框现有文本、终端输出）以改进润色 —— 稍后授予也不会影响核心听写。

两项授权都列在 **设置 › 权限** 中，包含状态与直达对应系统设置面板的按钮：

| 权限 | 用途 | 缺失时 |
|---|---|---|
| 麦克风 | 语音识别（必需） | 无法开始录音 —— 在 系统设置 › 隐私与安全性 › 麦克风 中开启，然后点击**刷新** |
| 辅助功能 | 读取应用上下文用于润色（推荐） | 润色仍可用，但失去上下文 |

> ℹ️ **已知的 macOS 怪癖：** 使用 hardened runtime 时，若麦克风权限被撤销，应用可能从「麦克风」面板中彻底消失，看起来无法授权。如果列表中没有本应用，请确认开关已开启，然后从「应用程序」文件夹（而不是构建目录）重新启动应用，再次查看该面板。

## 使用方法

1. **双击 Control** —— 胶囊出现，开始聆听。
2. 开口说话，文字实时出现。当你停顿，段落被定稿、润色（如已启用）、并插入当前应用 —— 胶囊显示回执（`第 3 段 · ✓ 已插入 · 24 字`）。
3. 继续说话；长会话会自动轮换段落。
4. **单击 Control 或按退格键**结束会话，随后显示总结回执：插入了多少段、多少字、用时多久。

会话进行期间，菜单栏会显示实时头部（段落数 + 时钟）和一个**结束连续听写**项 —— 不想伸手够快捷键时的备用停法。

## 设置

- **权限** —— 麦克风与辅助功能状态，带系统设置直达链接。
- **语音识别** —— 识别语言（自动跟随或固定）。
- **连续听写** —— 段落静默阈值（静默持续多久才切段；越短越跟手，越长切分越少）。
- **AI 文本润色** —— 开关、服务商、API 密钥、模型、温度、超时、自定义系统提示词、按应用定制配置。
- **云端转写** —— OpenAI 兼容 ASR 端点、模型、录音管理。
- **重置** —— 所有设置恢复默认（会清空 API 密钥，需要确认）。

## 开发

Swift Package Manager，无外部依赖；Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。

```bash
swift build                                   # 调试构建
swift test                                    # 全部测试（212 个）
swift test --filter PolishProfileTests        # 运行单个测试文件
xcodegen generate                             # 新增文件后重新生成 Xcode 工程
swift build -c release                        # 发布构建
./install.sh                                  # 构建、以稳定本地证书签名、安装到 /Applications 并启动
./package.sh                                  # 本地 DMG（正式发布 DMG 由 CI 生成）
```

**签名很关键：** 如果应用被 ad-hoc 重新签名（Designated Requirement 变成每次构建都变化的 cdhash），macOS TCC 会静默丢弃麦克风 / 辅助功能授权。`./install.sh` 使用稳定的本地证书 `DoubleTapTalk Local Signing` 签名（由 `./scripts/setup-signing-identity.sh` 一次性创建），授权才能跨构建保留。请始终运行「应用程序」文件夹中的副本，而不是构建目录里的。

**实时提示词评测**（会请求 OpenRouter，需要密钥；无密钥时自动跳过）：

```bash
OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEvalTests
```

### 日志与调试

日志位于 `~/Library/Caches/DoubleTapTalk.log`（时间戳为 **UTC**；东八区请加 8 小时）。每次 LLM 往返都会在发送前记录端点/模型，并在返回后记录耗时。

```bash
./view-logs.sh watch          # tail -f 实时查看日志
./check-polish-logs.sh        # 从日志汇总润色流水线状态
./test-injection.sh browser   # 测试向浏览器注入文本（或：native）
```

## 故障排除

- **双击 Control 无反应** → 查看菜单栏麦克风图标。若显示为禁用符号，说明缺少麦克风权限：设置 › 权限 会给出确切状态与指向麦克风面板的链接。
- **识别不出任何文字** → 确认已启用 macOS 听写（系统设置 › 键盘 › 听写）；本应用刻意不强制设备端模式，因为关闭听写时强制设备端会导致识别彻底失败。
- **润色结果缺失** → 润色是可选的且会优雅降级：失败时插入原始转写。用 `./check-polish-logs.sh` 查看 `LLM request failed ← … after Nms` 行。
- **刚才那次请求打到了哪个服务商/模型？** → 每次请求都会在发送前记录 `LLM request → <endpoint> (transport, model, timeout)`，耗时总能对得上。

## 常见问题

**我的音频会离开 Mac 吗？** 只有启用云端转写时，*录音文件*才会发送到你配置的 ASR 端点。实时识别以及默认链路完全在设备端。AI 润色只把转写文本与上下文发送给你选择的服务商。

**能在哪些应用里使用？** 任何接受键盘输入的应用 —— 浏览器、终端、编辑器、聊天软件。按应用定制的润色配置会针对目标调整 LLM 提示词（例如终端命令 vs 聊天消息）。

**为什么有时我明明说了，它却没记下来？** 没有识别到词的段落会被静默跳过；插入失败的段落会在胶囊中明确提示（`⚠︎ N 段未插入`），方便你重说一遍。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。有问题？请提交 [issue](https://github.com/tychenjiajun/DoubleTapTalk/issues)。