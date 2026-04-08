# Terminal Polish Update - Binary-Aware Command Detection

## Problem
The previous terminal polish profile was **too aggressive** at converting speech to commands:
- "check the logs" → `tail -f /path/to/logfile`
- "git commit my changes" → `git add . && git commit...`  
- "show current directory" → `cd ~/projects/...`

This caused unintended command execution when you were just discussing or asking questions.

## Solution
Updated the terminal polish system prompt with **binary-aware, intent-sensitive** logic:

### Changes Made

1. **Added `detectTerminalBinary()` function**
   - Detects current shell (zsh, bash, fish) from terminal prompt
   - Identifies when inside coding agent environments
   - Extracts current command being typed

2. **Enhanced `.terminal` profile system prompt**
   - Distinguishes between:
     - **Action intents**: "run", "execute", "build", "test" → Convert to command
     - **Question/descriptive intents**: "check the logs", "why did", "what's happening" → Keep as natural language
   - Smart rules for git work: keeps descriptions as-is unless explicit commit/push
   - Conservative default: if uncertain, keep natural language (not command)

3. **Context injection**
   - Current shell/binary shown in LLM prompt for better context
   - Terminal prompt line analyzed for binary detection

## New Behavior Examples

| Speech | Old Behavior | New Behavior |
|--------|-------------|--------------|
| "check the logs" | `tail -f /var/log/...` | "check the logs" (kept as-is) |
| "list all files" | `ls -la` | "list all files" (kept as-is) |
| "run tests" | `npm test` | `npm test` (action word detected) |
| "build the project" | `make` | `make` (action word detected) |
| "commit with message fix bug" | N/A | `git commit -m "fix bug"` |
| "I'm seeing an error here" | Markdown code block | "I'm seeing an error here" |

## Testing
Test cases to verify:
1. Say descriptive phrases like "check recent commits" → Should stay as text
2. Say action phrases like "build and run" → Should convert to `build && run`
3. Say question phrases like "why is this failing" → Should stay as text
4. Say explicit commands like "install dependencies" → Should convert to `npm install`

## Files Changed
- `Sources/DoubleTapTalk/Models/PolishModels.swift`
  - Added `detectTerminalBinary(from:)` helper method
  - Enhanced `.terminal` profile system prompt with intent analysis
  - Added conservative conversion defaults
