# GitHub profile README — draft

Not published. This would live in a repo named `MarwanMaher0/MarwanMaher0`, whose README renders
on your profile page at `github.com/MarwanMaher0`.

Written to the brief: lead with the problem, then who uses it and why. Everything below is a
claim about you — check each line before it goes up, and cut anything you would not say out loud.

---

```markdown
## Marwan Maher

Digital transformation, and the tooling that makes it survive contact with real work.

I build internal platforms for IP and trademark operations — case management, automated
watch pipelines, and the integrations that hold them together. Most of what I ship is
private, so this profile is the small part that generalises.

### 🔁 claude-account-switcher

**The problem:** you are deep in a task, Claude Code hits its 5-hour limit, and your second
account sits idle. Switching means logging out, logging back in, and abandoning a
conversation you were forty messages into. So you wait.

**The fix:** one command. The run ends, the transcript moves, and the same conversation
resumes on your other account in about four seconds.

**Who it's for:** anyone holding more than one Claude subscription — typically a personal
plan and a work seat — who loses real time to the limit window. It doesn't pool or share
accounts; every account's own limits still apply.

Built on the `CLAUDE_CONFIG_DIR` variable alone. No proxies, no third-party services, no
network calls, no telemetry. MIT.

→ **[claude-account-switcher](https://github.com/MarwanMaher0/claude-account-switcher)**

### What I care about in code

- **Check the real data before writing the parser.** The rate-limit detection in that tool
  is built on an actual recorded 429, not a guess at the shape. A later test against the
  real binary showed a 429 can also mean transient throttling, with a different payload —
  which would have been a false switch on every hiccup.
- **Tests that cost nothing to run.** That project stubs the CLI and uses a throwaway HOME,
  so the suite touches no real account and consumes no API quota. 109 assertions, no
  framework to install.
- **Say what broke.** Mid-build, my own tool logged me out of my main account by setting one
  environment variable that looked harmless. That story is in the README, because a fork
  would otherwise reintroduce it.

### Currently

Working on trademark-watch automation and the operations platform around it.

📫 marwanmaher635@gmail.com
```

---

## Notes before publishing

- The "Digital transformation" line and the "Currently" section describe your day job in
  general terms and name no employer. Keep it that way unless you want the association.
- The email is already public in the plugin manifest, so this adds no new exposure.
- If you would rather not lead with one project, cut the whole `claude-account-switcher`
  block — the "What I care about in code" section stands on its own.
- No badges, no stats widgets, no streak counters. They read as noise on an otherwise
  serious profile; add them only if you actively want that look.
