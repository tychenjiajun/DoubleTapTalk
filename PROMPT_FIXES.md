# Prompt Fixes - Preventing LLM Hallucinations and Contradictions

## Root Cause Analysis

### Problem Discovered (2026-04-08)
The LLM was producing **completely unrelated output** for terminal polish:
- **Input**: "Carefully check and learn the implementation from the original tables, and fix all the TypeScript bugs reported by your TSC. No emits." (134 chars)
- **Output**: "I'm looking for recent errors" (29 chars) ❌

### Root Cause: Contradictory Instructions

**Bug in `wrapUserContent()`**:
```swift
// BEFORE - CONTRADICTORY
case .terminal:
    return "Convert this speech to terminal input: \(text)"
```

This **contradicted** the system prompt which said:
> "NEVER convert descriptions, questions, or meta-commentary into commands"

The LLM received mixed signals:
1. System prompt: "Preserve original meaning, don't convert"
2. User content wrapper: "Convert this speech to terminal input"

**Result**: LLM hallucination - it tried to "convert" by inventing unrelated content.

---

## All Prompt Fixes Applied

### 1. Unified Neutral Wrapper (`LLMService.swift`)
**Changed**: All profiles now use neutral framing
```swift
// AFTER - CONSISTENT AND NEUTRAL
case .terminal:      return "Speech to polish: \(text)"
case .searchQuery:   return "Speech to polish: \(text)"
case .codeComment:   return "Speech to polish: \(text)"
case .codeEditor:    return "Speech to polish: \(text)"
case .tradingTerminal: return "Speech to polish: \(text)"
case .chatMessaging: return "Speech to polish: \(text)"
case .emailFormal:   return "Speech to polish: \(text)"
case .general:       return "Speech to polish: \(text)"
```

**Rationale**: The system prompt already establishes context. The wrapper should just deliver the text cleanly without contradictory instructions.

---

### 2. Enhanced System Prompts (`PolishModels.swift`)

All profiles now include:
- ✅ **"CRITICAL"** statement emphasizing preservation of original meaning
- ✅ **Explicit "Do NOT" rules** preventing unwanted transformations
- ✅ **"When in doubt, keep the original wording"** fallback
- ✅ **Concrete examples** showing expected behavior
- ✅ **"Do NOT add content that wasn't spoken"** constraint

#### Terminal Profile
**Before**:
> "You are converting speech to terminal input. IMPORTANT: Analyze the user's intent carefully."

**After**:
> "You are polishing speech-to-text for terminal input. **CRITICAL: Preserve the user's original intent and meaning.**"

Added explicit rules:
- NEVER convert descriptions, questions, or meta-commentary into commands
- ALWAYS keep as natural language for questions ("why", "what", "how")
- ALWAYS keep as natural language for descriptions ("I'm looking for")
- ALWAYS keep as natural language for testing/commenting ("check if", "see if")

#### Code Comment Profile
**Added**:
- "Do NOT expand or add content that wasn't spoken"
- "When in doubt, keep the original wording"
- Examples showing preservation of technical content

#### Code Editor Profile
**Added**:
- "CRITICAL: Preserve the original meaning and all technical content"
- "Do NOT rewrite or paraphrase the content"
- "Keep roughly the same length as the input"

#### Trading Terminal Profile
**Added**:
- "CRITICAL: Preserve ALL numbers, symbols, and trading instructions exactly as spoken"
- "Do NOT add or remove any trading parameters"
- "When uncertain, keep the original spoken form"

#### Chat Messaging Profile
**Added**:
- "CRITICAL: Preserve the original tone and intent"
- "Do NOT formalize or rewrite the content"
- "Keep emojis or emoticons if mentioned"

#### Email Formal Profile
**Added**:
- "CRITICAL: Preserve all names, dates, numbers, and key information exactly"
- "Do NOT add or remove any substantive content"
- "Keep the same level of detail as the original"

#### Search Query Profile
**Added**:
- "CRITICAL: Preserve all technical terms and key concepts"
- "Do NOT add concepts that weren't mentioned"
- Better examples with technical terms

#### General Profile
**Added**:
- "CRITICAL: Preserve the speaker's original meaning and voice"
- "Do NOT paraphrase or rewrite sentences"
- "Preserve all names, places, numbers, and technical terms exactly"

---

## Testing Checklist

### Terminal Polish
- [ ] "check if the polish is working" → `check if the polish is working` (NOT a command)
- [ ] "I'm looking for recent errors" → `I'm looking for recent errors` (description, not command)
- [ ] "run the tests" → `run the tests` (imperative, keep as-is)
- [ ] "why is the build failing" → `why is the build failing` (question)
- [ ] "build the project" → `build the project` (imperative)

### Code Comment
- [ ] "check if user is logged in" → `check if user is logged in`
- [ ] "this function handles the api retry logic" → `this function handles the API retry logic`

### Code Editor
- [ ] "fix the login bug" → `fix the login bug`
- [ ] "update api endpoint to use v2" → `update API endpoint to use v2`

### Trading Terminal
- [ ] "buy 100 shares of TSLA" → `BUY 100 TSLA`
- [ ] "sell 50 AAPL at 150" → `SELL 50 AAPL LIMIT 150`

### Chat Messaging
- [ ] "hey can you check this out" → `hey can you check this out` (casual preserved)

### Email Formal
- [ ] "i'll send it tomorrow" → `I will send it tomorrow` (contraction expanded)

### General
- [ ] Any dictation → Should preserve meaning, fix only grammar/fillers

---

## Monitoring

Watch logs for hallucination patterns:
```bash
# Check for length mismatches (hallucination indicator)
grep -E "Original ASR text|Polished text final" /Users/chenjiajun/Library/Caches/DoubleTapTalk.log | \
awk -F"'" '{if(NR%2==1) orig=$2; else {split($0,a," "); polished=a[7]; if(length(polished)<length(orig)*0.5) print "⚠️ Potential hallucination:"; print "Original:", orig; print "Polished:", polished; print ""}}'

# Watch for specific problematic patterns
grep -E "TERMINAL POLISH DEBUG|Original ASR|Polished text final" /Users/chenjiajun/Library/Caches/DoubleTapTalk.log | tail -20
```

---

## Files Changed
- `Sources/DoubleTapTalk/Models/PolishModels.swift` - All 8 profile system prompts enhanced
- `Sources/DoubleTapTalk/Services/LLMService.swift` - Unified neutral `wrapUserContent()`

## Version
- Date: 2026-04-08
- Fix: Prevent LLM hallucinations from contradictory instructions
