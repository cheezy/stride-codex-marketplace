---
name: oracles
description: Use when you have observed a result during exploration and need to decide whether it is a defect, a known-bad-but-expected behavior, or acceptable. This skill supplies oracle strategies — Never/Always rules, alternative-resource consistency checks, and approximations for when the exact right answer is unknowable — plus the HTSM quality-criteria checklist for deriving Never/Always statements. Invoked by the exploratory-testing orchestrator, the explorer subagent, and the stride-exploratory-testing-explore command-skill whenever a probe produces a result that must be judged.
skills_version: "1.0"
---

# oracles

## STOP — orchestrator check

This is an internal doctrine skill, dispatched by the orchestrator. If you arrived here directly from a user prompt, activate the `stride-exploratory-testing` orchestrator skill first — it teaches the mental model and routes the request here with the right framing. Do not proceed from a cold user prompt; the orchestrator is the front door, this skill is not.

An **oracle** is a heuristic for recognizing a problem when you see one. Exploration constantly produces results no one pre-answered — "the report shows 47, is that right?" — and every such result needs an oracle to judge it. Oracles are **fallible**: they suggest that something is *worth questioning*, not that it is provably wrong. A spec is one oracle among many; this skill supplies the others, for the (frequent) case where no spec settles the question.

## The judgment this skill supports

For each observed result, classify it:

- **Defect** — it violates a Never/Always rule or a consistency oracle, with no justification. Report it.
- **Known-bad-but-expected** — it violates an oracle but is a *documented* limitation, an accepted trade-off, or an already-tracked issue. Note it and move on; don't re-report noise.
- **Acceptable** — it holds against every oracle you applied. Keep exploring.

When two oracles disagree (the product matches its spec but violates user expectations), that *conflict* is itself a finding worth raising — often the spec is wrong.

## Never / Always rules

The fastest oracle is an **invariant**: something the system should *never* do, or *always* do. Violations are strong bug signals because they need no reference to compute.

- *Never* lose committed data. *Never* charge a card twice for one action. *Never* expose one tenant's data to another.
- *Always* leave the user a next step. *Always* report an error in terms the user can act on. *Always* return to a consistent state after an interruption.

State the Never/Always for the target before you explore it; then every probe is also a check of those invariants. The quality-criteria checklist below is how you *generate* Never/Always statements systematically.

## Alternative resources (consistency oracles)

When there's no invariant to check, judge the result by **consistency with something else**. Ask "is this result consistent with…":

| Resource | The result should be consistent with… |
|---|---|
| **Internal consistency** | itself and the rest of the product — same term, same format, same rules everywhere. |
| **History** | how the product behaved before — an unexplained change from prior behavior is suspicious. |
| **Comparable products** | how similar features or competing products solve the same problem. |
| **Standards & references** | specs, RFCs, style guides, regulations, and domain references that apply. |
| **Claims** | what the docs, UI copy, marketing, and stakeholders say it does. |
| **User expectations** | what a reasonable user would expect — the "principle of least astonishment". |
| **Purpose** | the product's intended use — a result that defeats the point is a problem even if "correct". |

No single resource is authoritative; the more of them a result violates, the more confident the bug.

## Approximations — when the exact right answer is unknowable

Sometimes you cannot compute the one correct answer (complex domain logic, non-deterministic output, floating point, generated content). Judge it *approximately*:

- **Evaluate against a range** — the answer may be unknown, but its *bounds* are known. A tax can't be negative or exceed the total; a percentage sits in [0, 100]; a duration is positive. Flag anything outside the plausible range. *(Use this for complex-domain output whose exact value you can't recompute.)*
- **Evaluate characteristics** — don't check the exact value; check *properties* that must hold. A sort is monotonic; a shuffle preserves the multiset; shares sum to 100%; a round-trip preserves length. *(Use this for non-deterministic output — the value varies run to run, but the properties don't.)*
- **Invert the result** — reverse the operation and check you recover the input. Encode→decode, export→import, create→read, zip→unzip should round-trip to the original.
- **Select extreme conditions** — choose inputs where the correct answer *is* knowable: the empty case, the identity element, a single item, the maximum. The general answer may be opaque, but the extremes are checkable.

## Adapter Is Not the Wire

A result you observed **only through an in-process test adapter** — a test connection, a mock transport, any helper that calls the app without a real socket — does not establish **wire behaviour**. The adapter hands you the response the app built, whole; it cannot see what a real server sends, or fails to send, after the status and headers go out. So for four kinds of behaviour an adapter-only result is a *claim*, not an observation:

- **streamed or chunked responses** — what the client receives when the source fails mid-stream;
- **`HEAD` requests** — whether the server answers with headers and no body;
- **connection aborts** — what happens when either side drops the connection part-way;
- **`Content-Length`** — whether the length the server declares matches the bytes it sends.

Confirm the claim on a real server — the authorized non-production target and listed hosts you were given; this oracle grants no new reach, and it never needs one. When you cannot confirm it, record the wire claim under **`debrief.unknown`, never under `found`**, and raise no bug on it. The oracle does not fire on a charter whose responses are none of the four: an ordinary buffered response observed through an adapter is judged by the other oracles as usual.

*Example:* a download endpoint passes its test through the adapter — `200`, full body. On a real server the body is streamed after the `200` is committed, so a source that fails part-way leaves the client a `200` with an empty or short body that looks complete. The adapter's pass says nothing about that window. Fetch it with `curl -q -sS -i` through `shell` against the running app (on a listed host, never following a redirect), or record "streamed download not observed on the wire" under `debrief.unknown`. The **After the Headers** lens in the `heuristics` skill designs the probe; this oracle judges what it shows.

## Two Decision Sites

When the **client and the server each decide the same thing** — whether an action is allowed, how much room is left, what type a file is, what state a plan is in — both sites must **agree in every state**. A disagreement is a finding whichever side is right: the user is offered what the server refuses, or refused what the server would accept.

- List the states that change the decision — signed out, one under the limit, at it, over it, the plan changed in another session, a page left open while the server's state moved — and check both sites in each.
- A client control that matches the server in every state you tried is **Acceptable**. One state where they differ is a **Defect**; the server's answer is the truth the client must follow.

*Example:* an upload button stays enabled at "9 of 10 files" after another session filled the tenth slot, and the server rejects the upload with a generic error; or the button accepts a file type the server refuses. Each is two decision sites disagreeing. The **Shadow Decision** lens in the `heuristics` skill designs the probe; this oracle judges what it shows.

## Quality-criteria checklist → Never/Always

To surface Never/Always rules systematically, walk the **quality criteria** (the "-ilities" from the Heuristic Test Strategy Model). For each, ask "what must this feature *never* do, and *always* do?"

| Criterion | Prompt | Example Never/Always |
|---|---|---|
| **Capability** | Does it do what it claims, completely? | *Never* silently drop a requested operation; *always* do what the button says. |
| **Reliability** | Does it hold up over time, load, and failure? | *Never* lose committed data on a crash; *always* recover to a consistent state after an interruption. |
| **Usability** | Can a real user succeed without surprise? | *Never* leave the user stuck with no next step; *always* phrase errors in terms the user can act on. |
| **Scalability** | Does it hold as volume grows? | *Never* degrade to failure within the expected growth range; *always* bound resource use. |
| **Security** | Does it protect data and access? | *Never* store secrets in cleartext; *always* enforce authorization on every access, server-side. |
| **Performance** | Is it responsive enough? | *Never* block the UI on a long operation with no feedback; *always* respond within the stated budget. |
| **Accessibility** | Can everyone use it? | *Never* convey meaning by color alone; *always* expose controls and state to assistive technology. |

Sweep these criteria over the target and you get a Never/Always set that turns vague "does this seem OK?" into concrete, checkable invariants.

## Safety of oracle examples

Security-flavored Never/Always examples (e.g. "never store secrets in cleartext") are illustrative — they **must not embed real secrets, tokens, or credentials**; use placeholders. And oracle evaluation is about judging results from **a system you are authorized to test** — this guidance never encourages probing or comparing against systems the user has no permission to test. Confirming wire behaviour on a real server is a probe like any other: it reaches only the authorized non-production target and its listed hosts, and *Adapter Is Not the Wire* grants no new reach.

## Handing off

The `chartering` skill sets the mission and the `heuristics` skill generates the probes; this skill judges what those probes reveal. Known-bad-but-expected observations are recorded but not re-reported.

A finding you classify as a **Defect** does not go straight into the report. Hand it to the **`bug-advocacy`** skill first: it owns the work between "an oracle says this is wrong" and "a stakeholder can act on this" — Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly, plus the severity rubric that makes ratings comparable across sessions. From there the write-up flows into the session notes and debrief (the `session` skill).
