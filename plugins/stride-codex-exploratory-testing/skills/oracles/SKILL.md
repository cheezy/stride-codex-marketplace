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

Security-flavored Never/Always examples (e.g. "never store secrets in cleartext") are illustrative — they **must not embed real secrets, tokens, or credentials**; use placeholders. And oracle evaluation is about judging results from **a system you are authorized to test** — this guidance never encourages probing or comparing against systems the user has no permission to test.

## Handing off

The `chartering` skill sets the mission and the `heuristics` skill generates the probes; this skill judges what those probes reveal. Findings you classify as defects flow into the session notes and debrief (the `session` skill); known-bad-but-expected observations are recorded but not re-reported.
