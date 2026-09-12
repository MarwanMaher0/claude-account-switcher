# Specs

Written before the code they describe. Each states what is in scope, what is explicitly out,
and acceptance criteria that a test can check.

| Spec | Covers | Status |
|---|---|---|
| [SPEC-01](SPEC-01-config-schema.md) | `config.json` shape, `state.json` migration, the `isDefault` rule | drafted |
| [SPEC-02](SPEC-02-account-management.md) | `cc add` / `cc remove`, guided login, rollback | drafted |
| [SPEC-03](SPEC-03-fallback-chain.md) | tier order, API-key opt-in, external-CLI handoff | drafted |
| [SPEC-04](SPEC-04-release.md) | security checklist, CI, docs, marketplace | drafted |

## The rule that outranks everything else

`CLAUDE_CONFIG_DIR=~/.claude` is **not** the same as leaving the variable unset.

Claude Code keeps the default account's config at `~/.claude.json` — beside the directory, not
inside it. Set the variable and it looks for `~/.claude/.claude.json`, finds nothing, runs
first-time onboarding, and overwrites `~/.claude/.credentials.json` with whatever account logs
in next. That silently logs the user out of their default account, and the old token is
unrecoverable because Claude Code backs up `.claude.json` but never `.credentials.json`.

The default account is therefore launched with `env -u CLAUDE_CONFIG_DIR`, always. No spec may
weaken this, and `SPEC-01 AC-7` is the test that guards it.
