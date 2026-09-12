# LinkedIn post — draft for review

Not published. Nothing goes out without sign-off, and the repo must be public with CI green
first, so the link works on day one.

Framing rule from SPEC-04: this is about switching between accounts you already own. No
"never hit rate limits", no "bypass" language, nothing implying unlimited usage.

---

## Draft A — the engineering story (recommended)

> I hold two Claude subscriptions — a personal one and a work seat. Hitting the limit on one
> while the other sat idle was a daily annoyance, so I spent a day fixing it properly.
>
> The tool turned out to be the easy part. Three things made it interesting:
>
> **1. A running session can never change accounts.**
> The config directory and credentials are read once, at process start. No hook, plugin or
> command can rebind them afterwards — and there is no "rate limited" hook event to react to
> anyway. So the switch can only happen *between* runs. Accepting that constraint, instead of
> fighting it, is what made the rest work: end the run, copy the transcript, resume on the next
> account. About four seconds, conversation intact.
>
> **2. Claude Code doesn't exit when you hit a limit.**
> I assumed it did. Checking an actual rate-limit event in my own session history showed the
> session logged 281 more lines over the following fifty minutes. It just sits there. So
> something has to end the run deliberately — which I only knew to build because I checked the
> real data instead of trusting the assumption.
>
> **3. The bug that logged me out.**
> Setting CLAUDE_CONFIG_DIR to the default account's own path is not the same as leaving it
> unset. Claude Code then looks for a config file that isn't there, decides you're a new user,
> runs onboarding, and overwrites your credentials with whatever logs in next. My own tool did
> this to me mid-build. The token wasn't recoverable — .claude.json gets backed up,
> .credentials.json doesn't.
>
> That one became three guard rails and a test whose only job is to assert an environment
> variable is absent.
>
> Two more bugs came out of a test harness that stubs the CLI and fakes a rate limit, so the
> suite costs no quota: an expired limit event in the transcript tail marking an account spent
> forever, and — my favourite — the handoff copying the transcript *including* the 429, so the
> receiving account read the previous account's limit and declared itself limited too. One
> clean handoff, then an infinite ping-pong.
>
> MIT, 106 tests, no network calls, and it never reads a credentials file:
> github.com/MarwanMaher0/claude-account-switcher
>
> To be clear about what it is: it switches between accounts you already pay for. It doesn't
> pool or share accounts and it doesn't raise anyone's limits — each account's limits apply in
> full. If you have one subscription, it won't help you.

**Why this one:** the three findings are specific, verifiable and useful to anyone building on
Claude Code. The failure is told honestly, which reads as competence rather than self-criticism.

---

## Draft B — short

> Two Claude subscriptions, and I kept hitting the limit on one while the other sat idle. So I
> built a switcher.
>
> The interesting part wasn't the tool — it was discovering that a running session can never
> change accounts. Config and credentials are read once at process start; nothing can rebind
> them. So the switch happens between runs: end the session, copy the transcript, resume on the
> next account. Four seconds, conversation intact.
>
> Then my own tool logged me out. Setting CLAUDE_CONFIG_DIR to the default account's own path
> makes Claude Code think you're a new user and overwrite your credentials. Unrecoverable.
> That became three guard rails and a test that asserts an environment variable is absent.
>
> MIT, 106 tests, no network calls:
> github.com/MarwanMaher0/claude-account-switcher
>
> It switches between accounts you already own. It doesn't pool accounts or raise limits.

---

## Checklist before posting

- [ ] Repo public, CI green on both runners
- [ ] `git log --format='%ae' | sort -u` shows only the personal address
- [ ] README opens with the honest framing
- [ ] Link resolves in a logged-out browser
- [ ] No employer name anywhere in the post or repo
- [ ] Sign-off received
