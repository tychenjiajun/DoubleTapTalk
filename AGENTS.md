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
| Install + re-sign + launch | `./install.sh` (one-time: `./scripts/setup-signing-identity.sh`) |
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
- Logs go to `~/Library/Caches/DoubleTapTalk.log` (also written to stdout, captured by `./view-logs.sh`). Timestamps are **UTC**; local = UTC+8. Every LLM round-trip logs `LLM request → <endpoint> (transport, model, timeout)` *before* sending and `LLM response ← … in Nms` / `LLM request failed ← … after Nms: <reason>` after — so latency must be attributed from these lines (the per-polish totals are `✓ Polished successfully in Nms` / `LLM polishing failed after Nms`). Never log the endpoint from the response side only: a timed-out request must still say which provider/model it hit.
- The recording overlay has exactly one visual-language source: `Views/Overlay/OverlayState.swift` (`OverlayState` → `OverlayStyle.Resolved`, pure and unit tested) and `Views/Overlay/OverlaySession.swift` (relay HUD copy + `RelaySessionLedger`). Drive it through `RecordingOverlayPanel`'s stage API (`updateLiveText` / `showTranscribing` / `showPolishing` / `showResult` / `showEmpty` / `showError`, plus `beginRelaySession` / `noteSegment*` / `endRelaySession`) — never push raw status strings from the AppDelegate, never change the waveform per call site, and never compute overlay copy there. Continuous dictation is the ONLY mode: the session HUD (fixed height, one truncated line, segment/status column) is the one and only layout.
- Overlay transitions must set the model value synchronously (`setFrame` / `alphaValue`) and animate on the content layer. `animator()` may be silently dropped (no GUI session, non-key window), which used to strand the capsule at a stale width — never depend on it for geometry or opacity.
- User-facing overlay copy lives in those tables (zh-Hans + English), not inline; menu-bar copy follows `OverlayStyle.language()` too.
- Regenerating the project **wipes entitlements**: `project.yml`'s `entitlements:` block makes XcodeGen *generate* `DoubleTapTalk.entitlements` on every `xcodegen generate`, silently discarding anything hand-written into that file. Declare entitlements in `project.yml` under `entitlements.properties` only, and never edit the generated file.
- `ENABLE_HARDENED_RUNTIME: YES` means every gated TCC service needs its entitlement, otherwise tccd refuses to even *prompt* (`Prompting policy for hardened runtime; service: kTCCServiceMicrophone requires entitlement com.apple.security.device.audio-input but it is missing` → `Policy disallows prompt` → denied). The app then never appears in System Settings, and the **Microphone pane has no "+" button**, so it looks un-grantable. Currently required: `com.apple.security.device.audio-input` (mic) and `com.apple.security.automation.apple-events` (opening `x-apple.systempreferences:` panes). Add the entitlement whenever a new Hardened-Runtime-gated service is introduced.
- Never sign with `-` (ad-hoc). Ad-hoc signing makes the Designated Requirement a `cdhash`, which changes on every rebuild, so macOS TCC silently drops the Accessibility/Microphone grants: the System Settings toggle stays ON while tccd logs `Failed to match existing code requirement for subject com.jiajun.doubletaptalk`. `./install.sh` signs every build with the stable local identity `DoubleTapTalk Local Signing` (created by `./scripts/setup-signing-identity.sh`, DR = `identifier … and certificate root = H"…"`), so permission is granted once and survives rebuilds. `install.sh` also kills stale copies launched straight out of `build/DerivedData/` — always run the `/Applications` copy, never the DerivedData one.

## External References
| Need | File |
|------|------|
| Setup & usage | `README.md` |
| Prompt engineering history | `docs/PROMPT_FIXES.md` |
| Spoken abandon (segment drop) RFC | `docs/RFC-001-abandon-segment.md` |
| Polish decision-model RFC (deferred) | `docs/RFC-002-polish-decision.md` |
| Applying the decision model (Bocha Jev) | `docs/JEV_INTEGRATION.md` |
| Contribution guide | `CONTRIBUTING.md` |
| Release pipeline (CI) | `.github/workflows/release.yml` |

## Commit Attribution
AI commits MUST include:
```
Co-Authored-By: (the agent's name and attribution byline)
```