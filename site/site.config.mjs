// Single place that names the deployment and maps repository Markdown onto site pages.
// Only titles, descriptions, sidebar groups and FAQ questions are written here; every
// paragraph on the site is pulled from README.md, docs/, PRIVACY.md or SECURITY.md at build time
// by scripts/sync-docs.mjs.

export const repo = 'https://github.com/MarwanMaher0/claude-account-switcher'
export const branch = 'main'
export const base = '/claude-account-switcher/'
export const siteOrigin = 'https://marwanmaher0.github.io'
export const siteUrl = `${siteOrigin}${base}`
export const siteName = 'cc-switch'
export const author = { name: 'Marwan Maher', url: 'https://github.com/MarwanMaher0' }

export const groups = [
  { id: 'use', label: 'Use it' },
  { id: 'reference', label: 'Reference' },
  { id: 'help', label: 'Help' },
  { id: 'trust', label: 'Privacy and security' },
]

// A source is either a whole file (its H1 becomes the page title) or a list of sections picked by
// heading text. `title: true` turns that section's heading into the page title; `exclude` drops
// sub-sections that live on another page.
export const pages = [
  {
    slug: 'get-started',
    title: 'Get started',
    group: 'use',
    description: 'Install cc-switch, see the account you already use, add another one you own, and start Claude Code with cc instead of claude.',
    sources: [
      { file: 'README.md', section: 'Get started', title: true, exclude: ['Step 6: VS Code users only'] },
    ],
    tip: { text: 'Use the Claude panel in VS Code? Finish with the [VS Code](vscode) steps.' },
  },
  {
    slug: 'everyday-use',
    title: 'Everyday use',
    group: 'use',
    description: 'The cc commands you use day to day, how to read cc status, the terminal versus the VS Code panel, removing an account and uninstalling.',
    sources: [
      { file: 'README.md', section: 'Everyday use', title: true },
      { file: 'README.md', section: 'Never pause: the terminal versus the VS Code panel' },
      { file: 'README.md', section: 'Switching before the limit (optional)' },
      { file: 'README.md', section: 'Remove an account' },
      { file: 'README.md', section: 'Uninstall' },
    ],
  },
  {
    slug: 'separate-projects',
    title: 'Separate projects: one account per folder',
    sidebarLabel: 'Separate projects',
    group: 'use',
    description: 'Pin each employer’s or client’s folders to that company’s Claude Code account with cc pin, and decide what happens when it hits its limit.',
    sources: [
      {
        file: 'README.md',
        section: 'Separate projects: one account per folder',
        title: true,
        exclude: ['VS Code with pinned folders', 'Never pause: the terminal versus the VS Code panel', 'Switching before the limit (optional)'],
      },
    ],
    tip: { text: 'Pinned folders in VS Code windows are covered on the [VS Code](vscode#vs-code-with-pinned-folders) page.' },
  },
  {
    slug: 'vscode',
    title: 'VS Code',
    group: 'use',
    description: 'Make each VS Code window run the Claude panel on its folder’s account: install the plugin per account, bind windows with cc vscode on, and how pinned folders behave.',
    sources: [
      { file: 'README.md', section: 'Step 6: VS Code users only', title: true },
      { file: 'README.md', section: 'VS Code with pinned folders' },
    ],
  },
  {
    slug: 'configuration',
    title: 'Configuration',
    group: 'reference',
    description: 'Reference for ~/.claude-switch/config.json and state: accounts, isDefault, paid fallbacks, pinned folders, auto-continue, early switch and environment variables.',
    sources: [{ file: 'docs/CONFIG.md' }],
  },
  {
    slug: 'how-it-works',
    title: 'How it works',
    group: 'reference',
    description: 'How cc-switch detects a rate limit, why a live session cannot change accounts, how the handoff resumes the same conversation, and how VS Code windows are bound.',
    sources: [{ file: 'docs/HOW-IT-WORKS.md' }],
  },
  {
    slug: 'troubleshooting',
    title: 'Troubleshooting',
    group: 'help',
    description: 'Fixes for common cc-switch problems: logged out, cc not found, no switch at a limit, a VS Code window on the wrong account, and plugin install errors.',
    sources: [{ file: 'docs/TROUBLESHOOTING.md' }],
  },
  {
    slug: 'changelog',
    title: 'Changelog',
    group: 'reference',
    description: 'Release notes for cc-switch, including account switching, pinned folders, VS Code binding, and privacy fixes.',
    sources: [{ file: 'CHANGELOG.md' }],
  },
  {
    slug: 'faq',
    title: 'FAQ',
    group: 'help',
    description: 'Short answers about cc-switch, each quoted from the documentation it links to.',
    faq: true,
  },
  {
    slug: 'privacy',
    title: 'Privacy',
    group: 'trust',
    description: 'What cc-switch reads, writes and sends: everything stays on your machine, and the optional live usage check can be turned off.',
    sources: [{ file: 'PRIVACY.md' }],
  },
  {
    slug: 'security',
    title: 'Security',
    group: 'trust',
    description: 'What cc-switch touches and never touches, how to report a problem, and the one failure mode worth knowing about.',
    sources: [{ file: 'SECURITY.md' }],
  },
]

// Home page: hand-written headings, bodies pulled from the README.
export const home = {
  title: 'One Claude Code account per project',
  description: 'cc-switch keeps each project folder on its own Claude Code account, an employer’s, a client’s or your own, and carries the conversation to your next account when one hits its limit.',
  sections: [
    {
      heading: 'Keep each employer’s work on its own account',
      from: { file: 'README.md', section: 'Separate projects: one account per folder', until: '**If a company account hits its limit**' },
      more: { text: 'How pinning works', slug: 'separate-projects' },
    },
    {
      heading: 'Keep working when an account hits its limit',
      from: { file: 'README.md', section: '#intro' },
      more: { text: 'Install in five minutes', slug: 'get-started' },
    },
    { heading: 'Is this for you?', from: { file: 'README.md', section: 'Is this for you?' } },
    { heading: 'Good to know', from: { file: 'README.md', section: 'Good to know' } },
    { heading: 'Try it without installing', from: { file: 'README.md', section: 'Try it without installing' } },
  ],
}

// FAQ: the questions are written here, every answer is quoted from the docs. `match` picks the
// paragraph, list item or note containing that text; without it the whole section is used.
export const faq = [
  { q: 'Who is cc-switch for?', from: { file: 'README.md', section: 'Is this for you?' } },
  {
    q: 'Can I keep each employer’s work on that employer’s account?',
    from: [
      { file: 'README.md', section: 'Separate projects: one account per folder', match: 'From then on, every `cc` started' },
      { file: 'README.md', section: 'Separate projects: one account per folder', match: 'A company account never falls back' },
      { file: 'README.md', section: 'Separate projects: one account per folder', match: 'A pinned account is kept for its folders' },
    ],
  },
  {
    q: 'Does anything from a company project leave my machine when it falls back to my own account?',
    from: { file: 'README.md', section: 'Separate projects: one account per folder', match: 'Falling back to `personal` copies' },
  },
  { q: 'Can a running session change accounts?', from: { file: 'README.md', section: 'Good to know', match: 'A running session cannot change accounts' } },
  { q: 'Does a plain `claude` switch accounts too?', from: { file: 'README.md', section: 'Good to know', match: 'only switches sessions it started' } },
  { q: 'What happens when every account is used up?', from: { file: 'README.md', section: 'Good to know', match: 'When every account is used up' } },
  {
    q: 'Why does the VS Code panel not carry on by itself after a switch?',
    from: [
      { file: 'README.md', section: 'Never pause: the terminal versus the VS Code panel', match: 'In the VS Code panel' },
      { file: 'README.md', section: 'Never pause: the terminal versus the VS Code panel', match: 'So when you need work to continue' },
    ],
  },
  { q: 'Does `cc` clash with the C compiler?', from: { file: 'README.md', section: 'Step 2: Install', match: 'usual name of the C compiler' } },
  { q: 'What does the Claude Code plugin add?', from: { file: 'README.md', section: 'Step 2: Install', match: 'The plugin itself adds' } },
  { q: 'Does it send anything anywhere?', from: { file: 'PRIVACY.md', section: '#intro', match: 'Short version' } },
  { q: 'Does it read my login credentials?', from: { file: 'SECURITY.md', section: 'What this tool does and does not touch', match: 'Never reads, copies or prints a credentials file' } },
  { q: 'Can it switch my claude.ai browser chats?', from: { file: 'docs/TROUBLESHOOTING.md', section: 'My browser session hit its limit' } },
  { q: 'Can it use my GitHub Copilot subscription?', from: { file: 'docs/TROUBLESHOOTING.md', section: 'Can it use my GitHub Copilot subscription?' } },
  { q: 'Can I try it without installing?', from: { file: 'README.md', section: 'Try it without installing' } },
]
