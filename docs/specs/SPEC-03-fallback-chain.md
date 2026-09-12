# SPEC-03 — The fallback chain

## Problem

With N accounts the question "what happens when they are all spent?" needs a defined answer
rather than an error. Two further sources exist, and they differ in ways the user must be told
about before either is used: one costs money per token, the other is a different product.

## In scope

- Tier order and the transition between tiers.
- Tier 2 (`ANTHROPIC_API_KEY`) opt-in, cost warning, and conversation carry-over.
- Tier 3 (external CLI) handoff and its explicit lack of carry-over.
- Behaviour when everything is exhausted.

## Out of scope

- **GitHub Copilot as a Claude Code backend.** Claude Code speaks the Anthropic Messages API,
  plus Bedrock/Vertex/Foundry which serve Claude models. Copilot is a different vendor with
  different auth; there is no supported way to point Claude Code at its quota. Unofficial
  proxies that re-expose Copilot as an Anthropic endpoint breach GitHub's terms and risk the
  user's account. Copilot may only ever appear as a **tier 3 external CLI**, launched as
  itself, never as a Claude Code backend.
- Bedrock / Vertex / Foundry wiring — possible later, not built now.

## The chain

| Tier | Source | Conversation | Cost | Default |
|---|---|---|---|---|
| 1 | Claude accounts, config order | **carries** via `--resume` | subscription | on |
| 2 | `ANTHROPIC_API_KEY` | **carries** via `--resume` | **per token** | **off** |
| 3 | External CLI | **does not carry** | depends | **off** |

Tier 1 is exhausted only when every account's `limitedUntil` is in the future. Within a single
`cc` run an account is tried at most once, so a mid-run limit cannot cause a loop.

## Tier 2 — API key

Used only when every account is limited and `fallbacks.apiKey.enabled` is true.

- The key comes from `keyCommand` — a shell command printing the key on stdout — so no key is
  ever stored in the config file. If `keyCommand` is unset, the tier is skipped.
- Launched as `env -u CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY=<key> claude --resume <session>`, so
  the conversation continues.
- With `confirmEachUse` (default true), print the cost warning and require confirmation before
  launching. This tier bills per token against an account that has no subscription cap — an
  unattended fallback into it could spend real money overnight.
- The key is never printed, logged, or written to state.

**Open risk, to be settled during implementation:** Claude Code records approved keys under
`customApiKeyResponses` in `.claude.json` and may prompt on first use of a new key. If the
prompt cannot be satisfied non-interactively, tier 2 falls through to tier 3 rather than
hanging. The implementation must detect the hang case and time out.

## Tier 3 — external CLI

Used when tiers 1 and 2 are exhausted or disabled, and `fallbacks.externalCli.command` is set
and its binary exists.

- Runs the configured command in the same working directory.
- **Prints plainly that this is a different tool with no shared context**, and echoes the
  transcript path so the user can carry anything over by hand.
- Never attempts to translate or import the transcript — a partial, silently-lossy import is
  worse than an honest fresh start.
- Skipped silently when unset or the binary is missing. Ships unset.

## Exhaustion

When nothing is available, `cc` exits non-zero, names the account that frees up soonest and its
reset time, and does not loop or poll.

## Acceptance criteria

| # | Criterion |
|---|---|
| AC-1 | With N accounts, tier 1 walks config order and tries each at most once per run. |
| AC-2 | Tier 2 is skipped entirely while `enabled` is false, even when all accounts are limited. |
| AC-3 | With tier 2 enabled, the key is fetched from `keyCommand` and never appears in output, state, or config. |
| AC-4 | `confirmEachUse: true` blocks the launch until confirmed; declining falls through to tier 3. |
| AC-5 | Tier 2 carries the conversation — the resumed session contains the pre-limit turns. |
| AC-6 | Tier 3 is skipped when unset or when the binary is missing, without an error. |
| AC-7 | Tier 3 prints the no-shared-context warning and the transcript path before launching. |
| AC-8 | Full exhaustion exits non-zero naming the earliest reset time, with no loop. |
| AC-9 | Copilot is never invoked as a Claude Code backend anywhere in the codebase. |
