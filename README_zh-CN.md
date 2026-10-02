# 🎤 DoubleTapTalk 语音助手

<div align="center">

**macOS 语音转文字助手 | macOS Speech-to-Text Utility**

双击快捷键激活，闪电般快速转录并智能 AI 优化文本输入到任何应用

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![版本](https://img.shields.io/badge/version-1.0.0-brightgreen.svg)]()

📖 [英文文档](README.md) | [中文](#概述)

---

## 🎯 概述

DoubleTapTalk 彻底改变了您与 Mac 的交互方式。告别繁琐打字，**自然说话**即可将文字呈现眼前——还可智能 AI 优化，实现完美语法、上下文感知的格式和专业语气。

### 💡 为什么选择 DoubleTapTalk？

| 功能 | 优势 |
|------|------|
| ⚡ **比打字快 3 倍** | 平均语速：150 词/分钟 vs 打字：40-50 词/分钟 |
| 🧠 **AI 智能优化** | 智能场景识别，自动格式化终端命令、邮件、代码注释、聊天消息 |
| 🔒 **隐私优先** | Apple 设备端语音识别——数据不出设备、无需 API 密钥 |
| 🌍 **100+ 语言支持** | 自动检测或手动选择中文、英语、西班牙语、法语、日语等 |
| 🎨 **零学习成本** | 简单的双击手势，随处可用 |

<div align="center">

**工作原理**：双击 Control → 说话 → 文字出现（可选 AI 优化）！

</div>

### ✨ 核心功能

#### 🎙️ 智能语音识别
- **双击激活**：简单的 Control+Control 手势开始录音
- **单击停止**：单击 Control 即停止——AI 优化在启用时**自动**应用于每一段
- **多语言支持**：自动检测 100+ 种语言或手动选择
- **零配置**: 无需 API 密钥与账号，即开即用
- **菜单栏设计**：安静运行，不占用 Dock 图标空间
- **⚡ 流式实时转录**（Apple 后端）：边说边出字
- **🎛️ 录音悬浮胶囊**：无边框胶囊窗口，实时波形 + 实时转录文本，弹簧动画
- **🔁 连续口述（中继模式，需在设置中开启）**：开启后麦克风全程开启，停顿满 3 秒自动分段——上一段识别并插入，新一段随即开始，允许在长篇口述中思考停顿；可调阈值（1–10 秒）
- **🌩️ 云端转写（可选）**：开启后录音存为 WAV 文件并通过 OpenAI 兼容 ASR 端点（如阿里云百炼 qwen3-asr-flash）获取更准确的最终文本；任何失败自动回退到 Apple 本地结果。未开启时不会向磁盘写入任何音频文件。

#### 🛡️ 设备端语音识别（Apple）

语音识别完全在您的 Mac 上运行，使用苹果内置语音框架：

| 后端 | 类型 | 最佳用途 | 准确度 | 速度 |
|------|------|----------|--------|------|
| **Apple 设备端** | 离线 ⚡ | 流式实时转录、零配置、隐私 | ⭐⭐⭐⭐ | ⚡ 实时 |

- ⚡ **流式**: 边说边出字
- 🔒 **私密**: 完整的设备端识别；WAV 录音仅在开启“云端转写”时写入磁盘，保存在本机（`~/Library/Application Support/DoubleTapTalk/Recordings/`，保留最近 20 个），且仅用于转写上传；可在设置中查看占用空间、打开文件夹或一键删除
- 🌍 **多语言**: 自动检测或选择 中/英/日/韩/西/法/德

> 实时文字显示固定使用 Apple 设备端识别。云端转写仅用于替换最终插入的文本，失败时自动回退；中继模式的每段同理。

#### ✨ AI 智能文本优化
可选的大语言模型文本增强，理解上下文：

**支持的提供商**：OpenAI GPT-4o、Claude 3、Google Gemini、ModelScope、Ollama（本地）、LM Studio

**场景感知配置文件**：
- 💻 **终端** → 转换命令为可执行格式，保留问题为自然语言
- 💬 **聊天应用**（Slack、Discord、微信）→ 随意语气，保留表情符号
- 📧 **邮件**（Mail、Outlook、Gmail）→ 专业语气，正确标点
- 💾 **代码注释** → 简洁技术语言，无需标记
- 🔍 **搜索栏** → 关键词提取用于干净查询
- 📈 **交易终端** → 订单格式转换，双语支持

**示例**：
```
输入："check if the tests are passing"
输出：check if the tests are passing ✓ （保留为问题）

输入："run the test suite"
输出：npm test ✓ （转换为命令）

输入："I'm looking for recent build failures in logs"
输出：I'm looking for recent build failures in logs ✓ （保留意图）
```

**✨ 变更预览**：当 AI 优化修改了文本，悬浮胶囊会先展示 `✨ 优化结果` 一秒再插入——你总能看清改动。

**🧠 段落上下文**：连续口述时，优化提示会把**前面几段（最近 8 段，每段截取 120 字符）的 ASR/优化结果**一并发给模型，并要求“术语和风格保持一致、不要重复已输出内容”。

**🚫 防翻译保护**：提示词经专门设计，绝不翻译或转写——英文保持英文，中文保持中文。精简为约 110 token，更快更省。

#### 🌩️ 云端转写（OpenAI 兼容 ASR）

可选的后处理：把录音（WAV）通过 OpenAI 兼容接口发送给云端 ASR 端点（例如阿里云百炼 compatible-mode 下的 `qwen3-asr-flash`），用返回文本替换 Apple 结果。

- **实时文字不受影响**：说话过程中的实时文字始终来自 Apple 设备端识别
- **失败即回退**：未配置、超时、网络错误、HTTP 错误、音频超过 10MB 等任何失败都自动使用 Apple 本地结果
- **Base URL / API Key 可留空**：留空时复用 LLM 优化里配置的 Base URL 和 API Key

请求示例（`qwen3-asr-flash`，OpenAI 兼容）：
```
POST {base}/chat/completions
{ "model": "qwen3-asr-flash",
  "messages": [{ "role": "user",
    "content": [{ "type": "input_audio",
      "input_audio": { "data": "data:audio/wav;base64,..." }}]}],
  "stream": false, "asr_options": { "enable_itn": false } }
```

#### 🔁 连续口述（中继模式）

开启后，一次双击开始即可连续口述长文：

- 麦克风与识别引擎全程保持开启，不关闭、不重开
- 当 Apple 识别**超过阈值秒数（默认 3 秒）没有新字词**时：
  1. 当前分段立即收尾（保存录音文件）
  2. 同时开启新的分段继续识别（引擎不停，边界不丢字）
  3. 上一段异步上传云端转写（若启用），**有结果即插入**目标应用，完全不打扰当前实时字幕
- 每段 ASR 完成即自动做 AI 优化（若启用），优化提示会把**前面几段的 ASR/优化结果**作为上下文一起发给模型，保持术语与风格一致、不重复内容
- **Apple 没识别出任何字的段落直接跳过**（不保留、不上传空录音），有效避免把静音/空音频发给云端 ASR
- 停止只需单击 Control（不再有“单击不优化 / 双击优化”之分），最后一段同样自动优化
- 录音文件按段生成于 `Recordings/`（仅在开启云端转写时生成；自动保留最近 20 个，可在设置中查看占用并一键删除）

#### 👨‍💻 开发者友好设计

为可扩展性和调试而生：

- **全面日志**：实时调试位于 `~/Library/Caches/DoubleTapTalk.log`
- **辅助脚本**：
  ```bash
  ./view-logs.sh watch        # 实时监控日志
  ./check-polish-logs.sh      # 验证优化功能状态
  ./test-injection.sh browser # 测试文本注入
  ```
- **Swift Package Manager**：干净的现代化构建系统
- **模块化架构**：轻松扩展后端和服务

### 📋 系统要求

- **macOS 13.0+** (Ventura 或更高版本)
- **权限**:
  - 麦克风访问（用于录音）
  - 辅助功能权限（用于热键和文本注入）
  - 语音识别权限（仅 Apple 设备端后端，提示开启一次）
- **API 密钥**: 语音识别无需任何密钥；仅在启用 AI 优化时需 LLM 提供商密钥

### 🚀 快速开始

#### 安装

**方式一：下载 DMG**
```bash
# 下载最新版本的 DMG
open DoubleTapTalk-1.0.0.dmg
# 将 DoubleTapTalk.app 拖入应用程序文件夹
```

**方式二：从源代码构建**
```bash
git clone https://github.com/tychenjiajun/voice-key.git
cd voice-key
swift build -c release
open DoubleTapTalk.app
```

#### 首次设置

1. **授予权限**:
   - 前往 系统设置 → 隐私与安全性 → 辅助功能
   - 将 "DoubleTapTalk" 添加到列表
   - 提示时也授予麦克风权限

2. **无需配置**（⌘, 打开设置）:
   - 语音识别已预置为 Apple 设备端，开箱即用
   - 可选：选择语言（推荐自动检测）
   - 可选：启用 AI 优化并填写 LLM 提供商密钥

3. **开始使用**:
   - 注意菜单栏中的麦克风图标
   - 双击 Control → 说话 → 释放
   - 文字出现在当前应用光标位置！

### ⚙️ 配置说明

#### 语音识别设置
- **后端**: Apple 设备端（固定，无需配置）
- **语言**: 自动 / zh-CN / en / ja / ko / es / fr / de

#### AI 优化设置（可选）
- **启用优化**: 开关选项
- **提供商**: OpenAI / Anthropic / Google / 自定义
- **模型**: gpt-4o-mini / claude-3-haiku / gemini-pro 等
- **温度值**: 0.0 - 1.0（创造性）
- **自定义 Base URL**: 用于 Ollama/LM Studio/vLLM（例如 http://localhost:11434/v1）
- **超时时间**: 1-30 秒（防止卡住）
- **系统提示词**: 自定义优化行为

#### 热键配置
- **录音触发**: 双击 Control
- **停止行为**: 单击 = 不优化，双击 = 带优化
- **菜单按钮**: 总是停止且不带优化

### 🔧 开发指南

#### 构建项目
```bash
# 调试构建
swift build

# 运行测试套件（66 个测试）
swift test

# 发布构建（推荐）
swift build -c release

# 直接运行
.build/debug/DoubleTapTalk
```

#### 运行测试
```bash
# 实时查看日志
./view-logs.sh watch

# 检查优化状态
./check-polish-logs.sh

# 测试文本注入
./test-injection.sh browser  # 或 'native'
```

#### 日志文件位置
所有操作记录到：`~/Library/Caches/DoubleTapTalk.log`

日志级别：
- **DEBUG**: 详细 API 调用、JSON 响应、token 使用量
- **INFO**: 状态变化、成功操作
- **WARN**: 非关键问题
- **ERROR**: 失败信息及降级详情

### 🛠️ 故障排除

#### 热键不工作
```
1. 退出 DoubleTapTalk
2. 系统设置 → 隐私与安全性 → 辅助功能
3. 找到 "DoubleTapTalk"，删除后重新添加
4. 重启 DoubleTapTalk
```

#### 转录返回空结果
检查日志文件的错误详情：
```bash
tail -30 ~/Library/Caches/DoubleTapTalk.log | grep -i error
```

常见原因：
- API 密钥无效
- 网络连接问题
- 所选后端不支持该模型

#### 优化功能优雅降级
如果 AI 优化超时或失败，会自动使用原始转录文本。

如持续失败，可在设置中增加超时时间。

### 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

### ❓ 常见问题解答

**问：这个软件免费吗？**
答：100% 免费且开源（MIT）。语音识别使用苹果内置设备端引擎——无需 API 密钥、永不收费。

**问：语音识别要花多少钱？**
答：$0。识别完全在设备端（Apple Speech），唯一可选花费是使用付费 LLM 提供商时 AI 优化的费用。

**问：可以离线使用吗？**
答：可以！语音识别完全在设备端——无需联网、无需 API 密钥。

**问：这会在后台录音吗？**
答：绝对不会！只有当您主动双击 Control 键时才会录音。永远不会在后台监听。

**问：哪些语言效果最好？**
答：Apple Speech 支持您 Mac 已下载的语言（系统设置 → 键盘 → 听写中开启）。英语和中文准确度最高；自动模式跟随当前输入法（中文输入法→中文识别，英文键盘→英文识别）。

**问：可以自定义快捷键吗？**
答：目前硬编码为双击 Control。欢迎修改源代码并重新构建——查看 `HotkeyService.swift`！

**问：AI 优化会改变我的意思吗？**
答：不会！从 v1.0.0 开始，提示词设计为保留您的确切意图。仅修正语法、移除填充词、适应语气。

**问：我可以贡献代码吗？**
答：当然！查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解指南。新后端支持、bug 修复和文档改进都受欢迎！

---

### 💼 真实应用场景

**开发者**：
```bash
# 无需打字编写提交信息
"fix the memory leak in user authentication module"
→ "Fix memory leak in user authentication module"

# 免操作终端命令
"show me the last 20 git commits"
→ "git log --oneline -20"
```

**作家与内容创作者**：
- 通过自然语音快速撰写邮件，速度提升 3 倍
- 用 AI 增强语法润色博客文章
- 即时切换随意（聊天）和专业（邮件）语气

**研究人员与学者**：
- 讲座/会议中口述笔记
- 生成研究代码的技术注释
- 将想法转换为文献综述的搜索查询

**交易者**（支持中文平台）：
- 通过语音执行交易指令（富途牛牛、同花顺）
- 双语命令识别（英语 + 中文）
- 自动订单格式转换

### 🤝 贡献

**非常欢迎**贡献！💙 无论您是修复 bug、添加新后端、改进文档，还是提出新功能——每项贡献都至关重要。

👉 查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详细的起步指南。

### 📄 文档

- [英文版](README.md)
- [中文版](README_zh-CN.md) （本文档）
- [Prompt Engineering Fixes](docs/PROMPT_FIXES.md) - LLM 优化技术细节
- [贡献指南](CONTRIBUTING.md)

---

<div align="center">

**用心打造 by [Jiajun Chen](https://github.com/tychenjiajun)** | 开源许可：[MIT License](LICENSE)

---

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Stars](https://img.shields.io/github/stars/tychenjiajun/voice-key?style=social)](https://github.com/tychenjiajun/voice-key/stargazers)

📧 **有问题？** 提交 [issue](https://github.com/tychenjiajun/voice-key/issues) 或直接联系我们！

</div>
