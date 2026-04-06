# VoiceKey

<div align="center">

**macOS Speech-to-Text Utility | macOS 语音转文字助手**

Push-to-talk app for quick transcription and text input in any application

[中文版本](README_zh-CN.md)

</div>

---

## Overview

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
.build/debug/VoiceKey
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

### 📄 Documentation

- [English Version](README.md) (this file)
- [中文版本](README_zh-CN.md)

---

<div align="center">

Made with ❤️ by Jiajun Chen | Open Source under MIT License

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)

</div>
