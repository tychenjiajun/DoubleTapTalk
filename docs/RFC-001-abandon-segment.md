# RFC-001 — Spoken Abandon: dropping a relay segment on request

**Status:** Proposed (Phase 1 ready to implement, Phase 2 unresolved)
**Date:** 2026-10-03
**Decision model:** `bocha-jev-v1` (see [JEV_INTEGRATION.md](JEV_INTEGRATION.md))
**Related:** [RFC-002](RFC-002-polish-decision.md) (decision model for polishing)

---

## Summary

While dictating continuously, the user sometimes loses their train of thought
mid-passage. Today the only way out is to stop talking and press Backspace
(`Relay: stopping via Backspace — discarding active segment` — already
implemented), which breaks the flow.

This RFC proposes letting the user **say** the abandonment instead: the segment
that contains an explicit instruction like 「这段不要了」 / 「刚才那段作废」 /
`scratch that` is not inserted, and the overlay acknowledges the discard.

The decision is an *intent classification over the user's own words*, not a
quality judgement about the transcript. That distinction is what makes it
work (see [Rejected alternatives](#rejected-alternatives)).

---

## Motivation

The user's own framing:

> 我在说很长的一大段话的时候，可能我中间有一段脑子短路了，然后我就说这段我要放弃掉，
> 然后我再继续说下面的一段话。在这个场景下，做一个决策的模型去做一个段落的放弃，
> 可能会有是有价值的。

Requirements implied by that sentence:

1. **Hands-free** — no keypress, no stopping the session.
2. **Always available** mid-passage, not just at session end.
3. **No interruption** of the recording, and ideally no visible cost when it
   does not fire (most segments will not be abandonments).

---

## Evidence

### Pipeline timings (the budget this has to fit into)

From `~/Library/Caches/DoubleTapTalk.log`, 2026-10-02 → 10-03, real dictation
only. Log timestamps are whole seconds, so stage figures are ±1 s.

| Stage | Log source | Measured |
|---|---|---|
| idle rotation threshold | `Relay: no new words for Ns` | **2.0 s** (108/110 rotations) |
| Apple segment finalize | `Relay segment result: … finalize Nms` (n=13) | p50 **25 ms**, p90 510 ms |
| cloud ASR | `Cloud transcription request →` … `✓ Cloud transcription:` (n=31) | p50 **≈1000 ms**, max ≈3000 ms |
| polish (LLM round-trip) | `LLM request →` … `LLM response ←` (n=41) | p50 **≈2000 ms**, p90 ≈4000 ms, max ≈7200 ms |
| rotation → insertion | `rotating segment` → `Relay segment injecting:` (n=21) | p50 **≈1000 ms**, max ≈3000 ms |

Segment outcomes in the same window: 89 used cloud ASR, 30 fell back to Apple
(`cloud unavailable`), 47 skipped for having no recognized words.

### The decision model is fast enough

`bocha-jev-v1`, one `noul` question on the finished segment text, 3 repeats each:
**246–425 ms**, ~230 input tokens, byte-identical across repeats (deterministic —
the API rejects `temperature`, `422 extra_forbidden`).

At 246–425 ms the verdict lands *before* the polish call returns (p50 2 s), so
when the decision is run concurrently with polish it adds **zero** wall-clock
time to a segment.

### Classification accuracy

Probe A — **whole segment as `state`**, one `noul` question (recommended shape):

```
POS  我们先把缓存层改一下 用 LRU 大概一千条 呃 算了这一段不要了        → 0.97
POS  然后那个接口回调的时候要加一个超时 不对 这段作废 我重说            → 0.991
POS  I think we should split the service into two parts scratch that…  → 0.922
POS  就是那个 你帮我把那个 呃… 算了上面说的都别记 我重新讲              → 0.962
NEG  刚才那个功能不要了 改成异步的                                      → 0.101
NEG  这段很重要 千万不要删                                              → 0.011
NEG  算了 就这样吧 我们继续下一件事                                      → 0.031
NEG  缓存那句注释删掉 换成英文的                                        → 0.007
NEG  这个 bug 不要了 我们关掉这个 issue                                  → 0.077
NEG  这里不要再重试了 直接抛异常                                        → 0.016
```

**10/10, deterministic**, and the two classes separate widely (0.92–0.99 vs
0.007–0.10). The dangerous reading — real content that merely *contains*
"不要了 / 删掉" — is rejected in every case.

Probe B — **the bare phrase alone**, with a 3-way `choice`
(`keep` / `discard_current` / `discard_prev`): **8/11**, with one harmful miss:

```
MISS  「刚才那个功能不要了 改成异步的」 → discard_prev @ 0.71   (real content, would be deleted)
MISS  「这段不要了 我重新说」           → discard_prev @ 0.77   (right action, wrong segment)
MISS  「这个不算 我重说一遍」           → discard_prev @ 0.69   (right action, wrong segment)
```

The same input scored **0.101** in Probe A. The lesson is the design constraint
below: *the decision must see the whole segment, and the abandoning phrase must
land inside the segment it abandons.*

---

## Proposal

### Phase 1 (recommended, self-contained)

Detect abandonment **within the segment that carries it**, and drop that whole
segment before insertion. No retraction, no new destructive primitive.

This works precisely when the user does **not** pause before saying it — the
abandoning sentence stays in the same 2 s idle window as the content it
abandons, so the segment text handed to the model is
`<abandoned content> … <abandon instruction>`.

Design in one line: *the segment that contains an explicit abandon instruction is
never inserted.*

### Phase 2 (optional, higher risk)

Handle "paused, saw it land, then said 算了" by retracting the **immediately
preceding** segment. This requires a safe delete primitive, which the codebase
does not have today. See [Retraction](#phase-2-retraction-rules) for the rules;
if they cannot all be met, **do not ship Phase 2**.

---

## Design

### Where it sits in the pipeline

`AppDelegate.insertRelaySegment(_:generation:)` (and `finishRelay` →
`finalize`) is the only insertion path, and `PolishProcessor.process` is the only
polish site — this must not add a second one of either (AGENTS.md).

```
ContinuousDictationSession rotates (2.0 s idle)
  → AppDelegate.enqueueRelaySegment            (OrderedTaskChain, generation-guarded)
      → cloud ASR (if enabled)                 ~1 s
      → ┌─ PolishProcessor.process             p50 2 s   ← existing, untouched
        └─ DecisionModel.abandonVerdict(text)  ~0.3 s   ← NEW, concurrent, advisory
      → if verdict = abandon: drop segment, noteSegmentAbandoned(), return
      → else: inject()                          ← unchanged behaviour
```

Two hard rules:

1. **Never serialize the decision in front of polish.** Issue both requests on
   the post-cloud text and let them race. A serialized +0.3 s would make every
   ordinary segment slower to buy a rare feature. If the verdict has not arrived
   when polish returns, proceed with insertion (the decision is advisory).
2. **Fail open.** No key, no network, timeout, non-2xx, unparseable, or a
   probability below the threshold ⇒ insert as today. The decision may only ever
   turn an insertion into a discard when it is *confident*, never the reverse.

### Decision contract

One `noul` question over the finished segment text. Threshold **0.5** (the
observed gap is 0.10 vs 0.92, so the threshold has wide headroom; keep it
configurable but do not tune it below 0.5).

```json
{
  "model": "bocha-jev-v1",
  "state": "终端里的编码助手对话输入框。这一段的最终转写结果：\n「<segment text>」\n（这一段已经口述完毕）",
  "questions": {
    "abandon": {
      "type": "noul",
      "instructions": "用户在连续口述，把这段口述文字插入到终端里的编码助手输入框。请判断：用户在说完内容之后，是否在结尾明确表示『刚才这段口述作废/不要了/重说』，也就是要求把这一段整体丢弃。注意：如果用户只是在自己的口述内容里讨论『删除、不要、去掉』某个功能、代码、需求或 issue，那属于正常内容，答案为 false。只有在用户明确指示放弃这段口述本身时才为 true。",
      "criteria": {
        "true":  {"description": "明确指示放弃这段口述（整段丢弃、重说、作废）"},
        "false": {"description": "正常口述内容，即使里面提到了不要/删除/算了"}
      }
    }
  }
}
```

Notes on the rubric (measured, not stylistic — see JEV_INTEGRATION.md):

- The instruction **must** name the embedding app context and the
  "content that merely mentions 删除/不要" counter-case. Removing either clause
  reintroduces Probe B's false positive.
- `noul` returns a **probability of true as a JSON number**, not a bool.
- Do not add a second "which segment" question: with Phase 1's framing the answer
  is always *this* segment, and asking made the model worse (Probe B).

### Abandoned segments must not enter the polish context

`insertRelaySegment` currently calls `appendSegmentHistory(text)` right before
injecting, and `previousSegments` is fed into the next segment's polish prompt.
An abandoned segment therefore **must not** be appended — otherwise the text the
user just threw away resurfaces as context and drags later segments toward it.

This is the subtlest requirement in this RFC and is worth a unit test.

### Overlay acknowledgement

The user has to be able to tell that the discard was understood, or they will
stop, repeat themselves, or reach for Backspace — which is exactly the
interruption the feature exists to remove.

Follow the existing stage-API rule (never push raw strings from the
AppDelegate): add `noteSegmentAbandoned()` to `RelaySessionLedger` (alongside
`noteSkipped()` / `noteFailed()`), surface it through `RecordingOverlayPanel`,
and add copy to `OverlaySessionCopy` for **both** languages. Do not reuse
`noteSegmentSkipped()` — "no words recognized" and "you told me to drop this"
are different facts and the session summary distinguishes them.

### Phase 2: retraction rules

Only if all of these hold, otherwise report 「上一段已保留」 and stop:

1. Same target application as the insertion, verified at retraction time (the
   `expectedTarget` drift check in `inject(_:expectedTarget:)` already models
   this — the log contains a real drift case where polish took 30 s and the text
   landed in Microsoft Edge Dev instead of kitty).
2. The focused element's current value still **ends with** exactly the text we
   inserted — readable via `AccessibilityService.captureFocusedElementInfo().value`.
   If it does not, the cursor moved or something else was typed: do not delete.
3. Only the immediately preceding segment, never further back.
4. Never retract into a terminal that is streaming output from another process
   (kitty running a coding agent is the log's actual target). Deletion there can
   destroy the agent's output or feed text into the shell.

Keep the recording WAV (when cloud ASR + recordings are enabled) so a discarded
segment remains recoverable from disk, and log the full dropped text once
(`Abandoned segment (dropped, <n> chars): …`) — it is the only record left.

---

## Failure modes

| Failure | Effect | Mitigation |
|---|---|---|
| False positive on real content | **Silent loss of the user's words** — the worst outcome in this app | Wide-margin threshold; accuracy is 10/10 on the probe; fail-open; instruction clause about content that mentions deletion |
| Verdict arrives after insertion | Insertion happens as usual, feature misses | Phase 1 only fires when the phrase is in the same segment; accept the miss, never auto-retract |
| Model unreachable | No behaviour change | Own ~600 ms deadline, fail-open, do not inherit `LLMSettings.timeout` (30 s) |
| Decision added to the ordered chain tail | Burst of segments gets slower | Race, never serialize; the chain already serializes cloud ASR + polish |
| Abandoned text leaks into `previousSegments` | Later segments drift toward discarded content | Skip `appendSegmentHistory` for abandoned segments (+ unit test) |
| User must remember "say it in the same breath" | Feature silently does not work | HUD hint on first use; document it in Settings/README |

---

## Testing

- **Offline eval harness** (mirrors `RefinementPromptEvalTests`): the 10 probe
  cases plus the real phrasings the user actually uses, skipped unless
  `BOCHA_JEV_API_KEY` is set. Assert `noul` is a number in [0,1] (not a bool),
  assert the separation between the positive and negative groups, and assert
  *stability* across 2–3 repeats — the model is deterministic, so an unstable
  answer is a prompt bug.
- **Unit:** abandoned segment is not appended to history; abandoned segment is
  not injected; verdict below threshold inserts unchanged; timeout inserts
  unchanged; `RelaySessionLedger` counts an abandoned segment separately from
  skipped/failed.
- **Round-trip log test** (as with `LLMRoundTripLogTests`): the request line is
  emitted *before* the call with endpoint/model/timeout, and a timeout still
  logs `← … after Nms: timeout`.

---

## Rejected alternatives

- **Judge whether the transcript is "garbage" and abort.** Refuted by the log.
  Every segment that looked like noise was real speech rescued by cloud ASR:
  `Can Sharma` → 「你可以看一下吗？就是如果要，呃，修饰一段的话，它大概需要多长的时间？」;
  `Can can` → 「看看日志。」; `Since I was so calm` → 「现在我试一试看。」;
  `Play last commit` → `Lay last commit.`. 5/5 checked. A plausibility gate would
  have deleted the user's words in every one of them, and the discriminator
  (audio energy, language vs. script) is local and free — text-only, mumbling and
  real-but-mangled speech are identical.
- **Local silence/energy gate.** Already handled: 47 empty-text segments were
  dropped for free, and `peak 0.01–0.03` cases never got text. The class this RFC
  targets (`peak 0.08–0.34` with real words) is not separable by energy.
- **Reuse the polish prompt for the abandon decision.** Tempting (zero extra
  latency, no new dependency) but it entangles a destructive action with a
  prompt whose structure is load-bearing and measured (see
  `docs/PROMPT_FIXES.md`), and it would only work when polishing is enabled.
- **A canonical keyword instead of a model.** Cheaper and 100 % precise; keep it
  as the fallback contract, but it does not cover the natural phrasings the user
  will actually produce.

## Open questions

1. Does the user's real phrasing match the probe? (Re-run the harness with real
   utterances before shipping.)
2. Should the abandoned segment be recoverable in-app (a "recently discarded"
   list) or is the WAV on disk enough?
3. Phase 2 at all? The retraction primitive is the expensive part; the
   same-breath protocol removes the need for it.
4. Should the decision also run on the *final* segment of a session? Dropping
   there is the same action, but it is also where the user's last words live.

## References

- [JEV_INTEGRATION.md](JEV_INTEGRATION.md) — how to call the decision model, budget, logging, secrets, eval harness
- [RFC-002-polish-decision.md](RFC-002-polish-decision.md) — polish gate (deferred) and the faithfulness check
- `Sources/DoubleTapTalk/App/DoubleTapTalkApp.swift` — `enqueueRelaySegment`, `insertRelaySegment`, `finalize`, `inject(_:expectedTarget:)`
- `Sources/DoubleTapTalk/Services/PolishProcessor.swift`, `Services/OrderedTaskChain.swift`, `Services/AccessibilityService.swift`
- `Sources/DoubleTapTalk/Views/Overlay/OverlaySession.swift`, `Views/Overlay/OverlayState.swift`