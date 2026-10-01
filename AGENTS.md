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
| Test text injection | `./test-injection.sh browser` (or `native`) |

## Adding or Renaming Files
- `Package.swift` lists source files **explicitly** — update it when files are added or renamed.
- Then regenerate the Xcode project (also an explicit file list): `xcodegen generate`.
- Tests under `Tests/VoiceKeyTests/` are picked up automatically by the `DoubleTapTalkTests` SPM target.

## Key Conventions
- Polish prompts live in `Sources/DoubleTapTalk/Models/PolishModels.swift`; shared sections `baseInstruction` + `languagePreservationSection` are reused by every profile via `buildPrompt(role:rule:contextHint:)`.
- Keep profile prompts compact (≤620 chars, enforced by `PromptEconomyTests`). When rewording prompts, update the content assertions in `Tests/VoiceKeyTests/PolishProfileTests.swift`.
- ASR backends conform to `ASRBackend` (`Models/ASRBackend.swift`); streaming backends also emit live partial text + audio level callbacks (`Backends/AppleSpeechBackend.swift` is the reference).
- Polish and injection use exactly one site: `Services/PolishProcessor.swift` → `AppDelegate.finalize`. Never add a second polish/inject path.
- Logs go to `~/Library/Caches/DoubleTapTalk.log` (also written to stdout, captured by `./view-logs.sh`).
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