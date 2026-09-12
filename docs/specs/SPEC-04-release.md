# SPEC-04 — Release gates

## Problem

This tool lives beside credential files and will carry a personal name in public. The bar is
higher than its size suggests. This spec is the checklist that blocks publication.

## In scope

Security review, test matrix, documentation set, repository layout, marketplace entries.

## Out of scope

The LinkedIn post — written after the repo is live and CI is green, and reviewed separately.

## Framing (applies to every public surface)

The honest description is **"switch between Claude accounts you already own, with graceful
failover."** Never "never hit rate limits" or "bypass limits". The tool does not share, pool or
resell accounts, and every account's own limits still apply in full. No language promising
unlimited usage in the README, marketplace entry, or post.

## Security gates

| # | Gate |
|---|---|
| S-1 | No code reads, copies, prints or transmits `.credentials.json`. Enforced by a test that greps for credential reads. |
| S-2 | No work or machine identifiers in the repo — by category, since listing the literals here would itself leak them: the author's work email addresses, any employer name, the development machine's home directory path, real session UUIDs, and real transcript samples. The exact patterns live only in `test/test-security.sh`, written split so the test file does not trip its own grep. All fixtures are synthetic. |
| S-3 | Published identity is `Marwan Maher <marwanmaher635@gmail.com>` in `plugin.json`, `marketplace.json` and `LICENSE` — the one address that is deliberately public. Repo-local `git config user.email` set to the same; **the global git config is left untouched**, since other repositories depend on it. Verified with `git log --format='%ae' \| sort -u` before the first push. |
| S-4 | No network calls and no telemetry anywhere in the tool. Stated in the README, enforced by a grep test. |
| S-5 | File modes asserted in code: config and state `600`, account dirs `700`. |
| S-6 | The logout trap carries a top-level README warning, since a fork could reintroduce it. |
| S-7 | Transcript copying is documented: what moves, where, and that it never leaves the machine. |
| S-8 | `npx @claude-flow/cli@3.5.79 security scan` run and triaged. |
| S-9 | `shellcheck` clean on every shell script, in CI. |

## Test matrix

`bats`, GitHub Actions, ubuntu-latest + macos-latest. Built on the stub-`claude`-on-PATH
harness, which costs no quota and already caught two real bugs.

| # | Test | Guards |
|---|---|---|
| T-1 | Migration generates config, maps numeric state keys, idempotent | SPEC-01 AC-1..3 |
| T-2 | **Default account launches with `CLAUDE_CONFIG_DIR` unset; others with it set** | SPEC-01 AC-7 |
| T-3 | Config validation rejects dup id, dup dir, two defaults, bad default dir, malformed file | SPEC-01 AC-4..6, AC-9 |
| T-4 | N accounts: pick order, each tried once per run | SPEC-03 AC-1 |
| T-5 | Chain exhaustion: tier 2 skipped when off, tier 3 skipped when unset, exits naming earliest reset | SPEC-03 AC-2, AC-6, AC-8 |
| T-6 | Tier 2 enabled: key from `keyCommand`, never printed, conversation carries, decline falls through | SPEC-03 AC-3..5 |
| T-7 | `cc add` success and rollback; no credential/history/project copied | SPEC-02 AC-1..3, AC-6 |
| T-8 | `cc add` / `cc remove` guards | SPEC-02 AC-4,5,7,8 |
| T-9 | Regression: live-limit handoff still carries the conversation | existing behaviour |
| T-10 | Plugin hooks: `SessionStart` names the right id; `Stop` fires once per limit window | plugin |
| T-11 | Security greps: no credential reads, no personal strings, no network calls | S-1, S-2, S-4 |

T-2 is the one that matters most — it is the regression that logged a real user out.

## Documentation set

| File | Contents |
|---|---|
| `README.md` | what it is, honest framing, install, quickstart, logout warning, how failover works, what it does **not** do (no Copilot backend, no browser sessions, no mid-session switch) |
| `docs/HOW-IT-WORKS.md` | 429 detection shape, offset logic, both false-positive traps, why a live session cannot switch |
| `docs/CONFIG.md` | every field, the tier chain, tier-2 cost warning |
| `docs/TROUBLESHOOTING.md` | logged-out recovery, stale npm shim, node >= 22, "cc only governs what it launched" |
| `CONTRIBUTING.md` | run the bats suite; never weaken the `isDefault` rule |
| `SECURITY.md` | reporting, and the explicit "never reads credentials" statement |
| `LICENSE` | MIT |
| `CHANGELOG.md` | starts at 2.0.0 |

## Repository and marketplace

```
claude-account-switcher/
  bin/       cc, cc-detect, cc-watch
  plugin/    .claude-plugin/plugin.json, SKILL.md, hooks/, commands/
  .claude-plugin/marketplace.json      <- the repo is itself a marketplace
  test/      bats suites + stub claude
  docs/  .github/workflows/ci.yml
  install.sh  uninstall.sh
```

1. Self-hosted marketplace: `marketplace.json` with `source: "./"`. Users run
   `claude plugin marketplace add MarwanMaher0/claude-account-switcher`, then
   `claude plugin install cc-switch`.
2. Tag `v2.0.0` once CI is green on both runners and a clean-checkout install works.
3. Optional: PR to Anthropic's `claude-plugins-official` with a `git-subdir` entry pinned to
   tag and sha, `category: productivity`. Acceptance is not ours to decide, so the self-hosted
   path must stand alone.

## Acceptance criteria

Every S-gate and every T-test passes, or carries a written, signed-off exception. Publication
is blocked otherwise.
