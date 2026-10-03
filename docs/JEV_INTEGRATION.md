# Applying the decision model (Bocha Jev) in DoubleTapTalk

**Audience:** whoever implements [RFC-001](RFC-001-abandon-segment.md) or
[RFC-002](RFC-002-polish-decision.md).
**Model:** `bocha-jev-v1` · **API origin:** `https://jev.bocha.cn` ·
**Client key env var:** `BOCHA_JEV_API_KEY`
**Vendor reference:** https://bocha-ai.feishu.cn/wiki/PhrPwCrEaiCyyPkkDNecdfRSnHR
*(login-walled — see [Unverified items](#unverified-items) before trusting a
detail that is not in this document)*

---

## 1. What this is, and what it is not

Jev is a **rubric scorer**, not a text generator and not a search engine. You
give it a shared piece of context (`state`) plus one or more independently
answerable questions, each with its own type and criteria, and it returns a typed
decision with probabilities.

| It is good at | It is not for |
|---|---|
| Classification with 2–255 named alternatives | Producing any text |
| Rubric scoring on an ordered scale | Retrieval / factual lookup |
| True/false probability for one narrow claim | Executing actions |
| Judging whether a supplied piece of text is X | Judging anything it cannot read — **including audio** |

That last row is the one that decides two of our three use cases: the model sees
only text, so it cannot distinguish "mumbling" from "real speech the ASR
mangled". Both are identical strings. Do not ask it to.

### Use the model when all four hold

1. The decision is a **judgement**, not a threshold on data you already have
   locally (energy, script-vs-language, app bundle ID, `polished == raw`).
2. Getting it wrong is **recoverable** and fail-open is the current behaviour.
3. It can run **concurrently** with work already scheduled, or the segment is
   already waiting on a multi-second remote call.
4. A rubric can express it in a few sentences, with the counter-case named.

If any of those is false, a local heuristic is almost always the better answer —
the log is full of examples (§7).

---

## 2. Provider contract

```
POST https://jev.bocha.cn/v1/systemone
Authorization: Bearer $BOCHA_JEV_API_KEY
Content-Type: application/json
```

```json
{
  "model": "bocha-jev-v1",
  "state": "<string | object | array — shared by every question>",
  "questions": {
    "<caller-chosen-id>": { "type": "...", "instructions": "...", "criteria": ... }
  }
}
```

Response: top level `model`, `answers` (keyed by your question ids), `usage`,
`metadata`. There is **no** `code/msg/data` envelope.

| type | `criteria` | answer fields |
|---|---|---|
| `choice` | object: 2–255 candidate ids → descriptions | `type`, `choice`, `probabilities`, `confidence` |
| `score` | ordered array, 1–10 level descriptions, lowest first | `type`, `score`, `probabilities`, `legend`, `confidence` |
| `noul` | optional `{false, true}` descriptions | `type`, `noul` |

Semantics that are easy to get wrong:

- `score` is the **probability-weighted zero-based index** (3 levels → 0–2), *not*
  the number written in the level description. Probability and legend keys are
  **strings** in JSON.
- `noul` is a **numeric probability of true in [0,1]**, not a boolean. Assert
  `not isinstance(x, bool)` in tests.
- `confidence` = the maximum candidate probability (Choice/Score only).
- Questions are answered **independently** — they share `state` but do not see
  each other. Cross-question policy must be restated inside each rubric.

### Limits

| Limit | Value |
|---|---|
| Questions per request | 1–32 |
| Candidates per request | ≤1024 total (`noul` counts as 2) |
| Request body | ≤256 KiB (262144 UTF-8 bytes), original and normalized |
| **Complete question input** | **32768 tokens**, including template + shared `state` + that question's `instructions` + **all** its candidates |
| String `instructions` | additionally ≤8192 characters |
| Documented rate limit | 200 QPS per user |

`usage.input_tokens` sums the encoded question inputs, so a shared `state` is
counted once per question. `usage.output_tokens` is currently 0.
`metadata.inference_ms` is forward inference only — do not subtract it from
wall-clock latency to estimate network time.

### Verified behaviour (measured 2026-10-03, not quoted from docs)

| Property | Measurement |
|---|---|
| Latency, 1 question | **246–520 ms** wall (inference 180–250 ms) |
| Latency, 2 questions (~1.2K tokens) | 330–570 ms |
| Latency, 4 questions (~2.2K tokens) | 400–640 ms |
| Tokens, one tight question | ~230 |
| Determinism | identical across 3 repeats, every case tested |
| `temperature` present | **HTTP 422 `extra_forbidden`** — no sampling knob |
| `GET /v1/models` | `bocha-jev-v1`, `bocha-jev-latest`, `jev-latest` (aliases) |

### Error handling

| Code | Action |
|---|---|
| 401 | Fix the credential. Do not retry. |
| 413 / 422 | Fix size/types/content. No automatic truncation exists — shorten `state`/`instructions`/candidates. Do not retry unchanged. |
| 429 / 503 / 529 | Honour `Retry-After`, bounded backoff (≤2 retries). |
| anything else / timeout | Fail open to current behaviour. |

---

## 3. Placement rules in this project

These are consequences of the architecture, not preferences.

1. **One polish site, one insertion site.** `Services/PolishProcessor.swift`
   performs all polishing; `AppDelegate.inject(_:expectedTarget:)` performs all
   insertion. A decision may sit *beside* those, never as a parallel path
   (AGENTS.md).
2. **Never serialize the decision in front of polish or cloud ASR.** Relay
   segments run through `OrderedTaskChain`, which orders *emission* — a serial
   +0.3 s per segment compounds across a burst and lengthens the tail. Issue the
   decision and the polish request together on the post-cloud text and race them;
   if polish wins, proceed.
3. **Fail open, always.** Advisory only. The model may turn an insert into a
   discard when confident; it must never turn a discard into an insert, nor
   replace text.
4. **Own deadline, ~600 ms.** Do not inherit `LLMSettings.timeout` (30 s).
5. **Exclude discarded content from `previousSegments`.** `insertRelaySegment`
   appends to `segmentHistory`, and that history is fed into the next segment's
   polish prompt. Anything dropped must not be appended.
6. **Generation-guard everything.** Relay work is guarded by
   `isCurrentGeneration(_:)`; a verdict that arrives after its session ended is
   dropped, exactly like a late polish result.
7. **No new entitlements.** The app is not sandboxed and outgoing HTTP needs no
   entitlement; if a decision ever needs a *new* gated TCC service, it must be
   declared in `project.yml` → `entitlements.properties` (never hand-edit the
   generated `.entitlements`).

---

## 4. Settings and secrets

Follow the existing `LLMSettings` / `ASRSettings` pattern:

- Secret in the **Keychain**: add `bochaJevAPIKey` to `KeychainStore.Account` and
  persist through the same `persistSecret(_:keychainKey:defaultsKey:)` helper the
  LLM/ASR keys use. Never in `UserDefaults`, never in source, never in logs.
- `UserDefaults` keys: `DecisionModelEnabled` (default **false**),
  `DecisionModelBaseURL` (default `https://jev.bocha.cn`),
  `DecisionModelModel` (default `bocha-jev-v1`),
  `DecisionModelTimeout` (default 0.6 s — not 30).
- Build a snapshot with a static `current()` returning a value type
  (`DecisionSettings`), so call sites never reach into the settings singleton —
  same shape as `ASRSettings.current()`.
- Ship it **off by default** and only for the features RFC-001 approves. A
  second remote dependency in the core loop multiplies failure modes; it earns
  default-on with log evidence, not with a probe.

---

## 5. Logging contract

Every other remote call in this app is attributable; this one must be too. Follow
`LLMService`'s pattern (request logged **before** sending, outcome after, with
elapsed ms in both cases) into `~/Library/Caches/DoubleTapTalk.log` (UTC
timestamps):

```
Decision request → https://jev.bocha.cn/v1/systemone (model: bocha-jev-v1, question: abandon, timeout: 0.6s)
Decision response ← https://jev.bocha.cn/v1/systemone in 312ms (abandon noul=0.962, in_tokens=241)
Decision request failed ← https://jev.bocha.cn/v1/systemone after 601ms: timeout
```

Then one outcome line at the decision point, so the effect is measurable:

```
Relay segment 3: abandon verdict 0.962 ≥ 0.5 — dropped (41 chars, decision 312ms)
Relay segment 3 injected in 1902ms (cloud 903ms · polish 0ms · decision 298ms · 41 chars)
```

Never log the API key, and never log the endpoint only on the success path — a
timed-out request must still say which provider/model it hit.

---

## 6. Prompt design rules (measured, not stylistic)

1. **Name the embedding context inside `state`.** `state` is the app frame the
   question is answered against ("终端里的编码助手对话输入框。这一段的最终转写结果：…").
   Removing it measurably hurt accuracy.
2. **Name the counter-case in `instructions` and say what to do when unsure.**
   The phrases "注意：如果用户只是在…（属于正常内容）" and "如果你无法确定，选 keep/答案为
   false" are load-bearing: they are what turned a 0.71 false positive on
   「刚才那个功能不要了 改成异步的」 into 0.101.
3. **Give the whole text, not a fragment.** The same sentence scored 0.71 alone
   and 0.101 inside its segment. Provide all evidence the human would need.
4. **One question per decision.** Bundling makes policies fight each other; and
   a "which one?" companion question measurably hurt (RFC-001 Probe B: 8/11 vs
   10/10).
5. **Phrasing drives the answer.** The same input moved between `use_cloud 0.78`
   and `keep_apple 0.67` across two instruction wordings. Treat a rubric edit as
   a prompt change that needs the eval harness re-run — exactly like the polish
   profiles.
6. **Watch the token budget.** Shared `state` is charged to *every* question, and
   a whole question's allowance is 32K tokens including candidates.
7. **`noul` before `choice`** when the decision is binary — one question, no
   candidate-description bias, and a probability you can threshold.

---

## 7. When *not* to use it (from the log, with the numbers)

| Tempting use | Why it fails | Evidence |
|---|---|---|
| Decide whether the transcript is garbage → abort | Every "garbage-looking" segment was real speech rescued by cloud ASR; text-only, mumbling and mangled speech are identical | `Can Sharma` → 「你可以看一下吗？就是如果要，呃，修饰一段的话，它大概需要多长的时间？」; `Can can` → 「看看日志。」; `Since I was so calm` → 「现在我试一试看。」 — 5/5 checked |
| Decide whether to use cloud ASR | +40 % on a p50 ≈1.0 s step to skip it sometimes; suspicious-looking text is the text that most needs cloud; answer flips with phrasing | cloud ASR replaced Apple text in 89/119 real segments |
| Decide whether to polish (serial) | Fires mostly on eval fixtures; real dictation is 6 of 7 prose that needs polish; serial cost lands on 100 % of segments | RFC-002 §2–3 |
| Silence/energy gating | Already handled locally and for free | 47 empty-text segments dropped, `peak 0.01–0.03` |

---

## 8. Evaluation harness

Copy the `RefinementPromptEvalTests` pattern (`Tests/VoiceKeyTests/`): a test that
**skips unless `BOCHA_JEV_API_KEY` is set**, so CI stays offline.

Assertions worth having:

- HTTP 200 and `answers` present for every question id.
- `noul` is a number in [0,1] and **not** a bool; `choice` is one of the supplied
  ids; `score` is within `0...(levels-1)`.
- For `choice`, probabilities sum to ≈1 and `confidence == max(probabilities)`.
- **Stability**: run each case 2–3 times and assert identical answers — the model
  is deterministic, so variation means the rubric is ambiguous.
- **Separation**: assert `min(positive group) > max(negative group)` rather than
  asserting exact values, so small model updates do not make the suite brittle.
- Never assert on `metadata.inference_ms` or `usage` values beyond sanity bounds.

Include the real phrasings the user actually uses, not only invented ones — the
RFC-001 probe was 10/10 on careful phrasings and the eval fixtures are what
misled the polish analysis.

---

## 9. Reference implementation (Swift)

Advisory, single-shot, own timeout, fail-open — the shape every call site should
use. Not a second polish or injection path.

```swift
import Foundation

private let logger = FileLogger.shared

/// One decision, one deadline, never throws for provider failure: callers get
/// `nil` and must continue with their existing behaviour.
final class DecisionModelService {
    static let shared = DecisionModelService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0.6      // not LLMSettings.timeout
        config.timeoutIntervalForResource = 1.2
        self.session = URLSession(configuration: config)
    }

    /// - Returns: P(true) for the question, or nil when unavailable/undecided.
    func noul(
        questionID: String,
        instructions: String,
        trueCase: String,
        falseCase: String,
        state: String,
        settings: DecisionSettings
    ) async -> Double? {
        guard settings.enabled, let key = settings.apiKey, !key.isEmpty else { return nil }

        let payload: [String: Any] = [
            "model": settings.model,
            "state": state,
            "questions": [
                questionID: [
                    "type": "noul",
                    "instructions": instructions,
                    "criteria": [
                        "true": ["description": trueCase],
                        "false": ["description": falseCase],
                    ],
                ]
            ],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        var request = URLRequest(url: settings.baseURL.appendingPathComponent("v1/systemone"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let endpoint = request.url?.absoluteString ?? settings.baseURL.absoluteString
        logger.info("Decision request → \(endpoint) (model: \(settings.model), question: \(questionID), timeout: \(Int(settings.timeout))s)")

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Decision request failed ← \(endpoint) after \(ms)ms: http \(code)")
                return nil
            }
            guard
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let answers = root["answers"] as? [String: Any],
                let answer = answers[questionID] as? [String: Any],
                let value = answer["noul"] as? NSNumber,
                !(value is Bool) || String(describing: type(of: value)) != "__NSCFBoolean"
            else {
                logger.info("Decision request failed ← \(endpoint) after \(ms)ms: malformed answer")
                return nil
            }
            let tokens = (root["usage"] as? [String: Any])?["input_tokens"] as? Int ?? 0
            logger.info("Decision response ← \(endpoint) in \(ms)ms (\(questionID) noul=\(value.doubleValue), in_tokens=\(tokens))")
            return value.doubleValue
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let reason = (error as? URLError)?.code == .timedOut ? "timeout" : "\(error.localizedDescription)"
            logger.info("Decision request failed ← \(endpoint) after \(ms)ms: \(reason)")
            return nil
        }
    }
}
```

Call-site shape in `AppDelegate.insertRelaySegment` (Phase 1 of RFC-001):

```swift
// Race the verdict against polish; never serialize it in front of it.
async let polished = PolishProcessor().process(
    rawText: text, settings: LLMSettings.current(), previousSegments: segmentHistorySnapshot())
async let verdict = DecisionModelService.shared.noul(
    questionID: "abandon", instructions: Self.abandonInstructions,
    trueCase: "明确指示放弃这段口述（整段丢弃、重说、作废）",
    falseCase: "正常口述内容，即使里面提到了不要/删除/算了",
    state: "终端里的编码助手对话输入框。这一段的最终转写结果：\n「\(text)」\n（这一段已经口述完毕）",
    settings: DecisionSettings.current())

let decided = await verdict
if let p = decided, p >= 0.5 {
    await MainActor.run { self.recordingOverlay.noteSegmentAbandoned() }
    logger.info("Relay segment: abandon verdict \(p) ≥ 0.5 — dropped (\(text.count) chars)")
    return                       // do NOT appendSegmentHistory(text)
}
text = await polished
```

---

## 10. Unverified items

The vendor's full API reference is a login-walled Feishu wiki page (verified
unreachable anonymously: `curl` → login redirect, wiki API → `{"code":5,"msg":"Login Required"}`,
`r.jina.ai` → timeout). Everything above comes from the public skill contract
(`https://jev.bocha.cn/install/bocha-jev/SKILL.md`) plus live measurement. Still
unconfirmed:

- SDK examples and any client libraries.
- Account-specific quotas and the real QPS/settlement behaviour.
- Error-code details beyond 401/413/422/429/503/529, and the `Retry-After` semantics.
- The legacy `data[].max_candidate_tokens` field in `/v1/models` for this model
  (the skill contract says it is retained for compatibility and its value, 32768,
  applies to a complete question).

Do not invent these in code or docs; treat an unfamiliar response shape as a
fail-open case.

---

## References

- [RFC-001-abandon-segment.md](RFC-001-abandon-segment.md) — spoken abandon (recommended)
- [RFC-002-polish-decision.md](RFC-002-polish-decision.md) — polish gate (deferred) and the faithfulness check
- `Sources/DoubleTapTalk/Services/LLMService.swift` — the logging + timeout pattern to mirror
- `Sources/DoubleTapTalk/Models/ASRSettings.swift`, `Models/LLMProvider.swift` — the settings snapshot pattern (`LLMSettings`, `ASRSettings.current()`)
- `Sources/DoubleTapTalk/Services/KeychainStore.swift` — where the key goes
- `Tests/VoiceKeyTests/RefinementPromptEvalTests.swift` — the eval pattern to copy
- Public skill contract: https://jev.bocha.cn/install/bocha-jev/SKILL.md