# Agent Instructions

## Build System
- Swift Package Manager (no external dependencies). The Xcode project is generated from `project.yml` via XcodeGen.

## Commands
| Task | Command |
|------|---------|
| Build | `swift build` |
| Test all | `swift test` |
| Test one file | `swift test --filter PolishProfileTests` |
| Regenerate Xcode project | `xcodegen generate` |
| Release build (.app) | `swift build -c release` or `./package.sh` (DMG) |
| Install + re-sign | `./install.sh`, then `codesign --force --deep --sign - /Applications/DoubleTapTalk.app` |
| Live logs | `./view-logs.sh watch` |
| Check polish pipeline | `./check-polish-logs.sh` |
| Live prompt evals (needs key, hits OpenRouter) | `OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEvalTests` |
| Test text injection | `./test-injection.sh browser` (or `native`) |

## Adding or Renaming Files
- `Package.swift` lists source files **explicitly** — update it when files are added or renamed.
- Then regenerate the Xcode project (also an explicit file list): `xcodegen generate`.
- Tests under `Tests/VoiceKeyTests/` are picked up automatically by the `DoubleTapTalkTests` SPM target.

## Key Conventions
- Polish prompts live in `Sources/DoubleTapTalk/Models/PolishModels.swift`; shared sections `baseInstruction` + `languagePreservationSection` are reused by every profile via `buildPrompt(role:rule:contextHint:)`.
- Two prompt levers are load-bearing and must not be "cleaned up": the script reminder in `LLMService.wrapUserContent` (user turn — the system-prompt guard alone lost Chinese 3/6 on `liquid/lfm-2.5-2.6b:free`) and the unfenced, `context only` labelling of the existing-text / screen-context hints (fenced context made the model answer with the field's text instead of the new utterance). Rationale + measurements: `docs/PROMPT_FIXES.md`.
- `Tests/VoiceKeyTests/RefinementPromptEvalTests.swift` runs every profile prompt against the real model; it skips unless `OPENROUTER_API_KEY` is set. Change a profile rule and re-run it before shipping.
- Keep profile prompts compact (≤620 chars, enforced by `PromptEconomyTests`). When rewording prompts, update the content assertions in `Tests/VoiceKeyTests/PolishProfileTests.swift`.
- Speech recognition streams live text via Apple's Speech framework (`Backends/AppleSpeechBackend.swift`); do **not** set `requiresOnDeviceRecognition` — when macOS Dictation is disabled, forcing on-device makes recognition fail with `kLSRErrorDomain code=201` (no text at all). Continuous "relay" dictation lives in `Backends/ContinuousDictationSession.swift` (idle-based segment rotation, ordered emission via `Services/OrderedTaskChain.swift`). Cloud ASR (`Services/CloudTranscriptionService.swift`) is optional, post-hoc, and must always fall back to the Apple result. WAV recordings (`Services/RecordingFileWriter.swift`) are only written when Cloud Transcription is enabled; writes never block the audio tap, recordings are pruned to the newest 20, and `RecordingStore` powers the Settings panel (usage / open folder / delete all).
- Relay results carry a dictation-generation id: work whose session already ended is dropped, never injected late or appended to the next session's history (`AppDelegate.enqueueRelaySegment`/`finalize`).
- Polish happens at exactly one site: `Services/PolishProcessor.swift`. Injection happens at exactly one site: `AppDelegate.inject(_:)` (`finalize` reveals, relay segments insert quietly). Never add a second polish or inject path.
- Logs go to `~/Library/Caches/DoubleTapTalk.log` (also written to stdout, captured by `./view-logs.sh`).
- The recording overlay has exactly one visual-language source: `Views/Overlay/OverlayState.swift` (`OverlayState` → `OverlayStyle.Resolved`, pure and unit tested) and `Views/Overlay/OverlaySession.swift` (relay HUD copy + `RelaySessionLedger`). Drive it through `RecordingOverlayPanel`'s stage API (`show` / `updateLiveText` / `showTranscribing` / `showPolishing` / `showResult` / `showEmpty` / `showError`, plus `beginRelaySession` / `noteSegment*` / `endRelaySession`) — never push raw status strings from the AppDelegate, never change the waveform per call site, and never compute overlay copy there. One-shot dictation uses the `.focused` layout; continuous dictation uses `.session` (fixed height, one truncated line, segment/status column) and switches back on its own.
- Overlay transitions must set the model value synchronously (`setFrame` / `alphaValue`) and animate on the content layer. `animator()` may be silently dropped (no GUI session, non-key window), which used to strand the capsule at a stale width — never depend on it for geometry or opacity.
- User-facing overlay copy lives in those tables (zh-Hans + English), not inline; menu-bar copy follows `OverlayStyle.language()` too.
- The installed app must be re-signed after every rebuild: `codesign --force --deep --sign - /Applications/DoubleTapTalk.app`.

## External References
| Need | File |
|------|------|
| Setup & usage | `README.md` |
| Prompt engineering history | `docs/PROMPT_FIXES.md` |
| Contribution guide | `CONTRIBUTING.md` |
| Release pipeline (CI) | `.github/workflows/release.yml` |

## Commit Attribution
AI commits MUST include:
```
Co-Authored-By: (the agent's name and attribution byline)
```