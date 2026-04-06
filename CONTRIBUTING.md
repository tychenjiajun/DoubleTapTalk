# Contributing to DoubleTapTalk

Thank you for your interest in contributing to DoubleTapTalk! This document provides guidelines for contributing.

## 🚀 Quick Start

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/doubletap-talk.git
   cd doubletap-talk
   ```
3. **Create a branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **Make your changes** (see [Coding Guidelines](#coding-guidelines))
5. **Commit** with clear messages (see [Commit Messages](#commit-messages))
6. **Push** and create a Pull Request

## 📋 Contribution Areas

We welcome contributions in these areas:

- **New ASR Backends**: Add support for other speech-to-text services
- **Bug Fixes**: Report and fix issues
- **Documentation**: Improve README, comments, or add tutorials
- **Features**: Suggest or implement new capabilities
- **Translations**: Add support for more languages
- **Tests**: Add unit/integration tests

## 💻 Coding Guidelines

### Swift Style

```swift
// ✅ Good: Clear, descriptive names
var transcriptionText: String {
    return asrService.lastResult?.text ?? ""
}

// ❌ Avoid: Abbreviations without context
var txt: String { ... }
```

### Logging

Always log significant operations:

```swift
logger.debug("Processing audio file: \(filename)")
logger.info("Transcription complete: \(count) chars")
logger.error("API request failed: \(error)")
```

### Error Handling

Use proper error types:

```swift
enum ASRError: LocalizedError {
    case invalidResponse
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid API response"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}
```

### SwiftUI Bindings

Use `@Published` for view bindings:

```swift
@Published var llmBaseURL: String? = nil  // ✅ Correct
```

## 🧪 Testing Your Changes

Before submitting:

1. **Build the project**:
   ```bash
   swift build -c release
   ```

2. **Test manually**:
   ```bash
   open DoubleTapTalk.app
   # Test recording, transcription, injection
   ```

3. **Check logs**:
   ```bash
   ./view-logs.sh watch
   ```

4. **Verify no regressions**:
   - Speech recognition works
   - Text injection succeeds
   - Settings persist correctly

## 📝 Commit Messages

Follow conventional commit format:

```
type(scope): description

[optional body]
[optional footer]
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `chore`: Maintenance tasks
- `test`: Adding tests

### Examples
```
feat(asr): add Qwen3 ASR backend support
fix(settings): persist llmBaseURL across app restarts
docs(readme): update Chinese translation
```

## 🔧 Development Setup

### Prerequisites
- macOS 13.0+
- Swift 5.9+
- Xcode Command Line Tools (`xcode-select --install`)

### Building Locally
```bash
# Debug build (fast, for development)
swift build

# Release build (optimized, for distribution)
swift build -c release

# Run directly from terminal
.build/debug/DoubleTapTalk
```

### Creating DMG
```bash
./package-dmg.sh
```

## 🤝 Pull Request Process

1. **Update docs**: Include changes to README if needed
2. **Keep scope narrow**: One PR per feature/fix
3. **Test thoroughly**: All features should work after merge
4. **Update version**: Increment version number for releases
5. **Fill out template**: Provide detailed PR description

### PR Checklist
- [ ] Code follows existing style
- [ ] Added logging where appropriate
- [ ] Tested on real hardware
- [ ] Updated documentation
- [ ] No secrets committed
- [ ] Commits are meaningful and atomic

## 🐛 Reporting Bugs

Good bug reports help developers fix issues faster. Please include:

- **Steps to reproduce**: Detailed instructions
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happened
- **Logs**: Output from `~/Library/Caches/DoubleTapTalk.log`
- **Environment**: macOS version, DoubleTapTalk version

Example:
```
## Bug Report

**Steps:**
1. Open DoubleTapTalk
2. Double-click Control
3. Speak Chinese text
4. Release Control

**Expected:** Transcribed text appears in active app
**Actual:** Empty result, no error shown
**Logs:** [paste relevant log lines here]
**macOS:** 14.2 Sonoma
**DoubleTapTalk:** v1.0.0
```

## 🎨 Style Guide

- Use `let` over `var` when possible
- Prefer functional programming patterns
- Keep functions small and focused
- Comment complex logic
- Follow Apple's Human Interface Guidelines

## 📜 Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and their questions
- Focus on constructive feedback
- Accept responsibility for mistakes

## 🙏 Thank You

Every contribution matters, whether it's a code fix, documentation improvement, or helpful suggestion. Thank you for helping make DoubleTapTalk better!

---

**Have questions?** Feel free to:
- Open an issue on GitHub
- Check existing documentation
- Review related pull requests

---

Last Updated: 2024-04-06  
Author: Jiajun Chen <tychenjiajun@live.cn>
