# PostHog Self-driving setup — Crux iOS

PostHog Self-driving is now configured for Crux. Signal sources, a 7-scout troop (including two custom scouts built for this app), and two Replay Vision monitors are all live. Findings will start appearing in the [Self-driving inbox](https://us.posthog.com/project/568368/inbox) within ~30 minutes.

---

## AI data processing

**Approved.** Organisation-level AI data processing consent was confirmed before the run started.

---

## GitHub

**Connected during this run.** Integration ID 236415, account `21andrewchang`. Self-driving can now research findings in the repo and open fix PRs.

---

## Products enabled

| Product | Status | Notes |
|---|---|---|
| Session Replay | Enabled (inert) | `products-enable` tool unavailable; server flip recorded. iOS native app — replay requires `PostHogSessionReplayConfig()` in `PostHogConfig` (see follow-ups). |
| Error Tracking | Enabled (inert) | Same — iOS native app requires `config.captureExceptions = true` in `ClimbApp.swift` (see follow-ups). |
| Support / Conversations | Enabled (inert) | Enabled by default. Tickets arrive once an inbound channel (email / inbox / Slack) is connected in PostHog. |

> **Support follow-up:** connect an inbound channel in PostHog → Settings → Conversations to start receiving support tickets.
> **Note:** "Enabled (inert)" means the server toggle is on; the SDK still needs the config changes listed in follow-ups before any data is captured.

---

## Signal sources

| Source product | Source type | Action |
|---|---|---|
| `health_checks` | `health_issue` | **Enabled** (ID: 01a020fc-1585-77d7-bd09-0609a4440d75) |
| `error_tracking` | `issue_created` | **Enabled** (ID: 01a020fc-1bb4-7b1e-9d06-629c29c080b7) |
| `error_tracking` | `issue_reopened` | **Enabled** (ID: 01a020fc-1e5f-766a-b314-81736e39ca83) |
| `error_tracking` | `issue_spiking` | **Enabled** (ID: 01a020fc-20f2-7df1-b01b-4d361978313f) |
| `session_replay` | `session_analysis_cluster` | **Enabled** (ID: 01a020fc-2614-7286-b7d3-8206497ccbc6) |
| `conversations` | `ticket` | **Enabled** (ID: 01a020fc-2746-761e-a5d2-1b47d7a8a47e) |
| `signals_scout` | `cross_source_issue` | **On by default** — no row needed |
| `replay_vision` | — | **Self-authorizing** — the `emits_signals` flag on each scanner is the config; no row created |

---

## Connected tools

No external tools selected. All issue-tracker, error-tracker, support, and review tools are **not used** for this project.

---

## Scout troop

**Budget:** 100 runs/day (early access default). 0 runs used today. Banner: *"Scouts are in early access. Each project gets up to 100 scout runs a day. Contact team-self-driving@posthog.com if you need more."*

### Enabled scouts (7 total)

| Scout | What it watches |
|---|---|
| `signals-scout-general` | Cross-product correlations and surfaces no specialist covers |
| `signals-scout-product-analytics` | Saved funnel/retention/lifecycle flows for conversion rate regressions |
| `signals-scout-revenue-analytics` | Revenue pipeline for capture regressions and goal misses |
| `signals-scout-health-checks` | PostHog instrumentation health — missing events, SDK gaps |
| `signals-scout-anomaly-detection` | Dashboard and insight anomalies (bursts, drops, flat-lines) |
| `signals-scout-onboarding-funnel` *(custom)* | `onboarding_phase_changed` / `onboarding_completed` for completion-rate regressions |
| `signals-scout-paywall-conversion` *(custom)* | `paywall_viewed` → `subscription_purchased` conversion rate |

### Disabled scouts (22 total)

All remaining scouts are disabled. Notable re-enable candidates when you add those surfaces:

| Scout | Why disabled |
|---|---|
| `signals-scout-error-tracking` | **Covered by native source** — error tracking runs as a source, not a scout |
| `signals-scout-session-replay` | **Covered by native source** — replay analysis runs as a source |
| `signals-scout-feature-flags` | No feature flags found in the codebase |
| `signals-scout-experiments` | No A/B experiments configured |
| `signals-scout-surveys` | No surveys in use |
| `signals-scout-ai-observability` | No AI/LLM events (`$ai_*`) found |
| `signals-scout-web-analytics` | Native iOS app — no web traffic |
| `signals-scout-logs` | PostHog logs product not in use |
| All others | Not among the most-used product surfaces for this project |

**Noise escape hatch:** if any enabled scout becomes noisy, set `emit: false` on its config in PostHog → Self-driving → Scouts to put it into dry-run mode (it still runs and logs, but writes nothing to the inbox).

---

## Custom scouts

### `signals-scout-onboarding-funnel`

- **Watches:** `onboarding_phase_changed` (from/to: quiz → loading → profile → paywall → done) and `onboarding_completed`
- **Discriminator:** ratio of `onboarding_completed` to users entering the quiz phase, over a 7-day rolling window. A ≥15% drop sustained 3+ consecutive days triggers a report. Secondary: which specific phase transition shows a disproportionate user drop.
- **Why no built-in covers it:** `signals-scout-product-analytics` watches saved funnel insights; this project has none yet. Once saved funnels exist, the built-in may overlap — disable this custom scout at that point.

### `signals-scout-paywall-conversion`

- **Watches:** `paywall_viewed` → `subscription_purchased` conversion rate; plan-level breakdown (yearly vs monthly) and trial take-up.
- **Discriminator:** purchase/view ratio over a 7-day rolling window. A ≥20% drop sustained 3+ consecutive days triggers a report. Secondary: shift in plan mix toward fewer yearly subscriptions.
- **Why no built-in covers it:** `signals-scout-revenue-analytics` focuses on Stripe sync regressions; this app's revenue surface is entirely StoreKit — a different pipeline with different failure modes.

### Surfaces ruled out

| Surface | Filter that eliminated it |
|---|---|
| Core session/climb/attempt loop | No events found for session creation or attempt logging — not watchable |
| Error patterns | Covered by the native error tracking source |
| Support tickets | No `$conversation_*` events — Conversations not yet wired up |
| Feature flags / experiments | None found in use |

---

## Replay Vision scanners

Replay Vision scanners are LLMs that watch individual session recordings on a schedule and push what they find into the Self-driving inbox. Each finding arrives at half-weight; two independent findings on the same recording are needed before a report is promoted. Scanners are the only part of this setup that spends Replay Vision quota.

This project has **no recordings yet** (iOS Session Replay requires SDK config changes — see follow-ups). Both scanners are armed and will start working the day recordings begin.

| Scanner | Type | What it watches | Query scope | Sampling | Est. monthly credits |
|---|---|---|---|---|---|
| **Crux session breakage** | monitor | Visible product failures: blank paywall, broken capture controls, silent purchase failures, spinners that never resolve | Mobile recordings (`snapshot_source = mobile`), 50% sample | 0.5 | 0 (no recordings yet) |
| **Crux climbing app frustration** | monitor | User frustration signals: rage-clicking paywall buttons, hammering camera controls, retrying stuck flows | Sessions with `$rageclick` events, 100% sample | 1.0 | 0 (no recordings yet) |

Both scanners have `emits_signals: true`.

---

## Follow-ups

- [ ] **Enable Session Replay on iOS** — add `config.sessionReplay = PostHogSessionReplayConfig()` to `PostHogConfig` in `Climb/ClimbApp.swift`. The server toggle is on; this is the missing SDK piece.
- [ ] **Enable Exception Capture on iOS** — add `config.captureExceptions = true` to `PostHogConfig` in `Climb/ClimbApp.swift`. Once enabled, crash and error data feeds the error tracking source.
- [ ] **Connect a Support inbound channel** — go to PostHog → Settings → Conversations and connect an email address, inbox, or Slack channel so support tickets start routing to the inbox.
- [ ] **Review Replay Vision scanner query** — once mobile recordings arrive, verify that `snapshot_source = mobile` correctly scopes the breakage monitor to iOS sessions. Adjust if needed.
- [ ] **Enable `signals-scout-feature-flags`** — when feature flags are added to the app, enable this scout from PostHog → Self-driving → Scouts.
- [ ] **Enable `signals-scout-experiments`** — when A/B experiments are launched, enable this scout.

---

## What happens next

The scout coordinator picks up fresh configs within ~30 minutes of setup. Each enabled scout runs once a day and draws from the project's daily budget (100 runs/day during early access). Findings cluster into reports in the [inbox](https://us.posthog.com/project/568368/inbox); immediately-actionable reports can kick off coding tasks automatically.
