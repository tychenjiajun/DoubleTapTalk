# Prompt Engineering Fixes

## Problem: LLM Hallucinations

On 2026-04-08, we discovered a critical bug where the LLM was producing **completely unrelated output**:

- **Input**: "Carefully check and learn the implementation from the original tables, and fix all the TypeScript bugs reported by your TSC. No emits." (134 chars)
- **Output**: "I'm looking for recent errors" (29 chars) ❌

### Root Cause: Contradictory Instructions

The `wrapUserContent()` function was adding contradictory prefixes:

```swift
// BEFORE - CONTRADICTORY
case .terminal:
    return "Convert this speech to terminal input: \(text)"
```

This **contradicted** the system prompt which said:
> "NEVER convert descriptions, questions, or meta-commentary into commands"

The LLM received mixed signals and hallucinated unrelated content.

---

## Solution Applied

### 1. Unified Neutral Wrapper

All profiles now use neutral framing in `LLMService.swift`:

```swift
// AFTER - CONSISTENT AND NEUTRAL
case .terminal:      return "Speech to polish: \(text)"
case .searchQuery:   return "Speech to polish: \(text)"
case .codeComment:   return "Speech to polish: \(text)"
// ... all other profiles
```

**Rationale**: The system prompt already establishes context. The wrapper should just deliver the text cleanly.

### 2. Enhanced System Prompts

All 8 polish profiles in `PolishModels.swift` now include:

- ✅ **"CRITICAL"** statement emphasizing preservation of original meaning
- ✅ **Explicit "Do NOT" rules** preventing unwanted transformations
- ✅ **"When in doubt, keep the original wording"** fallback
- ✅ **Concrete examples** showing expected behavior
- ✅ **"Do NOT add content that wasn't spoken"** constraint

#### Key Profile Improvements

**Terminal Profile**:
- NEVER convert descriptions, questions, or meta-commentary into commands
- ALWAYS keep as natural language for questions ("why", "what", "how")
- ALWAYS keep as natural language for descriptions ("I'm looking for")

**Code Comment Profile**:
- Do NOT expand or add content that wasn't spoken
- Preserve all technical terms exactly

**General Profile**:
- Do NOT paraphrase or rewrite sentences
- Preserve all names, places, numbers, and technical terms exactly

---

## Testing

Check logs for potential hallucinations:

```bash
# Watch for length mismatches (hallucination indicator)
grep -E "Original ASR text|Polished text final" ~/Library/Caches/DoubleTapTalk.log | tail -20
```

If polished text is significantly shorter than original without good reason, investigate.

---

## Files Changed

- `Sources/DoubleTapTalk/Services/LLMService.swift` - Unified neutral `wrapUserContent()`
- `Sources/DoubleTapTalk/Models/PolishModels.swift` - Enhanced all 8 profile system prompts

---

**Date**: 2026-04-08  
**Impact**: Prevents LLM hallucinations from contradictory instructions

---

# Live Prompt Evals (liquid/lfm-2.5-2.6b:free)

## Why a 2.6B model

Static prompt tests (`PromptEconomyTests`, `PolishProfileTests`) can only check
that a prompt *says* the right thing. They cannot tell you whether a model
*obeys* it. `Tests/VoiceKeyTests/RefinementPromptEvalTests.swift` runs all eight
refinement prompts against a real — and deliberately small — model
(`liquid/lfm-2.5-2.6b:free` on OpenRouter, free tier) through the shipping path
(`LLMService.polish` with a pinned profile):

```bash
OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEvalTests
```

Without the key the suite skips, so `swift test` stays offline-green.

The model is small on purpose: it is cheap, deterministic enough to diff, and it
violates instructions that a 7B+ model would quietly absorb.

## Findings and fixes

Each finding was measured over repeated samples (the model is non-deterministic
even at temperature 0.3) and only fixed after a candidate was re-measured.

| # | Symptom (input → output) | Root cause | Fix | Before → After |
|---|---|---|---|---|
| 1 | `查看 日志 帮 我 看一下 昨天 的 报错` → `I'll check the logs for you.` | The anti-translation rule lives only in the *system* prompt; small models weight the nearest instruction far more | Repeat the script rule in the user turn (`LLMService.wrapUserContent`) | 3/6 → 6/6 kept Chinese |
| 2 | `haha yeah that is totally fine lol see you tomorrow` → `Yeah, that's totally fine. See you tomorrow!` | `chatMessaging` said "keep tone, humor" but gave no explicit slang protection | Added `NEVER delete casual slang or expressions (lol, haha, omg, btw)` | slang dropped ~1 run in 5 → ~1 in 8 |
| 3 | `um so like we should probably ship it tomorrow right` → `So like we should probably ship it tomorrow` | `general` listed `like` as a filler but not that fillers go mid-sentence | `strip filler words (…) wherever they appear` | 4/5 → 5/5 |
| 4 | Field already contains `今天我们讨论了`, dictation `这个 方案 的 风险 有点 高` → output `今天我们讨论了` (the new words were **dropped**) | The context block was fenced with ` ``` `, which small models read as "this is the output" | Context hints are unfenced and explicitly labelled `context only — your output must contain ONLY the new utterance` | 4/5 → 5/5 |

Fix #1 belongs in the user turn because a stronger *system* prompt did not help
(`Hard rule: …` variant still lost Chinese 3/6) — the same lever fix #4 uses.

## Writing the assertions

Two traps, both hit while building this suite:

- **Assert the rule, not one wording.** Requiring the literal `do not` from the
  email profile failed on a perfectly good rewrite ("please ensure it is
  completed"). The rule is "no contractions survive" — assert that.
- **Sample, then vote.** This model is non-deterministic; a strict 3/3 on a
  ~85%-compliant rule makes the eval flap. Behavioural rules run 3 samples and
  require 2; hard invariants (non-empty, no fences, no preamble, CJK never
  translated) must hold on every sample.

## Rate limits

The free tier allows ~20 requests/minute and OpenRouter's `lfm` route is a
*shared* upstream pool (`limit_source: upstream_provider_shared_pool`), so
congestion produces 429s **and** occasional low-quality samples. The harness
spaces requests 4s apart and retries with 15s/30s/45s back-off.

---

**Date**: 2026-04-09  
**Impact**: 4 prompt regressions found and fixed by a repeatable live eval

---

## Bug Fix: Microphone Permission Not Requested on Start Recording

### Date: 2026-04-13

### Symptoms
- User grants microphone permission in System Settings
- Clicking "Start Recording" from menu doesn't actually enable microphone
- No clear error message about permission status
- Recording appears to start but no audio is captured

### Root Cause
`AVAudioRecorder.record()` was called without explicitly checking or requesting microphone permission first. On macOS:
1. `AVAudioRecorder` should auto-prompt for permission on first use
2. But if permission was previously denied or in an inconsistent state, `record()` may fail silently
3. No clear feedback to user about permission status

### The Fix

**New File: `Services/MicrophonePermissionService.swift`**
```swift
final class MicrophonePermissionService {
    static let shared = MicrophonePermissionService()
    
    func hasMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }
    
    func requestPermission() async -> Bool {
        // Shows system permission dialog if needed
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
```

**Updated: `Services/AudioRecorder.swift`**
```swift
func startRecording() async throws {
    // Check and request microphone permission BEFORE recording
    if !permissionService.hasMicrophonePermission() {
        let granted = await permissionService.requestPermission()
        if !granted {
            throw NSError(
                domain: "AudioRecorder",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please grant in System Settings > Privacy & Security > Microphone"]
            )
        }
    }
    // ... continue with recording
}
```

**Updated: `App/DoubleTapTalkApp.swift`**
```swift
// Check permission at launch
if MicrophonePermissionService.shared.hasMicrophonePermission() {
    logger.info("Microphone permission granted")
} else {
    logger.warning("Microphone permission not granted — recording will prompt for permission")
}

// Updated startRecording to call async method
private func startRecording() {
    Task {
        do {
            try await audioRecorder.startRecording()
            // ...
        } catch {
            // Shows clear error to user
        }
    }
}
```

### Lessons Learned

1. **Explicit Permission Checks**: Always check permission state explicitly before using protected resources, even if the API claims to auto-prompt.

2. **Clear Error Messages**: When permission is denied, provide actionable guidance ("Go to System Settings > Privacy & Security > Microphone").

3. **Async Permission Requests**: macOS permission dialogs are async - use `async/await` pattern for clean handling.

4. **Early Status Logging**: Log permission status at app launch so users know the current state before attempting to record.

5. **Consistent Pattern**: Follow the same pattern as `AccessibilityService` for permission handling.

### Testing Checklist

- [ ] Fresh install: Permission dialog appears on first "Start Recording" click
- [ ] Permission granted: Recording starts immediately
- [ ] Permission denied: Clear error message shown, user directed to System Settings
- [ ] Permission granted after denial: Recording works after user grants in Settings
- [ ] Hotkey trigger: Same permission flow works for double-tap Control hotkey

### Files Changed
- `Sources/DoubleTapTalk/Services/MicrophonePermissionService.swift` (NEW)
- `Sources/DoubleTapTalk/Services/AudioRecorder.swift` (updated to async + permission check)
- `Sources/DoubleTapTalk/App/DoubleTapTalkApp.swift` (updated startRecording to async)

