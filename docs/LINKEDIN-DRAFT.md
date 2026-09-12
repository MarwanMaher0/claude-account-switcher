# LinkedIn post — final

Plain text throughout. LinkedIn does **not** render markdown: asterisks show up as asterisks.
Copy from the plain-text blocks below, not from any formatted version.

---

## THE POST (recommended)

Hook is the confession, not the tool. The first two lines are all that shows before
"see more", so they carry the whole job of earning the click.

```text
I built a tool to switch between my two Claude accounts.

On the first run, it logged me out of my main one.

Not a crash. Not a bug report. Just gone — and the token was unrecoverable, because Claude Code backs up its config file but never its credentials file.

The cause was one environment variable that looked completely harmless.

Setting CLAUDE_CONFIG_DIR to a directory is how you point Claude Code at a second account. So I set it to the first account's own directory, assuming that was a no-op.

It isn't. The default account keeps its config file BESIDE that directory, not inside it. Point the variable there and Claude Code finds nothing, decides you're a brand-new user, runs onboarding, and overwrites your credentials with whoever logs in next.

I did that to myself while building the thing meant to prevent it.

Three things that were actually worth learning:

1. A running session can never change accounts.

The config directory and credentials are read once, at process start. No hook, no plugin, no command can rebind them — and there's no "rate limited" event to react to anyway. I spent hours trying to work around that before accepting it. The way through was to stop fighting: end the run, move the transcript, resume on the next account. Four seconds, conversation intact.

Most of my good architectural decisions have started as a constraint I initially refused to accept.

2. Claude Code doesn't exit when you hit the limit.

I assumed it did. So I checked a real rate-limit event in my own session history — and found the session had logged 281 more lines over the next fifty minutes. It just sits there.

If I'd trusted the assumption, the tool would have quietly done nothing at the one moment it existed for.

3. A 429 is not always your usage limit.

This one only surfaced because I stopped trusting my own test double and pointed the real binary at a mock server that always returns 429.

It recorded an empty quota payload and printed: "Server is temporarily limiting requests (not your usage limit)."

So transient throttling and a real limit look nearly identical — and switching on a throttle is pointless, since the next account hits the same servers. My code already ignored it, but by accident rather than design. It had no test. Now it does.

The thread running through all three: I was wrong every time I reasoned from what I assumed the system did, and right every time I looked at what it actually recorded.

MIT, Linux and macOS, no network calls, never reads your credentials file. 109 tests that consume no API quota, because the CLI is stubbed.

To be explicit, because someone always asks: it switches between accounts you already pay for. It doesn't pool accounts and it doesn't raise anyone's limits. One subscription? This does nothing for you.

Link in the comments.

#ClaudeCode #DeveloperTools #SoftwareEngineering #OpenSource
```

**First comment** (post this immediately after — LinkedIn suppresses posts with external
links in the body):

```text
Repo: https://github.com/MarwanMaher0/claude-account-switcher

The write-up of the detection logic and both false-positive traps is in docs/HOW-IT-WORKS.md if you want the detail.
```

---

## SHORT VERSION

If you'd rather not post something this long.

```text
I built a tool to switch between my two Claude accounts.

On the first run, it logged me out of my main one.

One environment variable. CLAUDE_CONFIG_DIR pointed at the default account's own directory — which I assumed was a no-op. It isn't: Claude Code keeps that account's config file beside the directory, not inside it. So it found nothing, decided I was a new user, ran onboarding, and overwrote my credentials. Unrecoverable.

Three things I'd have got wrong if I'd trusted my assumptions instead of checking the real data:

→ A running session can never change accounts. Config and credentials are read once at process start. So the switch has to happen between runs: end it, move the transcript, resume. Four seconds, conversation intact.

→ Claude Code doesn't exit when you hit the limit. A real session in my history logged 281 more lines over the following fifty minutes. It just sits there.

→ A 429 isn't always your usage limit. Transient throttling looks almost identical but carries no quota payload — and switching accounts on it is pointless, since the next account hits the same servers.

Every one of those came from looking at what the system actually recorded, not what I assumed it did.

MIT, Linux and macOS, no network calls, 109 tests. Link in the comments.

#ClaudeCode #DeveloperTools #SoftwareEngineering
```

---

## Posting notes

**Format**
- Paste as plain text. Markdown does not render — `**bold**` appears as literal asterisks.
- The line breaks matter. LinkedIn collapses nothing, and the white space is what makes a long
  post readable on a phone.
- Only the first ~2 lines show before "see more". They are doing all the work.

**Link placement**
- Keep the link out of the post body; put it in the first comment, added straight after posting.
  Posts with external links in the body reach fewer people.

**Timing**
- Tuesday to Thursday morning, in your audience's timezone. Avoid Friday and the weekend.

**Hashtags**
- Three or four, at the end. More reads as reach-farming.

**After posting**
- Reply to every comment in the first two hours. Engagement early is what decides whether it
  travels, and a post that ships then goes silent reads worse than no post.
- Expect "isn't this against the ToS?" — the answer is in the post, but answer it again plainly
  and without defensiveness. It's a fair question.

**Before you post — check each line is true of you**
- Three days of work: adjust if that's not right.
- The logout story is real and is the strongest thing in the post. Keep it.
