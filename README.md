# VoiceKey

<div align="center">

**macOS 语音转文字助手 | macOS Speech-to-Text Utility**

简洁的菜单栏应用，按住说话，自动输入到任何应用程序

</div>

---

## 📖 Table of Contents / 目录

- [English](#english-version)
- [中文版](#chinese-version)

---

## English Version

### Overview

VoiceKey is a lightweight macOS menu-bar application that enables hands-free speech-to-text input into any active application. Simply press and hold a hotkey, speak naturally, and your words will be automatically transcribed and typed where needed.

### ✨ Features

#### Core Features
- **🎤 Push-to-Talk Recording**: Double-click Control key to start recording
- **⏱️ Smart Hotkey Controls**: 
  - Double-click Control → Start recording
  - Single-click Control → Stop without polish
  - Double-click Control → Stop with AI polish
- **🌐 Multi-Language Support**: Auto-detect language or manually select from 100+ languages
- **🔒 Secure Storage**: API keys encrypted in macOS Keychain
- **🚫 No Dock Icon**: Runs quietly in menu bar (LSUIElement)

#### Multiple ASR Backends
Choose your preferred speech recognition service:
- **OpenAI Whisper** (cloud) - High accuracy, requires API key
- **Groq** (cloud) - Fast inference on edge hardware
- **Qwen3 ASR Flash** (cloud) - Alibaba's advanced model, excellent for Chinese
- **Local whisper.cpp** (offline) - Free, private, self-hosted server required

#### AI Text Polishing (Optional)
Improve transcribed text with LLM-powered refinement:
- **Multi-provider support**: OpenAI, Anthropic, Google, ModelScope
- **Custom Base URL**: Connect to Ollama, LM Studio, vLLM, etc.
- **Configurable timeout**: 1-30 seconds (default 5s)
- **Graceful fallback**: Falls back to original text if timeout/error occurs
- **System prompt customization**: Tailor the polishing behavior

#### Developer Friendly
- **Comprehensive logging**: Debug at `~/Library/Caches/VoiceKey.log`
- **Helper scripts**: `view-logs.sh`, `check-polish-logs.sh`, `test-injection.sh`
- **Swift Package Manager**: Clean build system
- **Modular architecture**: Easy to extend backends/services

### 📋 Requirements

- **macOS 13.0+** (Ventura or later)
- **Permissions**:
  - Microphone access (for audio recording)
  - Accessibility permissions (for hotkey & text injection)
- **API Keys** (choose one):
  - OpenAI API key, OR
  - Groq API key, OR
  - DashScope/ModelScope API key, OR
  - Local whisper.cpp server running

### 🚀 Quick Start

#### Installation

**Option 1: Download DMG**
```bash
# Download the latest release DMG
open VoiceKey-1.0.0.dmg
# Drag VoiceKey.app to Applications folder
```

**Option 2: Build from Source**
```bash
git clone https://github.com/tychenjiajun/voice-key.git
cd voice-key
swift build -c release
open VoiceKey.app
```

#### First Time Setup

1. **Grant Permissions**:
   - Go to System Settings → Privacy & Security → Accessibility
   - Add "VoiceKey" to the list
   - Also grant Microphone permission when prompted

2. **Configure Backend** (⌘, to open settings):
   - Select your preferred ASR backend
   - Enter API key (saved securely to Keychain)
   - Choose language (auto-detect recommended)

3. **Start Using**:
   - Watch for menu bar icon (microphone)
   - Double-click Control → Speak → Release
   - Text appears in frontmost application!

### ⚙️ Configuration

#### ASR Settings
- **Backend Type**: OpenAI / Groq / Qwen3 / Local
- **API Key**: Stored in Keychain (com.voicekey.app)
- **Language**: auto / zh-CN / en / +100 more
- **Model**: whisper-1 / whisper-large-v3 / qwen3-asr-flash

#### AI Polishing Settings (Optional)
- **Enable Polishing**: Toggle on/off
- **Provider**: OpenAI / Anthropic / Google / Custom
- **Model**: gpt-4o-mini / claude-3-haiku / gemini-pro / etc.
- **Temperature**: 0.0 - 1.0 (creativity)
- **Custom Base URL**: For Ollama/LM Studio/vLLM (e.g., http://localhost:11434/v1)
- **Timeout**: 1-30 seconds (prevent hanging)
- **System Prompt**: Customize polishing behavior

#### Hotkey Configuration
- **Record Trigger**: Double-click Control
- **Stop Behavior**: Single = no polish, Double = with polish
- **Menu Bar Button**: Always stop without polish

### 🔧 Development

#### Building
```bash
# Debug build
swift build

# Release build (recommended)
swift build -c release

# Run directly
.open/build/debug/VoiceKey
```

#### Running Tests
```bash
# View logs in real-time
./view-logs.sh watch

# Check polishing status
./check-polish-logs.sh

# Test text injection
./test-injection.sh browser  # or 'native'
```

#### Log File Location
All operations logged to: `~/Library/Caches/VoiceKey.log`

Log levels:
- **DEBUG**: Detailed API calls, JSON responses, token usage
- **INFO**: State changes, successful operations
- **WARN**: Non-critical issues
- **ERROR**: Failures with fallback information

### 🛠️ Troubleshooting

#### Hotkeys Not Working
```
1. Quit VoiceKey
2. System Settings → Privacy & Security → Accessibility
3. Find "VoiceKey", remove and re-add
4. Restart VoiceKey
```

#### Transcription Returns Empty
Check log file for error details:
```bash
tail -30 ~/Library/Caches/VoiceKey.log | grep -i error
```

Common causes:
- Invalid API key
- Network connectivity
- Model not supported by chosen backend

#### Polish Feature Fails Gracefully
If AI polishing times out or fails, original transcription is used automatically.

Increase timeout in Settings if consistent failures occur.

### 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

### 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

---

## 中文版

### 概述

VoiceKey 是一款轻量级 macOS 菜单栏应用，让您在任何活跃应用中通过语音输入文字。只需按住快捷键，自然说话，您的话语就会被自动转录并输入到需要的位置。

### ✨ 功能特点

#### 核心功能
- **🎤 按键录音**: 双击 Control 键开始录音
- **⏱️ 智能热键控制**:
  - 双击 Control → 开始录音
  - 单击 Control → 停止，不进行优化
  - 双击 Control → 停止，进行 AI 优化
- **🌐 多语言支持**: 自动检测或从 100+ 种语言中手动选择
- **🔒 安全存储**: API 密钥加密存储在 macOS Keychain
- **🚫 无Dock图标**: 安静地运行在菜单栏中

#### 多种语音识别后端
选择您偏好的语音识别服务：
- **OpenAI Whisper**（云端）- 高精度，需要 API 密钥
- **Groq**（云端）- 边缘硬件上的快速推理
- **Qwen3 ASR Flash**（云端）- 阿里云高级模型，中文效果极佳
- **本地 whisper.cpp**（离线）- 免费、隐私友好，需自托管服务器

#### AI 文本优化（可选）
使用大模型改进转录文本：
- **多提供商支持**: OpenAI、Anthropic、Google、ModelScope
- **自定义 Base URL**: 连接 Ollama、LM Studio、vLLM 等
- **可配置超时**: 1-30 秒（默认 5 秒）
- **优雅降级**: 超时或错误时自动回退到原文
- **系统提示词定制**: 调整优化行为

#### 开发者友好
- **全面日志**: 调试位置 `~/Library/Caches/VoiceKey.log`
- **辅助脚本**: `view-logs.sh`、`check-polish-logs.sh`、`test-injection.sh`
- **Swift Package Manager**: 干净的构建系统
- **模块化架构**: 易于扩展后端/服务

### 📋 系统要求

- **macOS 13.0+** (Ventura 或更高版本)
- **权限**:
  - 麦克风访问（用于录音）
  - 辅助功能权限（用于热键和文本注入）
- **API 密钥**（选择其一）:
  - OpenAI API 密钥，或
  - Groq API 密钥，或
  - 阿里云 DashScope/ModelScope API 密钥，或
  - 正在运行的本地 whisper.cpp 服务器

### 🚀 快速开始

#### 安装

**方式一：下载 DMG**
```bash
# 下载最新版本的 DMG
open VoiceKey-1.0.0.dmg
# 将 VoiceKey.app 拖入应用程序文件夹
```

**方式二：从源代码构建**
```bash
git clone https://github.com/tychenjiajun/voice-key.git
cd voice-key
swift build -c release
open VoiceKey.app
```

#### 首次设置

1. **授予权限**:
   - 前往 系统设置 → 隐私与安全性 → 辅助功能
   - 将 "VoiceKey" 添加到列表
   - 提示时也授予麦克风权限

2. **配置后端**（⌘, 打开设置）:
   - 选择首选的 ASR 后端
   - 输入 API 密钥（安全保存到 Keychain）
   - 选择语言（推荐自动检测）

3. **开始使用**:
   - 注意菜单栏中的麦克风图标
   - 双击 Control → 说话 → 释放
   - 文字出现在当前应用光标位置！

### ⚙️ 配置说明

#### ASR 设置
- **后端类型**: OpenAI / Groq / Qwen3 / 本地
- **API 密钥**: 存储在 Keychain（com.voicekey.app）
- **语言**: 自动 / zh-CN / en / 还有 100+ 种
- **模型**: whisper-1 / whisper-large-v3 / qwen3-asr-flash

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

# 发布构建（推荐）
swift build -c release

# 直接运行
.open/build/debug/VoiceKey
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
所有操作记录到：`~/Library/Caches/VoiceKey.log`

日志级别：
- **DEBUG**: 详细 API 调用、JSON 响应、token 使用量
- **INFO**: 状态变化、成功操作
- **WARN**: 非关键问题
- **ERROR**: 失败信息及降级详情

### 🛠️ 故障排除

#### 热键不工作
```
1. 退出 VoiceKey
2. 系统设置 → 隐私与安全性 → 辅助功能
3. 找到 "VoiceKey"，删除后重新添加
4. 重启 VoiceKey
```

#### 转录返回空结果
检查日志文件的错误详情：
```bash
tail -30 ~/Library/Caches/VoiceKey.log | grep -i error
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

### 🤝 贡献

欢迎贡献！请随时提交问题或拉取请求。

---

<div align="center">

Made with ❤️ by chenjiajun | 开源许可：MIT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)

</div>
