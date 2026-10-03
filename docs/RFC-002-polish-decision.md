# RFC-002 — Decision model for polishing (gate, routing, and verification)

**Status:** Deferred — do not implement the gate now. The verification use is
approved for prototyping.
**Date:** 2026-10-03
**Decision model:** `bocha-jev-v1` (see [JEV_INTEGRATION.md](JEV_INTEGRATION.md))
**Related:** [RFC-001](RFC-001-abandon-segment.md) (spoken abandon — the use of
the model that *is* recommended)

---

## Summary

The question was whether a decision model can decide, per segment, **whether to
polish at all** (and which polish profile to use), instead of polishing every
non-empty segment as the pipeline does today.

The measurements say **no, not now, and not as a gate on the critical path**:

1. The classes that make skipping attractive (`git commit …`, `npm test`,
   `func process raw text …`) come from the **eval fixture**, not from real
   usage. Real dictation in the log is overwhelmingly prose that genuinely needs
   the polish pass.
2. The observed pain is **latency and configuration**, not wasted polish. A
   decision call cannot fix a 30 s timeout; a timeout change can.
3. The polish-latency figures this analysis rests on were produced by the *eval*
   model, so they must be re-measured against the production provider before any
   of this is re-litigated.

What the model *is* good for here is **verifying the polished result** — a
post-hoc faithfulness check, measured at 0.985 vs 0.008 separation. That part is
worth prototyping.

---

## Motivation

Polish is the most expensive stage of the pipeline per segment, it is applied
unconditionally, and the overlay makes the wait visible (`showPolishing`). If a
cheap decision could skip it for segments that do not need it, segments would
land faster and the pipeline would call the LLM less often.

---

## Evidence

### 1. Latency: polish dominates the pipeline

From `~/Library/Caches/DoubleTapTalk.log` (2026-10-02 → 10-03, real dictation;
log timestamps are whole seconds):

| Stage | n | p50 | p90 | max |
|---|---|---|---|---|
| Apple finalize | 13 | 25 ms | 510 ms | 510 ms |
| cloud ASR | 31 | ≈1000 ms | ≈2000 ms | ≈3000 ms |
| **polish (LLM round-trip)** | **41** | **≈2000 ms** | **≈4000 ms** | **≈7200 ms** |

14 of 41 polish calls exceeded 2 s. 7 polish attempts failed outright and fell
back to the raw text (across all rotated log files), 3 of them the **30 s**
timeout (`LLM polishing failed: timeout. Using original text.`).

The worst real case in the log:

```
23:51:18  User content (polished): 'Speech to polish: 现在我正在测试这个AI修饰的功能，不知道行不行。'
23:51:48  LLM polishing failed: timeout. Using original text.
23:51:48  Injection target drifted — polished for kitty but frontmost is now Microsoft Edge Dev
23:51:48  Relay segment 1 injected in 30916ms (cloud 893ms · polish 30020ms · 24 chars)
```

A 24-character phrase took **30.9 s** to land, and landed in the wrong
application because the user changed windows during the wait.

> **Caveat that gates this whole RFC.** All 41 polish calls in that log went to
> `liquid/lfm-2.5-2.6b:free` via OpenRouter — that is the `RefinementPromptEvalTests`
> configuration, not necessarily the production one. The user's own dictation in
> the same log complains that the wrong provider was in use
> (「我明明配置的是 Arq，配的是河山方舟的模型，你怎么说我用的是 OpenRouter 啊？」).
> **Re-measure polish latency against the production provider first.** If
> production polish is p50 ≈ 600 ms, every remaining argument in this RFC
> evaporates.

### 2. What real dictation looks like

Unique real polish inputs in the log (the rest are eval fixtures — every request
in the log targets the eval model):

```
我现在就在用嘛，然后你可以看一下这个日志。就是我很想知道这个过程它是不是很流畅的…      (567 chars)
在最后一个段，呃，比方说我已经说了两段话了，然后说完两段话之后，我就…                (483)
还有个问题我特别关心，就是，呃，如果你，你用ASR的，你用你用苹果的本地去的那个…      (213)
比如说它的识别不是很精准，或者是说它它就是它它它识别本身有时间的…                  (153)
查看 日志 帮 我 看一下 昨天 的 报错                                            (spaced Chinese, unpunctuated)
这个 方案 的 风险 有点 高                                                       (same)
我重新配置了一下，ABS怎么不行？我换了一下，看一看会不会有好的效果。                    (99, the only already-clean one)
```

**Roughly 6 of 7 need polish** — filler words (呃 / 嘛 / 啊啊 / 你用你用) and
Apple's space-separated, unpunctuated Chinese output. The "obviously skippable"
inputs are the eval set (`um so like we should probably ship it tomorrow right`,
`um can you please run the unit tests with npm test`, `now run the build again`,
`buy one hundred tesla shares at market price`, …).

### 3. The model answers the question, but the framing decides the answer

Probe — decision model over `{target app, Apple transcript}`, 2 questions
(`noul` "Apple result is good enough" + `choice` `skip|light|rewrite`), 3 repeats
each, all deterministic:

```
Terminal  "git commit am fix the relay segment ordering bug"   cloud_use_p=0.67  polish=skip
Terminal  "帮我看一下 现在这个分支上还有什么没提交的改动"           cloud_use_p=0.91  polish=light
VS Code   "func process raw text settings LLM settings …"      cloud_use_p=0.77  polish=skip
VS Code   "这个函数需要加一个超时 不然网络断了会一直卡住"            cloud_use_p=0.91  polish=light
Slack     "好的 我马上发给你"                                    cloud_use_p=0.94  polish=light
Gmail     "我们看了一下这个季度的数据 想约个时间对齐一下下一步的计划"   cloud_use_p=0.94  polish=light
Spotlight "bocha jev api documentation"                        cloud_use_p=0.41  polish=skip
```

`skip` fires exactly where skipping makes sense — and exactly where the inputs
are eval fixtures. Meanwhile instruction phrasing moved the same string from
`use_cloud 0.78` to `keep_apple 0.67` between two probe versions, and the model
wanted to send a Spotlight keyword query to cloud ASR while keeping a mangled
terminal command local. Questions are scored independently, so a policy like
"code ⇒ skip polish" has to be restated inside every question's `instructions`.

### 4. Gating cloud ASR is worse

Even setting aside serialization, the Apple transcript is only available at
rotation time — the same moment the cloud call starts — so a gate can only run
before it, adding ~0.3 s to a p50 ≈1.0 s operation (+40 %) to skip it on some
segments. Cloud ASR *replaced* the Apple text in 89 of 119 real segments (≈75 %).
Additionally, the segments that most need cloud ASR look the *least* suspicious
textually (`Can Sharma` → real Chinese sentence), so a text-only gate is
mis-calibrated in the wrong direction.

### 5. What the model is genuinely good at here: verification

Probe — `noul` on `<raw transcript> → <polished text>`: "does the polished text
preserve every fact, number, name and intent?"

```
faithful (会议改到周三下午3点，地点仍为三号会议室)  → 0.985 / 0.949
mangled  (改成周四上午10点，改为线上)                → 0.008 / 0.016
added    (git commit -m "…" — a legitimate terminal edit) → 0.193
```

~240 tokens, 260–430 ms, clean separation. The pipeline currently has **no**
verification that polish preserved the text, and the log has 7 failed polish
attempts plus at least one silent no-op (24 chars in → 24 chars out after 30 s).

---

## Recommendation

### Do first (no decision model involved)

1. **Cut the polish timeout.** `LLMSettings.timeout` allows 30 s while p50 is 2 s
   and max observed 7.2 s. A ~5 s budget converts the 30.9 s case into a ~5 s
   case and removes the window in which injection target drift happens.
2. **Fix the provider configuration.** The log shows polish going to OpenRouter's
   free model regardless of the configured provider. Confirm which endpoint and
   model production actually uses, then re-measure.
3. **Detect the no-op for free.** `polished == rawText` (normalized) needs no
   model: skip the ✨ reveal and treat it as unchanged.
4. **Use the existing deterministic profile rule for the easy skips.**
   `PolishProfile.detect(from:)` already knows terminal/code/chat from the target
   app. A conservative "never polish single-token or obvious shell commands in a
   `.terminal` profile" rule captures most of the value at zero latency.

### Then, only if still worth it — the gate in this shape

- **Race, never serialize.** Issue the decision and the polish request together
  on the post-cloud text; act only on an early, confident verdict. If polish
  returns first, insert. This makes the added wall-clock cost zero on ordinary
  segments — which is the only way a gate can ever pay for itself here.
- **Skip-only, never rewrite-routing** in the first iteration. Routing to a
  different profile entangles the decision with the load-bearing prompt structure
  documented in `docs/PROMPT_FIXES.md`.
- **Conservative threshold, fail-open to polish.** The asymmetry is stark: a
  wrong "polish" costs p50 2 s; a wrong "skip" inserts filler-laden or
  unpunctuated text into the user's document with no automatic recovery. Set the
  bar so false skips are rare, and prefer `keep`/`light` over `skip` when
  uncertain (the instruction must say so explicitly).
- Own ~600 ms deadline; never inherit `LLMSettings.timeout`.
- Gate behind a setting, default **off**, and add `decision_ms` + `polish_skipped`
  to the existing `injected in Nms (cloud … · polish …)` log line so the effect is
  measurable before it is enabled by default.

### Approved for prototyping: the faithfulness check

Run the `noul` verification on `(raw, polished)` **after** polish, in parallel
with the reveal delay. It may only *flag*:

- below threshold ⇒ keep the polished text but mark the segment in the HUD, and
  log `Polish verification: noul=<p> (raw kept, <n> chars)` so the failure is
  visible in the field instead of silent;
- optionally fall back to `rawText` when the score is near zero and the segment
  is long — but never insert anything new, and never a second polish pass
  (AGENTS.md: one polish site, one insertion site).

---

## Rejected / deferred alternatives

| Option | Why not |
|---|---|
| Serial `skip?` gate before polish | +0.3 s on ~100 % of segments to save p50 2 s on a minority; strictly worse median |
| Gate cloud ASR with the model | +40 % on a p50 1 s step to save it on some segments; wrong calibration direction (suspicious-looking text is the text that needs cloud) |
| Replace the profile rule with a model router | 8 profiles already routed deterministically from the bundle ID; the model's marginal gain is intent *within* an app, which the eval does not yet measure |
| Use the polish prompt itself to decide ("output `<<SKIP>>`") | Zero added latency and no new dependency, but couples a control-flow decision to a prompt whose exact shape is measured and load-bearing; revisit only if the separate call proves too slow |

## Open questions

1. Production polish latency/quality with the intended provider — everything above
   depends on it.
2. What is the real skip rate on the user's own dictation (not the eval set)? If
   it is under ~20 %, the gate cannot justify a new remote dependency.
3. Does `light` vs `skip` even matter to the user, or is the useful axis just
   "insert raw" vs "polish"?
4. Should the verification result ever *replace* the polished text automatically,
   or only warn?

## References

- [JEV_INTEGRATION.md](JEV_INTEGRATION.md) — API contract, budget, placement rules, eval harness
- [RFC-001-abandon-segment.md](RFC-001-abandon-segment.md) — spoken abandon (recommended)
- [PROMPT_FIXES.md](PROMPT_FIXES.md) — why the polish prompts may not be casually restructured
- `Sources/DoubleTapTalk/Services/PolishProcessor.swift` — the single polish site
- `Sources/DoubleTapTalk/Models/PolishModels.swift` — profiles and `buildPrompt`
- `Tests/VoiceKeyTests/RefinementPromptEvalTests.swift` — the eval pattern to copy