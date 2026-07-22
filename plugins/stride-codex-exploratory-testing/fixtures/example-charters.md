# Example charter set

A worked charter set for a **fictional, synthetic target**: *ExpenseFlow*, a
multi-tenant expense-report web app where employees upload receipts (CSV + image),
managers approve reports, and finance exports approved data. Everything below is
invented — no real product, tenant, credential, or hostname appears. Placeholders
like `<tenant A>` and `demo.example.com` stand in for anything real.

This file demonstrates what the `chartering` skill and the
`stride-exploratory-testing-charter` skill produce. Each charter follows the
template:

> **Explore** `<target>`
> **with** `<resources>`
> **to discover** `<information>`

A good charter fits in a tweet, time-boxes to ≤ ~2 hours, names the *information*
you hope to learn (not just a target), and poses an **open question** — never a
single known expected result. If it has one expected result, it's a *check*: write
it as an automated test instead.

---

## Ranked charters

Ranked by risk × payoff. The top charter drove the
[example session sheet](example-session-sheet.md) and
[example debrief](example-debrief.md).

### 1. CSV receipt import — malformed and oversized files

> **Explore** the CSV receipt import
> **with** malformed, oversized, and wrong-encoding files (and files from another
> tenant's export)
> **to discover** how the parser fails, whether it corrupts existing receipts, and
> whether any row can leak across tenants.

- **Risk:** data corruption and cross-tenant leakage — the highest-stakes pair here.
- **SFDPOT lens:** Data, Structure. **Variables:** Format, Size, Files & storage.
- **Nightmare headline it defends against:** *"Expense App Imports One Tenant's
  Receipts Into Another's Books."*

### 2. Approval workflow — concurrent and out-of-order actions

> **Explore** the report approval workflow
> **with** two managers acting on the same report at once, and approve/recall/reject
> in unexpected orders
> **to discover** state-desync, double-approval, and stale-write problems.

- **Risk:** an approved-then-recalled report that still exports; money moves on a
  stale state.
- **SFDPOT lens:** Operations, Time. **Variables:** Timing, Sequence, Count.
- **Heuristic:** *Interrupt* — start an action, interrupt it, resume from a stale tab.

### 3. Date-range filter — boundary and reversed ranges

> **Explore** the report date-range filter
> **with** boundary dates, reversed ranges (end before start), and timezone edges
> **to discover** off-by-one errors, empty-result handling, and timezone drift in
> the totals.

- **Risk:** finance trusts a total that silently drops the last day of the month.
- **SFDPOT lens:** Data, Time. **Variables:** Position (boundaries), Geography/locale.
- **Heuristic:** *Goldilocks* (too early / just right / too late), *Reverse*.

### 4. Multi-tab session handling

> **Explore** multi-tab session handling
> **with** two browser tabs logged in as the same user, one left idle past the
> session timeout
> **to discover** stale-write, silent-logout, and CSRF-token-desync problems.

- **Risk:** a silent logout that discards a half-written report without warning.
- **SFDPOT lens:** Platform, Operations. **Variables:** Timing, Input method.
- **Web heuristic:** *Multiple Tabs / Windows*, *Cookies / Session*.

### 5. Receipt export — tenant isolation and format fidelity

> **Explore** the approved-expense export
> **with** large date ranges, special characters in vendor names, and rapid repeated
> exports
> **to discover** whether the export can include another tenant's rows, mangle
> Unicode, or double-count on retry.

- **Risk:** an export that leaks rows or double-bills on a retry click.
- **SFDPOT lens:** Data, Structure. **Variables:** Format, Count, Size.
- **Nightmare headline:** *"Finance Export Bills Customers Twice After a Double-Click."*

---

## From nightmare headline to charter

The `stride-exploratory-testing-nightmare-headline` skill starts from the worst
thing that could be written about a feature, then works backward to charters. A
worked example:

> **Nightmare headline:** *"ExpenseFlow Emails Every Tenant's Receipts to the Wrong
> Company."*

Brainstormed causes → charters:

- *A shared cache keyed only by report ID, not tenant.* →
  **Explore** the report-detail cache **with** rapid tenant-switching in one session
  **to discover** whether cached pages bleed across tenants.
- *An export job that queries by date without a tenant filter.* → covered by charter
  **#5** above.

---

## Anti-pattern: a "charter" that is really a test case

The most common charter-writing mistake is smuggling in a check — something with a
single known expected result. Spot it and reframe it into an open question.

| ❌ Not a charter (a check) | Why | ✅ Reframed as a charter |
|---|---|---|
| "Verify that uploading a 5 MB PDF receipt returns 200 and shows a success toast." | One known expected result — write it as an automated test. | **Explore** receipt upload **with** unusual sizes, types, and truncated files **to discover** how uploads fail and whether a partial upload corrupts the report. |
| "Confirm the login form rejects a blank password." | A test case with a known expected result — that's a check. | **Explore** the login form **with** boundary and malformed credentials **to discover** inconsistent validation and error messaging. |

If you can only write down what you *expect* to happen, you have a check. A charter
asks what you'd *learn* — "…to discover how X behaves under Y."
