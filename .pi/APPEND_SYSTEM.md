# DoubleTapTalk - Critical Notes & Lessons

## 🐛 Bug Fixes

### Language Translation Issue (English → Chinese)

**Symptoms:**
- User speaks English but LLM translates to Chinese instead of polishing

**Root Causes:**

1. **Google Gemini API Format Error** (`LLMService.swift`)
   - ❌ OLD: Concatenated system prompt + user input into single text block
   - ✅ FIXED: Use `system_instruction` parameter to separate instructions from content
   
2. **Weak Prompt Instructions** (`PolishModels.swift`)
   - ❌ OLD: "LANGUAGE PRESERVATION" rules were too subtle for some models
   - ✅ FIXED: 
     - Added ⚠️ warning symbols and "ABSOLUTELY MANDATORY" emphasis
     - Included explicit WRONG vs RIGHT examples for each profile
     - Extracted all profiles to use shared `languagePreservationSection` constant

---

## 🔧 System Architecture

### Prompt Structure

All polish profiles share these components to avoid duplication and ensure consistency:

```swift
// Shared constants (defined outside extension)
private let languagePreservationSection = "..."  // ⚠️ anti-translation rules
private let baseInstruction = "Output ONLY..."
private let defaultExamples = "..."
private func buildContextHint(...) -> String

// Each profile uses them
func systemPrompt(context: PolishContext) -> String {
    let contextHint = buildContextHint(...)
    return "\(baseInstruction)\n\(languagePreservationSection)\n[profile-specific rules]\n\(contextHint)"
}
```

**7 Profiles:** `.terminal`, `.general`, `.searchQuery`, `.codeEditor`, `.codeComment`, `.chatMessaging`, `.emailFormal`, `.tradingTerminal`

---

## 📋 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Shared prompt sections** | DRY principle; update anti-translation rules in one place |
| **Explicit WRONG/RIGHT examples** | Stronger signal than abstract rules alone |
| **Separate system_instruction for Google API** | Required by Google's API spec |
| **Compact prompts (~100-150 chars)** | Faster, cheaper, less confusing for models |

---

## 🔨 Build & Deployment

### Build Commands

```bash
# Clean rebuild
xcodebuild clean -project DoubleTapTalk.xcodeproj -scheme DoubleTapTalk -configuration Release

# Full build
xcodebuild -project DoubleTapTalk.xcodeproj -scheme DoubleTapTalk -configuration Release \
  -derivedDataPath build/DerivedData build

# Install to Applications
cp -R build/DerivedData/Build/Products/Release/DoubleTapTalk.app /Applications/

# ⭐ Re-sign (REQUIRED after every rebuild!)
codesign --force --deep --sign - /Applications/DoubleTapTalk.app
```

### After Reinstallation

1. **Re-sign the code** ⭐ REQUIRED AFTER EVERY REBUILD ⭐:
   ```bash
   codesign --force --deep --sign - /Applications/DoubleTapTalk.app
   ```
2. **Grant Accessibility permission** → System Settings → Privacy → Accessibility
3. **Grant Microphone permission** → System Settings → Privacy → Microphone
4. **Restart app**: `open /Applications/DoubleTapTalk.app`

---

## 📂 Key Files

| File | Purpose |
|------|---------|
| `Sources/DoubleTapTalk/Services/LLMService.swift` | Calls OpenAI/Anthropic/Google APIs |
| `Sources/DoubleTapTalk/Models/PolishModels.swift` | Profile detection + prompt templates |
| `view-logs.sh` | Quick log viewer (`./view-logs.sh 100` or `./view-logs.sh watch`) |
| Log location | `~/Library/Caches/DoubleTapTalk.log` |

---

## 🧪 Testing Checklist

After deploying fixes:

- [ ] Speak English → Should NOT translate to Chinese
- [ ] Speak Chinese → Should remain Chinese (not pinyin)
- [ ] Mixed scripts → Keep all scripts intact
- [ ] Test across apps: Terminal, VSCode, Slack, Mail
- [ ] Verify accessibility permissions active
- [ ] Check logs for prompt sent to LLM
