# VoiceKey

A macOS menu-bar-only push-to-talk speech-to-text app that types into any frontmost app.

## Features

- **Push-to-Talk**: Hold Right Option key to record, release to transcribe
- **Multiple ASR Backends**: OpenAI Whisper, Groq, or local whisper.cpp server
- **No Dock Icon**: Runs entirely in the menu bar (LSUIElement)
- **Keychain Storage**: API keys stored securely in macOS Keychain
- **Launch at Login**: Toggle via SMAppService (macOS 13+)
- **Settings Panel**: Configure backend, API key, language, model

## Requirements

- macOS 13.0+
- Xcode 15.0+
- Accessibility permissions (for global hotkey)
- Microphone permissions (for audio recording)

## Build Instructions

1. Open the project in Xcode:
   ```bash
   open VoiceKey.xcodeproj
   ```

2. Select your development team in the project settings

3. Build and run (⌘R)

4. Grant required permissions when prompted:
   - **Accessibility**: System Settings > Privacy & Security > Accessibility
   - **Microphone**: System Settings > Privacy & Security > Microphone

## Usage

1. Launch VoiceKey - it appears only in the menu bar (no Dock icon)
2. Click the mic icon in the menu bar and select "Settings..."
3. Choose your ASR backend (OpenAI Whisper, Groq, or Local)
4. Enter your API key (stored securely in Keychain)
5. Hold Right Option key to record audio
6. Release to transcribe and automatically type the result

## ASR Backends

### OpenAI Whisper
- Requires OpenAI API key
- Uses `whisper-1` model by default
- Endpoint: `https://api.openai.com/v1/audio/transcriptions`

### Groq
- Requires Groq API key (free tier available)
- Uses `whisper-1` model by default
- Endpoint: `https://api.groq.com/openai/v1/audio/transcriptions`

### Local (whisper.cpp)
- No API key required
- Requires a local whisper.cpp server running
- Default endpoint: `http://localhost:8080/v1/audio/transcriptions`

## Project Structure

```
Sources/VoiceKey/
├── App/
│   └── VoiceKeyApp.swift          # Main app entry
├── Models/
│   ├── Settings.swift             # App settings
│   └── ASRBackend.swift           # Protocol & errors
├── Services/
│   ├── AudioRecorder.swift        # 16kHz WAV recording
│   ├── ASRService.swift           # ASR backend management
│   ├── HotkeyService.swift        # Global hotkey detection
│   ├── KeychainService.swift      # Secure API key storage
│   └── TextInjectionService.swift # Text injection
├── Views/
│   ├── StatusBarController.swift  # Menu bar item
│   ├── SettingsWindowController.swift
│   └── SettingsView.swift         # SwiftUI settings
└── Backends/
    ├── OpenAIWhisperBackend.swift
    ├── GroqBackend.swift
    └── LocalWhisperBackend.swift
```

## Technical Details

- **Audio Format**: 16kHz mono WAV
- **Hotkey**: Right Option key (via CGEventTap)
- **Text Injection**: CGEvent keyboard events with Cmd+V fallback
- **API Keys**: Stored in macOS Keychain (never in UserDefaults)
- **Login Item**: Uses SMAppService (macOS 13+)

## Debugging & Logs

VoiceKey includes comprehensive logging to help debug issues.

### Log File Location

```
~/Library/Caches/VoiceKey.log
```

### Viewing Logs

Use the included helper script:

```bash
# View last 50 lines
./view-logs.sh

# View last 100 lines
./view-logs.sh 100

# View all logs
./view-logs.sh all

# Follow logs in real-time
./view-logs.sh watch

# Clear logs
./view-logs.sh clear
```

Or use terminal commands directly:

```bash
# View logs
tail -f ~/Library/Caches/VoiceKey.log

# Clear logs
> ~/Library/Caches/VoiceKey.log
```

### Log Levels

- **INFO**: Key events (start/stop recording, transcription results, etc.)
- **DEBUG**: Detailed information for troubleshooting
- **WARN**: Non-critical issues
- **ERROR**: Critical errors that need attention

### Common Issues

1. **"Failed to create event tap"**: Grant Accessibility permissions
2. **"No API key configured"**: Set API key in Settings
3. **"No frontmost application found"**: Focus a text input field
4. **"Server error"**: Check network connection and API endpoint

## Entitlements

- `com.apple.security.device.audio-input` - Microphone access
- `com.apple.security.automation.apple-events` - System events
- `com.apple.security.network.client` - API calls

---

## Distribution

### Manual Packaging

```bash
# Make script executable
chmod +x package.sh

# Run packaging script
./package.sh
```

This creates `VoiceKey-1.0.0.dmg` in the project root.

### GitHub Releases (Automated)

1. **Push a version tag:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **GitHub Actions** will automatically:
   - Build the release version
   - Create a .dmg
   - Upload as a draft release

3. **Publish the release** on GitHub

### Code Signing (For Distribution)

For notarization, configure in Xcode:
- Select VoiceKey target → Signing & Capabilities
- Enable "Automatically manage signing"
- Set Distribution to "Developer ID Application"
- Or use ad-hoc signing for personal use

### Notarization (Optional)

```bash
# After signing, notarize:
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Release \
  archive

# Submit for notarization
xcrun notarytool submit VoiceKey.xcarchive \
  --apple-id your@email.com \
  --password "app-specific-password" \
  --team-id YOUR_TEAM_ID
```