# Reddit post — draft for review

Not posted. Reddit is much harsher on self-promotion than LinkedIn, so the framing matters more
here, not less.

## Where

| Subreddit | Fit | Watch out for |
|---|---|---|
| r/ClaudeAI | best fit — the people with this exact problem | check the self-promo rule; some weeks it is enforced strictly |
| r/ClaudeCode | smaller, directly on topic | same |
| r/commandline | fits as a shell tool | wants the tool to be the point, not the story |

Post to **one** first. Cross-posting the same text to three subs in an hour is the fastest way
to be read as spam.

## Rules to respect

- Most subs require participation history before a self-promo post. If the account is new or
  inactive, expect a removal regardless of quality.
- Lead with the problem and the technical finding, not the link. The link goes at the end.
- Say plainly that it does not bypass limits. On Reddit someone *will* raise it, and it is much
  better answered in the post than in the comments.
- Answer replies. A post that ships and goes quiet reads worse than no post.

---

## Draft — r/ClaudeAI

**Title:** I hit my Claude limit with a second account sitting idle, so I made the conversation move between them

**Body:**

> I have two Claude subscriptions — a personal plan and a work seat. Hitting the limit on one
> while the other sat unused was a daily annoyance, so I spent a day on it. Three things I
> learned that might be useful even if you never touch the tool:
>
> **A running session can't change accounts.** `CLAUDE_CONFIG_DIR` and the credentials are read
> once at process start. No hook, plugin or command can rebind them, and there's no
> "rate limited" hook event to react to anyway. So switching has to happen *between* runs: end
> the run, copy the transcript, resume on the next account with `--resume`. Roughly four seconds,
> conversation intact.
>
> **Claude Code doesn't exit when you hit the limit.** I assumed it did. Checking a real
> rate-limit event in my own session history showed the session logged 281 more lines over the
> next fifty minutes — it just sits there. So something has to end the run deliberately.
>
> **A 429 isn't always your usage limit.** This one I only found by pointing the real binary at
> a mock API that always returns 429. It recorded `quotaLimits: null` and printed
> "Server is temporarily limiting requests (not your usage limit)". So transient throttling and
> a real quota limit look similar but differ in the payload — and switching accounts on a
> transient throttle would be pointless, since the next account talks to the same servers.
>
> The detection keys on the structured `quotaLimits` field rather than the human-readable
> message, which can be reworded any time.
>
> To be explicit, since it always comes up: this switches between accounts **you already pay
> for**. It doesn't pool or share accounts and it doesn't raise anyone's limits — each account's
> own limits still apply in full. If you only have one subscription it does nothing for you.
>
> MIT, works on Linux and macOS, no network calls, never reads your credentials file:
> https://github.com/MarwanMaher0/claude-account-switcher
>
> Happy to answer anything about the detection or the handoff.

---

## Shorter variant — r/commandline

**Title:** cc — switch between multiple Claude Code accounts when one hits its rate limit, keeping the conversation

> Two Claude subscriptions, and I kept stalling on one while the other sat idle.
>
> The constraint that shapes the whole thing: an account is bound at process start, so nothing
> can switch one mid-session. The switch has to happen between runs — end the session, move the
> transcript, resume on the next account.
>
> Plain bash and python3, no dependencies. The test suite stubs the CLI and runs against a
> throwaway `HOME`, so it needs no API key and consumes no quota — 109 assertions, no framework
> to install.
>
> https://github.com/MarwanMaher0/claude-account-switcher

---

## Checklist

- [ ] Account has enough history in the target sub to not trip the self-promo filter
- [ ] Read that sub's current rules — they change
- [ ] Post to one sub, wait a day, then consider a second
- [ ] Be around for the first few hours to answer replies
- [ ] Link last, problem first
