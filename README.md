# 🎤 DoubleTapTalk

<div align="center">

**macOS Speech-to-Text Utility | macOS 语音转文字助手**

Double-tap hotkey activation for lightning-fast transcription and smart AI-polished text input in any application

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-brightgreen.svg)]()

📖 [English](#overview) | [中文文档](README_zh-CN.md)

---

## 🎯 Overview

DoubleTapTalk transforms how you interact with your Mac. Instead of typing, **speak naturally** and watch your words appear instantly—optionally polished by AI for perfect grammar, context-aware formatting, and professional tone.

### 💡 Why Choose DoubleTapTalk?

| Feature | Benefit |
|---------|--------|
| ⚡ **3x Faster Than Typing** | Average speaking speed: 150 wpm vs typing: 40-50 wpm |
| 🧠 **AI-Powered Polish** | Smart context detection auto-formats text for terminals, emails, code comments, chats |
| 🔒 **Privacy First** | Optional local whisper.cpp backend keeps data on-device |
| 🌍 **100+ Languages** | Auto-detect or manually select from Chinese, English, Spanish, French, Japanese & more |
| 🎨 **Zero Learning Curve** | Simple double-tap gesture works everywhere |

<div align="center">

**How It Works**: Double-tap Control → Speak → Text appears (with optional AI polish)!

</div>



### ✨ Key Features

#### 🎙️ Core Speech Recognition
- **Double-Tap Activation**: Simple Control+Control gesture to start recording
- **Smart Stop Options**:
  - 👆 Single-click → Insert raw transcription (instant)
  - 👆👆 Double-click → Insert AI-polished text (smart)
- **Multi-Language Support**: Auto-detect from 100+ languages or manually select
- **Secure API Storage**: Keys encrypted in macOS Keychain—never exposed
- **Menu Bar Design**: Runs quietly without Dock icon clutter

#### 🔄 Flexible Backend Options
Choose your preferred speech recognition service:

| Backend | Type | Best For | Accuracy | Speed |
|---------|------|----------|----------|--------|
| **OpenAI Whisper** | Cloud ⛅ | Highest accuracy | ⭐⭐⭐⭐⭐ | Fast |
| **Groq** | Cloud ⛅ | Ultra-fast inference | ⭐⭐⭐⭐ | ⚡ Ultra-fast |
| **DashScope Flash** | Cloud ⛅ | Chinese language | ⭐⭐⭐⭐⭐ | Fast |
| **Local whisper.cpp** | Offline 💻 | Privacy-sensitive work | ⭐⭐⭐⭐ | Medium |

💡 **No lock-in**: Switch backends anytime in settings!

#### ✨ AI-Powered Smart Polish
Optional LLM-powered text enhancement that understands context:

**Supported Providers**: OpenAI GPT-4o, Claude 3, Google Gemini, ModelScope, Ollama (local), LM Studio

**Context-Aware Profiles**:
- 💻 **Terminal** → Converts imperatives to commands, keeps questions as natural language
- 💬 **Chat Apps** (Slack, Discord, WeChat) → Casual tone, preserves emojis
- 📧 **Email** (Mail, Outlook, Gmail) → Professional tone, proper punctuation
- 💾 **Code Comments** → Concise technical language, no markers
- 🔍 **Search Bars** → Keyword extraction for clean queries
- 📈 **Trading Terminals** → Order format conversion with bilingual support

**Examples**:
```
Input:  "check if the tests are passing"
Output: check if the tests are passing ✓ (kept as question)

Input:  "run the test suite"
Output: npm test ✓ (converted to command)

Input:  "I'm looking for recent build failures in logs"
Output: I'm looking for recent build failures in logs ✓ (preserved intent)
```

#### 🎯 Smart Context Detection (App-Specific Polish)

Automatically adapts polishing style based on your target application:

| Application | Detected Profile | Behavior |
|-------------|-----------------|----------|
| iTerm2, Warp, Terminal | **Terminal** | Converts commands, preserves questions |
| VS Code, Xcode (text areas) | **Code Comment** | Concise technical comments |
| VS Code, Sublime (editors) | **Code Editor** | Commit-message style, preserve code |
| Slack, Discord, WeChat | **Chat/Messaging** | Conversational tone |
| Mail, Outlook, Gmail | **Email Formal** | Professional punctuation |
| Chrome URL bar, Spotlight | **Search Query** | Keywords only |
| 富途牛牛，同花顺，Schwab | **Trading Terminal** | Order format, stock codes |
| Everything else | **General** | Clean, readable text |

**Requirements for full detection**:
- ✅ Accessibility permission (to read existing text)
- ✅ Window title access (for Gmail/browser detection)
- ✅ Terminal screen buffer (for command context)

#### 👨‍💻 Developer-Friendly Design

Built for extensibility and debugging:

- **Comprehensive Logging**: Real-time debug at `~/Library/Caches/DoubleTapTalk.log`
- **Helper Scripts**:
  ```bash
  ./view-logs.sh watch        # Watch logs in real-time
  ./check-polish-logs.sh      # Verify polish feature status
  ./test-injection.sh browser # Test text injection
  ```
- **Swift Package Manager**: Clean, modern build system
- **Modular Architecture**: Easily extend backends and services

### 📋 System Requirements

**Hardware & OS**:
- macOS 13.0+ (Ventura, Sonoma, Sequoia)
- Microphone (built-in or external)

**Permissions Needed**:
- 🔊 **Microphone Access**: For audio recording
- 🎛️ **Accessibility Permission**: For hotkey detection and text injection

**API Keys **(Choose One)
- 🌐 OpenAI API key (~$0.006/minute of audio)
- ⚡ Groq API key (free tier available)
- 💼 DashScope/ModelScope API key (excellent for Chinese)
- 💻 Local whisper.cpp server (completely free, privacy-focused)

### 🚀 Get Started in 3 Minutes

#### Step 1: Installation

**Option A: Download DMG **(Easiest)
```bash
# Download the latest release from GitHub Releases
doubletap-talk-1.0.0.dmg
# Drag DoubleTapTalk.app to /Applications
```

**Option B: Build from Source **(For Developers)
```bash
git clone https://github.com/tychenjiajun/voice-key.git
cd voice-key
swift build -c release
open DoubleTapTalk.app
```

#### Step 2: Grant Permissions

1. **System Settings** → Privacy & Security → Accessibility
2. Click `+` button and add **DoubleTapTalk.app**
3. Toggle **Microphone** permission when prompted
4. Restart DoubleTapTalk after adding permissions

#### Step 3: Configure Backend

Click ⚙️ **Settings** in menu bar (or press ⌘,):

1. **Select ASR Backend**: Choose OpenAI, Groq, DashScope, or Local
2. **Enter API Key**: Saved securely to macOS Keychain 🔒
3. **Choose Language**: Auto-detect recommended for mixed-language speech
4. **(Optional) Enable AI Polish**: Connect LLM provider for smart text enhancement

**💡 Pro Tip**: Start with **OpenAI Whisper + GPT-4o** for best overall quality!

#### Step 4: Start Using!

1. Watch for microphone icon 🎤 in menu bar
2. **Double-click Control** → Speak naturally → Release
3. Text appears instantly in your app! ✨

### ⚙️ Advanced Configuration

#### Speech Recognition Settings
- **Backend Type**: OpenAI / Groq / DashScope / Local whisper.cpp
- **Language**: auto / zh-CN / en / +100 more languages
- **Model Selection**: whisper-1 / whisper-large-v3 / qwen3-asr-flash

#### AI Polish Settings (Optional)
- **Enable/Disable Toggle**: Turn polish on or off instantly
- **Provider Choice**: OpenAI / Anthropic / Google / ModelScope / Custom
- **Model Selection**: gpt-4o-mini / claude-3-haiku / gemini-pro / local models
- **Temperature**: 0.0-1.0 (creativity level)
- **Custom Base URL**: Connect to self-hosted Ollama, LM Studio, vLLM
- **Timeout**: 1-30 seconds (prevent hanging, default: 5s)
- **System Prompt**: Customize polishing behavior per application

#### ⌨️ Hotkey Behavior
- **Start Recording**: Double-click Control (configurable)
- **Stop Without Polish**: Single-click Control or menu bar button
- **Stop With Polish**: Double-click Control while recording

**Customization**: Modify trigger keys in source code and rebuild if needed.

### 🔧 For Developers

#### Build & Run
```bash
# Debug build (fast iteration)
swift build

# Release build (optimized performance)
swift build -c release

# Run directly from terminal
.build/debug/DoubleTapTalk
```

#### Debugging Tools
```bash
# Real-time log monitoring
./view-logs.sh watch

# Check polish feature status
./check-polish-logs.sh

# Test text injection
./test-injection.sh browser  # or 'native'
```

#### Log File Details
All operations logged to: `~/Library/Caches/DoubleTapTalk.log`

**Log Levels**:
- **DEBUG**: Full API calls, JSON responses, token usage details
- **INFO**: State changes, successful operations, user actions
- **WARN**: Non-critical issues, deprecation notices
- **ERROR**: Failures with automatic fallback information

### 🛠️ Troubleshooting

#### Hotkeys Not Working? 🔧
```bash
1. Quit DoubleTapTalk completely
2. System Settings → Privacy & Security → Accessibility
3. Find "DoubleTapTalk", remove it, then re-add
4. Restart DoubleTapTalk.app
```

#### Transcription Returns Empty? ❓
Check logs for error details:
```bash
tail -30 ~/Library/Caches/DoubleTapTalk.log | grep -i error
```

**Common Causes**:
- 🚫 Invalid or expired API key
- 🌐 Network connectivity issues
- ⚠️ Model not supported by chosen backend
- 🔇 Microphone permission denied

#### AI Polish Fails Gracefully 💡
If polishing times out or errors occur:
- Original transcription is used automatically ✅
- No data loss or app crashes
- Check timeout settings (increase if needed)

**Still having issues?** Open a GitHub issue with relevant log excerpts!

### 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

### ❓ Frequently Asked Questions

**Q: Is this free to use?**
A: The app itself is 100% free and open-source (MIT License). You'll need an API key for cloud backends (OpenAI, Groq, etc.), but local whisper.cpp is completely free!

**Q: How much does it cost with OpenAI Whisper?**
A: Roughly $0.006 per minute of audio. If you dictate for 30 minutes daily, that's about $5-6/month.

**Q: Can I use this offline?**
A: Yes! Set up a local whisper.cpp server and you're completely independent from internet connectivity.

**Q: Does this record my conversations in the background?**
A: Absolutely not! Recording ONLY happens when you actively double-tap Control. No background listening ever occurs.

**Q: Which languages work best?**
A: Whisper supports 100+ languages. English and Chinese have the highest accuracy. Auto-detect handles mixed-language speech well.

**Q: Can I customize the hotkey?**
A: Currently it's hardcoded as double-tap Control. Feel free to modify the source code and rebuild—check `HotkeyService.swift`!

**Q: Does AI polish change my meaning?**
A: No! As of v1.0.0, prompts are designed to preserve your exact intent. It only fixes grammar, removes fillers, and adapts tone per context.

**Q: Can I contribute?**
A: Absolutely! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. New backend support, bug fixes, and documentation improvements are all welcome!

---

### 💼 Real-World Use Cases

**For Developers**:
```bash
# Write commit messages without typing
"fix the memory leak in user authentication module"
→ "Fix memory leak in user authentication module"

# Terminal commands hands-free
"show me the last 20 git commits"
→ "git log --oneline -20"
```

**For Writers & Content Creators**:
- Draft emails 3x faster with natural speech
- Polish blog posts with AI-enhanced grammar
- Switch between casual (chat) and formal (email) tone instantly

**For Researchers & Academics**:
- Dictate notes during lectures/meetings
- Generate technical comments in research code
- Convert ideas to search queries for literature review

**For Traders **(Chinese Platforms Supported)
- Execute trade orders via voice (富途牛牛，同花顺)
- Bilingual command recognition (English + Chinese)
- Automatic order format conversion

### 🤝 Contributing

Contributions are **highly welcome**! 💙 Whether you're fixing bugs, adding new backends, improving docs, or suggesting features—every contribution matters.

👉 See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines on how to get started.

### 📄 Documentation

- [English Version](README.md) (this file)
- [中文版本](README_zh-CN.md)
- [Prompt Engineering Fixes](docs/PROMPT_FIXES.md) - Technical details on LLM polish improvements
- [Contributing Guide](CONTRIBUTING.md) - How to contribute to the project

---

<div align="center">

**Made with ❤️ by [Jiajun Chen](https://github.com/tychenjiajun)** | Open Source under [MIT License](LICENSE)

---

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Stars](https://img.shields.io/github/stars/tychenjiajun/voice-key?style=social)](https://github.com/tychenjiajun/voice-key/stargazers)

📧 **Questions?** Open an [issue](https://github.com/tychenjiajun/voice-key/issues) or reach out!

</div>
