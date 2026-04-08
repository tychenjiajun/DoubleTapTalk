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
