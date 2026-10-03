# 🎤 DoubleTapTalk

<div align="center">

**macOS speech-to-text with AI polish** · **macOS 语音转文字 + AI 润色**

Double-tap the Control key anywhere, speak, and get clean text — constantly listening, polished by an LLM, injected into whatever you're typing in.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Stars](https://img.shields.io/github/stars/tychenjiajun/DoubleTapTalk?style=social)](https://github.com/tychenjiajun/DoubleTapTalk/stargazers)

[简体中文](README_zh-CN.md) · [Issues](https://github.com/tychenjiajun/DoubleTapTalk/issues)

</div>

---

## Overview

DoubleTapTalk turns a double-tap of the Control key into a live dictation session. It listens **on-device** with Apple Speech (audio never leaves your Mac), and as you pause, each segment is automatically inserted into the active application — optionally polished by an LLM first so what lands is clean, punctuation-correct text in your original language.

This is a **continuous dictation** utility: the mic stays open for as long as you talk, segments rotate on silence, and every insertion gets a receipt in the overlay so you always know where you are in the session.

## Features

**🎙️ Core dictation**
- Double-tap Control to start / stop anywhere; no app switching.
- On-device streaming recognition via Apple Speech — live text appears while you speak, no API key required.
- Continuous sessions: segments are cut on silence and inserted automatically; Backspace (or a Control tap) stops the session and discards the active segment.
- Language follows your keyboard input method (auto) or a pinned language (auto / EN / 中文 / ES / FR / DE / JA / KO).
- A floating capsule overlay shows the live waveform, transcript, and per-segment receipts — every pipeline stage has its own visual state, and it collapses to a slim pill while you're silent.

**✨ AI polishing (optional)**
- Every segment can be passed through an LLM before insertion, with earlier segments included as context for consistent terminology and style.
- Conservative by default: fixes recognition errors and punctuation, never rewrites, adds, or translates — your language is preserved.
- Providers: OpenAI, Anthropic (Claude), Google (Gemini), or any OpenAI-compatible endpoint via custom base URL.
- App-specific profiles adapt the polish to the target app: terminal, code comments, chat/messaging, formal email, search queries, code editor, trading terminal, general.

**☁️ Cloud transcription (optional)**
- After a segment finishes, the recording can be sent to an OpenAI-compatible ASR endpoint (default `qwen3-asr-flash`, e.g. Aliyun DashScope) for a more accurate result.
- Falls back to the Apple result on any failure; WAV recordings are kept only for upload and pruned to the newest 20. Manage them (usage / open folder / delete) in Settings.

**🌐 UI**
- Fully bilingual (简体中文 + English), following your system language in the overlay, menu bar, and settings.
- Menu-bar icon reports the live session state and elapsed clock; a dimmed header row updates while dictating.

## Requirements

- macOS 13.0 or later
- A microphone
- For AI polish: an API key from OpenAI, Anthropic, or Google (or any OpenAI-compatible endpoint)

## Installation

### 1. Grab the app

Download the latest DMG from [GitHub Releases](https://github.com/tychenjiajun/DoubleTapTalk/releases), mount it, and drag `DoubleTapTalk.app` to `/Applications`.

> For developers building locally, skip ahead to [Development](#development) — `./install.sh` builds, signs, installs, and launches in one step.

### 2. Grant permissions (one time)

On first launch, macOS asks for microphone access. DoubleTapTalk also needs **Accessibility** permission to read the active app's context (existing text in fields, terminal output) for better polishing — you can grant it later without losing core dictation.

Both grants are listed in **Settings › Permissions**, with status and buttons that open the right System Settings pane:

| Permission | Needed for | If missing |
|---|---|---|
| Microphone | Speech recognition (required) | No recording can start — grant it in System Settings › Privacy & Security › Microphone, then hit **Refresh** |
| Accessibility | Reading app context for polish (recommended) | Polish works, but loses surrounding context |

> ℹ️ **Known macOS quirk:** with hardened runtime, a revoked mic permission can leave the app missing from the Microphone pane entirely, so it looks un-grantable. If the toggle is missing, re-launch from `/Applications` (never from a build folder) and check the pane again.

## Usage

1. **Double-tap Control** — the capsule appears and listening starts.
2. Speak. Text appears live. When you pause, the segment is finalized, polished (if enabled), and inserted into the active app — the overlay shows a receipt (`Seg 3 · ✓ Inserted · 24 chars`).
3. Keep talking; long sessions rotate through segments automatically.
4. **Single-tap Control or Backspace** to end the session. A summary receipt shows what landed, how many characters, and how long it took.

While a session runs, the menu bar shows a live header (segment count + clock) and an **End Continuous Dictation** item — the fallback for stopping without reaching for the hotkey.

## Settings

- **Permissions** — microphone and Accessibility status with System Settings deep links.
- **Speech Recognition** — recognition language (auto-follow or pinned).
- **Continuous Dictation** — segment idle threshold (how long silence must last before a segment is cut; shorter = snappier, longer = fewer splits).
- **AI Text Polishing** — enable/disable, provider, API key, model, temperature, timeout, custom system prompt, and app-specific profiles.
- **Cloud Transcription** — OpenAI-compatible ASR endpoint, model, and recordings management.
- **Reset** — restore every setting to defaults (wipes API keys too — confirmation required).

## Development

Swift Package Manager, no external dependencies; the Xcode project is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```bash
swift build                                   # debug build
swift test                                    # all tests (212)
swift test --filter PolishProfileTests        # one test file
xcodegen generate                             # regenerate the Xcode project after adding files
swift build -c release                        # release build
./install.sh                                  # build, sign with the stable local identity, install to /Applications, launch
./package.sh                                  # local DMG (CI builds the official release DMG)
```

**Signing matters:** macOS TCC drops microphone/accessibility grants when the app is re-signed ad-hoc (the Designated Requirement becomes a cdhash that changes every rebuild). `./install.sh` signs with the stable local identity `DoubleTapTalk Local Signing` — created once by `./scripts/setup-signing-identity.sh` — so grants survive rebuilds. Always run the `/Applications` copy, never one from a build folder.

**Live prompt evals** (hits OpenRouter, needs a key — skipped otherwise):

```bash
OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEvalTests
```

### Logs & debugging

Logs go to `~/Library/Caches/DoubleTapTalk.log` (timestamps are **UTC**; if you're in UTC+8, add 8 hours). Every LLM round-trip logs the endpoint/model before sending and the latency after.

```bash
./view-logs.sh watch          # tail -f the log
./check-polish-logs.sh        # polish pipeline summary from the log
./test-injection.sh browser   # test text injection into a browser (or: native)
```

## Troubleshooting

- **Nothing happens on double-tap Control** → check the menu-bar mic icon. If it's crossed out, the microphone permission is missing: Settings › Permissions shows the exact state with a deep link to the Microphone pane.
- **Recognition returns no text** → make sure macOS Dictation is enabled (System Settings › Keyboard › Dictation); the app deliberately avoids forcing on-device mode, which fails when dictation is off.
- **Polished text is missing** → polishing is optional and fails gracefully: the raw transcript is inserted instead. Check `./check-polish-logs.sh` for `LLM request failed ← … after Nms` lines.
- **Which provider/model did that request hit?** → every request logs `LLM request → <endpoint> (transport, model, timeout)` *before* sending, so latency is always attributable.

## FAQ

**Does my audio leave the Mac?** Only if you enable Cloud Transcription — then the *recording file* is sent to your configured ASR endpoint. Live recognition and (if you skip cloud ASR) the whole default pipeline are fully on-device. The LLM polish sends only the transcribed text + context to your chosen provider.

**Which apps does it work in?** Anything that accepts keyboard input — browsers, terminals, editors, chat apps. App-specific polish profiles tune the LLM prompt per target (e.g. terminal commands vs. chat messages).

**Why does it sometimes ignore what I said?** Segments with no recognized words are skipped quietly; segments that fail to insert are called out in the overlay (`⚠︎ N not inserted`) so you can re-speak them.

## License

MIT — see [LICENSE](LICENSE). Questions? Open an [issue](https://github.com/tychenjiajun/DoubleTapTalk/issues).