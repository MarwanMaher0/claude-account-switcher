import type { Locale } from './faq'

export interface Feature {
  title: string
  text: string
  code: string
  href: string
  icon: 'pin' | 'wall' | 'window' | 'relay' | 'choice' | 'thread' | 'gauge' | 'lock'
}

export interface LandingCopy {
  htmlTitle: string
  metaDescription: string
  ogAlt: string
  skip: string
  nav: { why: string; features: string; start: string; faq: string; docs: string; menu: string; theme: string; language: string; github: string }
  hero: {
    eyebrow: string
    headline: [string, string]
    summary: string
    primary: string
    secondary: string
    note: string
    visualLabel: string
  }
  demo: {
    title: string
    folders: { path: string; account: string; kind: 'pinned' | 'default'; onLimit: string }[]
    lines: { folder: string; command: string; output: string[] }[]
    caption: string
  }
  trust: { intro: string; items: string[] }
  problem: {
    label: string
    title: string
    text: string
    before: string
    after: string
    beforeRows: [string, string][]
    afterRows: [string, string][]
    beforeLimit: string
    afterLimit: string
    rulesTitle: string
    rules: string[]
  }
  features: { label: string; title: string; text: string; cards: Feature[] }
  start: {
    label: string
    title: string
    text: string
    fullGuide: string
    copy: string
    copied: string
    copyFail: string
    steps: { title: string; note: string; code: string }[]
    handoffTitle: string
    handoff: string[]
    handoffNote: string
  }
  who: { label: string; title: string; cases: { title: string; text: string }[]; notTitle: string; not: string[] }
  faq: { label: string; title: string; text: string }
  final: { label: string; title: string; text: string; primary: string; github: string }
  footer: { text: string; docs: string; start: string; privacy: string; security: string; changelog: string; llms: string; license: string; disclaimer: string; otherLanguage: string }
}

const repoUrl = 'https://github.com/MarwanMaher0/claude-account-switcher'

export const install = `git clone ${repoUrl}.git\ncd claude-account-switcher\n./install.sh`

export const landingCopy: Record<Locale, LandingCopy> = {
  en: {
    htmlTitle: 'cc-switch: one Claude Code account per project folder',
    metaDescription: 'cc-switch pins each project folder to the Claude Code account it belongs to, so an employer’s or client’s work never runs on the wrong account, and moves a session to the next account you own when one hits its limit. Open source, local, no telemetry.',
    ogAlt: 'cc-switch: each project folder on its own Claude Code account.',
    skip: 'Skip to content',
    nav: { why: 'Why', features: 'Features', start: 'Quick start', faq: 'FAQ', docs: 'Docs', menu: 'Menu', theme: 'Toggle dark theme', language: 'العربية', github: 'GitHub' },
    hero: {
      eyebrow: 'For Claude Code on Linux and macOS',
      headline: ['Each project folder on', 'its own Claude account.'],
      summary: 'cc pins a folder to the Claude Code account it belongs to: your employer’s seat, a client’s, or your personal plan. Work never runs on the wrong account. And when one of your own accounts hits its usage limit, cc moves the session to the next one you own, conversation included.',
      primary: 'Get started',
      secondary: 'See how pins work',
      note: 'Your own accounts only. cc does not pool, share or bypass accounts, and it cannot raise any limit.',
      visualLabel: 'Illustration: three folders, each pinned to a different Claude Code account, and the terminal output of cc in each one.',
    },
    demo: {
      title: 'Pick a folder',
      folders: [
        { path: '~/work/acme', account: 'acme', kind: 'pinned', onLimit: 'switch to personal' },
        { path: '~/clients/globex', account: 'globex', kind: 'pinned', onLimit: 'stop and wait' },
        { path: '~/side/app', account: 'personal', kind: 'default', onLimit: 'next free account' },
      ],
      lines: [
        { folder: '~/work/acme', command: 'cc', output: ['pinned folder  ~/work/acme  ->  acme', 'starting Claude Code on acme  (you@acme.example)', 'if acme hits its limit: switch to personal'] },
        { folder: '~/clients/globex', command: 'cc', output: ['pinned folder  ~/clients/globex  ->  globex', 'starting Claude Code on globex  (you@globex.example)', 'if globex hits its limit: stop and wait for reset'] },
        { folder: '~/side/app', command: 'cc', output: ['no pin  ->  personal (default)', 'starting Claude Code on personal  (you@gmail.com)', 'acme and globex are reserved for their folders'] },
      ],
      caption: 'Illustration. Real output comes from cc status and cc pin.',
    },
    trust: {
      intro: 'Open source and local',
      items: ['MIT licence', 'No telemetry', 'Never reads credentials', 'bash 3.2+ · Python 3.6+', '{tests} checks in CI', 'v{version}'],
    },
    problem: {
      label: '01 — The problem',
      title: 'One ~/.claude for everything is how work lands on the wrong account.',
      text: 'Claude Code reads one account when it starts. With a work seat, a client’s seat and your own plan, every folder runs on whichever one happens to be signed in. And when that account hits its limit, the fix is sign out, sign in, and lose the conversation.',
      before: 'Without cc',
      after: 'With cc pin',
      beforeRows: [['~/work/acme', 'whichever account is signed in'], ['~/clients/globex', 'the same one'], ['~/side/app', 'the same one']],
      afterRows: [['~/work/acme', 'acme · pinned'], ['~/clients/globex', 'globex · pinned'], ['~/side/app', 'personal · default']],
      beforeLimit: 'At a limit: sign out, sign in, conversation gone.',
      afterLimit: 'At a limit: only the move the pin allows, conversation carried over.',
      rulesTitle: 'The rules a pin enforces',
      rules: [
        'A company account never falls back to another company’s account. The only fallback a pin can name is an account that is not pinned anywhere.',
        'A pinned account is kept for its folders. Outside them, cc never picks it, so personal work never uses a company seat.',
        'Each session follows its own folder. An acme limit only affects acme sessions; a globex window keeps working.',
        'With no pins, nothing changes: cc simply rotates over the accounts you own.',
      ],
    },
    features: {
      label: '02 — What it does',
      title: 'Separation first.\nContinuity second.',
      text: 'Everything below is in the current release and covered by the test suite. Nothing here needs a server, an API key or a change to your repositories.',
      cards: [
        { icon: 'pin', title: 'Pin a folder to an account', text: 'Run it once inside a folder. Every cc session there, and in every subfolder, uses that account from then on. Pins live in ~/.claude-switch, never in the repository.', code: 'cc pin', href: 'docs/separate-projects/' },
        { icon: 'wall', title: 'Walls between employers', text: 'A company account never falls back to another company’s. A pinned account is never used outside its folders. cc --acct still overrides a pin for one session when you ask.', code: 'cc pins', href: 'docs/separate-projects/' },
        { icon: 'window', title: 'VS Code windows follow their folder', text: 'Each window runs the Claude panel on its folder’s account and shows it in the status bar. Several windows can run on different accounts at once, and open windows re-check on their own.', code: 'cc vscode on', href: 'docs/vscode/#vs-code-with-pinned-folders' },
        { icon: 'relay', title: 'Failover that keeps the conversation', text: 'When an account you own hits its limit, cc ends the run, records when it resets, copies the transcript to the next allowed account and resumes the same session. In a terminal it sends “Continue where you left off.” for you.', code: 'cc', href: 'docs/how-it-works/#the-handoff' },
        { icon: 'choice', title: 'You decide what a limit means', text: 'Per pin: switch to your personal account, stop and wait for the reset, or ask each time. In VS Code the question is a notification with Use personal or Stay.', code: '--fallback none', href: 'docs/separate-projects/' },
        { icon: 'thread', title: 'Chats follow their pin', text: 'A folder pinned after you used it keeps its history: cc hard-links its earlier chats into the pin’s account. Nothing is moved, deleted or overwritten, and another pin’s chats never travel.', code: 'cc adopt', href: 'docs/how-it-works/#a-folders-chats-follow-its-pin' },
        { icon: 'gauge', title: 'Switch before the wall, if you want', text: 'On Pro and Max plans, cc can switch at 98% between turns, reading the usage Claude Code already passes to status line commands. Off by default, and no network call.', code: '"earlySwitch"', href: 'docs/configuration/#switching-before-the-limit' },
        { icon: 'lock', title: 'Local, inspectable, offline', text: 'Bash and Python, nothing to npm install. No network calls of its own, no telemetry, never reads a credentials file. State lives in ~/.claude-switch with mode 600.', code: 'bash test/run-all.sh', href: 'docs/security/' },
      ],
    },
    start: {
      label: '03 — Quick start',
      title: 'Five minutes,\nyour own accounts.',
      text: 'You need Claude Code signed in to your first account, Python 3.6 or newer, and any bash from 3.2 up. Each account you add is one you own and sign in to yourself.',
      fullGuide: 'Full setup guide, including VS Code',
      copy: 'Copy',
      copied: 'Copied',
      copyFail: 'Select the code and copy it by hand.',
      steps: [
        { title: 'Install', note: 'Copies five commands into ~/.local/bin. Or add it as a Claude Code plugin and run /cc-setup.', code: install },
        { title: 'See the account you already use', note: 'Nothing to configure: cc finds it on its own, marked (default).', code: 'cc status' },
        { title: 'Add another account you own', note: 'Asks for that account’s email, opens the login page, and refuses an account you already added.', code: 'cc add work' },
        { title: 'Pin a folder to an account', note: 'Inside the folder, or with flags from a script. Choose what a limit means for that folder.', code: 'cd ~/work/acme\ncc pin\n\n# or, without the menu:\ncc pin ~/work/acme --account acme --fallback personal' },
        { title: 'Run cc instead of claude', note: 'In a pinned folder it starts on the pin’s account. Elsewhere it uses the next account with quota.', code: 'cc' },
      ],
      handoffTitle: 'What happens at a limit',
      handoff: ['Claude Code writes the limit to the transcript', 'cc ends the run and records when the account resets', 'The transcript is copied to the next allowed account, on your disk', 'claude --resume reopens the same session there'],
      handoffNote: 'In a pinned folder, “the next allowed account” is only what the pin permits: its fallback, or nothing.',
    },
    who: {
      label: '04 — Who it is for',
      title: 'People whose Claude Code\nbelongs to more than one place.',
      cases: [
        { title: 'Contractors with several clients', text: 'Each client folder pinned to that client’s seat. Your own projects stay on your own plan, and no client’s chat is ever copied into another client’s account.' },
        { title: 'Employees with a work seat and a personal plan', text: 'Work repositories on the seat, side projects on your plan. Weekend work never burns the company’s limit, and company work never leaks into your personal history.' },
        { title: 'Teams that hand out seats', text: 'Pin per repository, choose Stop and wait where policy forbids moving a chat, and nothing is written into the repository to make it work.' },
        { title: 'Long runs that must not pause', text: 'In a terminal, when an account you own hits its limit, cc carries the conversation to the next one and continues it. Five tabs on one account each switch on their own.' },
      ],
      notTitle: 'Not for you if',
      not: [
        'You have one Claude account. There is nothing to separate and nothing to switch to.',
        'You want more quota. cc cannot raise any limit; each account keeps its own.',
        'You hit the limit in claude.ai in your browser. Web chats and their limits cannot be moved.',
        'You want to use another vendor’s subscription. Claude Code only talks to Anthropic.',
      ],
    },
    faq: { label: '05 — Questions', title: 'Before you install.', text: 'The things people ask first, answered plainly.' },
    final: { label: 'Keep every account where it belongs', title: 'Pin your first folder\ntonight.', text: 'Five minutes to install. Your own accounts, your own machine, nothing sent anywhere.', primary: 'Get started', github: 'View on GitHub' },
    footer: {
      text: 'One Claude Code account per project folder, and a conversation that survives a limit.',
      docs: 'Documentation',
      start: 'Get started',
      privacy: 'Privacy',
      security: 'Security',
      changelog: 'Changelog',
      llms: 'llms.txt',
      license: 'MIT licence',
      disclaimer: 'An independent open-source project, not affiliated with or endorsed by Anthropic. Use only accounts you own.',
      otherLanguage: 'اقرأ بالعربية',
    },
  },
  ar: {
    htmlTitle: 'cc-switch: حساب Claude Code واحد لكل مجلد مشروع',
    metaDescription: 'يربط cc-switch كل مجلد مشروع بحساب Claude Code الذي ينتمي إليه، فلا يعمل عمل جهة عملك أو عميلك على الحساب الخطأ، وينقل الجلسة إلى الحساب التالي الذي تملكه عندما يبلغ أحدها حدّه. مفتوح المصدر، محلي، بلا قياس عن بُعد.',
    ogAlt: 'cc-switch: كل مجلد مشروع على حساب Claude Code الخاص به.',
    skip: 'انتقل إلى المحتوى',
    nav: { why: 'لماذا', features: 'المزايا', start: 'البداية السريعة', faq: 'الأسئلة', docs: 'التوثيق', menu: 'القائمة', theme: 'تبديل المظهر الداكن', language: 'English', github: 'GitHub' },
    hero: {
      eyebrow: 'لـ Claude Code على لينكس وmacOS',
      headline: ['كل مجلد مشروع على', 'حساب Claude الخاص به.'],
      summary: 'يربط cc كل مجلد بحساب Claude Code الذي ينتمي إليه: مقعد جهة عملك، أو مقعد عميلك، أو خطتك الشخصية. فلا يعمل أي مشروع على الحساب الخطأ. وعندما يبلغ أحد حساباتك حدّ استخدامه، ينقل cc الجلسة إلى الحساب التالي الذي تملكه، مع المحادثة نفسها.',
      primary: 'ابدأ الآن',
      secondary: 'كيف يعمل الربط',
      note: 'حساباتك أنت فقط. لا يجمع cc الحسابات ولا يشاركها ولا يتجاوز حدودها، ولا يمكنه رفع أي حد.',
      visualLabel: 'رسم توضيحي: ثلاثة مجلدات، كل منها مربوط بحساب Claude Code مختلف، ومخرجات أمر cc في كل منها.',
    },
    demo: {
      title: 'اختر مجلدًا',
      folders: [
        { path: '~/work/acme', account: 'acme', kind: 'pinned', onLimit: 'التبديل إلى personal' },
        { path: '~/clients/globex', account: 'globex', kind: 'pinned', onLimit: 'التوقف والانتظار' },
        { path: '~/side/app', account: 'personal', kind: 'default', onLimit: 'الحساب المتاح التالي' },
      ],
      lines: [
        { folder: '~/work/acme', command: 'cc', output: ['pinned folder  ~/work/acme  ->  acme', 'starting Claude Code on acme  (you@acme.example)', 'if acme hits its limit: switch to personal'] },
        { folder: '~/clients/globex', command: 'cc', output: ['pinned folder  ~/clients/globex  ->  globex', 'starting Claude Code on globex  (you@globex.example)', 'if globex hits its limit: stop and wait for reset'] },
        { folder: '~/side/app', command: 'cc', output: ['no pin  ->  personal (default)', 'starting Claude Code on personal  (you@gmail.com)', 'acme and globex are reserved for their folders'] },
      ],
      caption: 'رسم توضيحي. المخرجات الحقيقية تأتي من cc status وcc pin.',
    },
    trust: {
      intro: 'مفتوح المصدر ومحلي',
      items: ['رخصة MIT', 'بلا قياس عن بُعد', 'لا يقرأ بيانات الاعتماد أبدًا', 'bash 3.2+ · Python 3.6+', '{tests} فحصًا في CI', 'الإصدار {version}'],
    },
    problem: {
      label: '01 — المشكلة',
      title: 'مجلد ‎~/.claude‎ واحد لكل شيء هو كيف ينتهي العمل على الحساب الخطأ.',
      text: 'يقرأ Claude Code حسابًا واحدًا عند بدء التشغيل. ومع مقعد عمل ومقعد عميل وخطة شخصية، يعمل كل مجلد على أي حساب صادف أنه مسجّل الدخول. وعندما يبلغ ذلك الحساب حدّه، يكون الحل: سجّل الخروج، ثم سجّل الدخول، واخسر المحادثة.',
      before: 'بدون cc',
      after: 'مع cc pin',
      beforeRows: [['~/work/acme', 'أي حساب مسجّل الدخول'], ['~/clients/globex', 'الحساب نفسه'], ['~/side/app', 'الحساب نفسه']],
      afterRows: [['~/work/acme', 'acme · مربوط'], ['~/clients/globex', 'globex · مربوط'], ['~/side/app', 'personal · الافتراضي']],
      beforeLimit: 'عند الحد: تسجيل خروج، تسجيل دخول، وضياع المحادثة.',
      afterLimit: 'عند الحد: الانتقال الذي يسمح به الربط فقط، مع نقل المحادثة.',
      rulesTitle: 'القواعد التي يفرضها الربط',
      rules: [
        'لا يرجع حساب شركة أبدًا إلى حساب شركة أخرى. البديل الوحيد الذي يمكن للربط تسميته هو حساب غير مربوط في أي مكان.',
        'يُحجز الحساب المربوط لمجلداته. خارجها لا يختاره cc أبدًا، فلا يستهلك عملك الشخصي مقعد شركة.',
        'تتبع كل جلسة مجلدها. حدّ acme لا يؤثر إلا في جلسات acme؛ وتواصل نافذة globex عملها.',
        'بدون عمليات ربط لا يتغير شيء: يتناوب cc ببساطة على الحسابات التي تملكها.',
      ],
    },
    features: {
      label: '02 — ماذا يفعل',
      title: 'الفصل أولًا.\nالاستمرارية ثانيًا.',
      text: 'كل ما يلي موجود في الإصدار الحالي ومغطّى بمجموعة الاختبارات. لا شيء هنا يحتاج إلى خادم أو مفتاح API أو تغيير في مستودعاتك.',
      cards: [
        { icon: 'pin', title: 'اربط مجلدًا بحساب', text: 'شغّله مرة واحدة داخل المجلد. من حينها تستخدم كل جلسة cc فيه، وفي كل مجلد فرعي، ذلك الحساب. تُحفظ عمليات الربط في ‎~/.claude-switch‎ وليس في المستودع أبدًا.', code: 'cc pin', href: 'docs/separate-projects/' },
        { icon: 'wall', title: 'جدران بين جهات العمل', text: 'لا يرجع حساب شركة أبدًا إلى حساب شركة أخرى. ولا يُستخدم الحساب المربوط خارج مجلداته. ويبقى cc --acct قادرًا على تجاوز الربط لجلسة واحدة عندما تطلب ذلك.', code: 'cc pins', href: 'docs/separate-projects/' },
        { icon: 'window', title: 'نوافذ VS Code تتبع مجلدها', text: 'تشغّل كل نافذة لوحة Claude على حساب مجلدها وتعرضه في شريط الحالة. يمكن لعدة نوافذ أن تعمل على حسابات مختلفة في آن واحد، وتعيد النوافذ المفتوحة الفحص من تلقاء نفسها.', code: 'cc vscode on', href: 'docs/vscode/#vs-code-with-pinned-folders' },
        { icon: 'relay', title: 'تبديل يحافظ على المحادثة', text: 'عندما يبلغ حساب تملكه حدّه، ينهي cc التشغيل، ويسجّل موعد إعادة الضبط، وينسخ نص الجلسة إلى الحساب التالي المسموح به، ويستأنف الجلسة نفسها. وفي الطرفية يرسل «أكمل من حيث توقفت» نيابةً عنك.', code: 'cc', href: 'docs/how-it-works/#the-handoff' },
        { icon: 'choice', title: 'أنت تقرر معنى بلوغ الحد', text: 'لكل ربط: التبديل إلى حسابك الشخصي، أو التوقف وانتظار إعادة الضبط، أو السؤال في كل مرة. وفي VS Code يأتي السؤال إشعارًا بخياري «استخدم personal» أو «ابقَ».', code: '--fallback none', href: 'docs/separate-projects/' },
        { icon: 'thread', title: 'المحادثات تتبع ربطها', text: 'المجلد الذي تربطه بعد استخدامه يحتفظ بتاريخه: ينشئ cc روابط صلبة لمحادثاته السابقة داخل حساب الربط. لا يُنقل شيء ولا يُحذف ولا يُستبدل، ولا تنتقل محادثات ربط آخر أبدًا.', code: 'cc adopt', href: 'docs/how-it-works/#a-folders-chats-follow-its-pin' },
        { icon: 'gauge', title: 'بدّل قبل الحد إن شئت', text: 'في خطتي Pro وMax يستطيع cc التبديل عند 98% بين الأدوار، بقراءة نسبة الاستخدام التي يمرّرها Claude Code أصلًا إلى أوامر شريط الحالة. متوقف افتراضيًا وبلا أي اتصال شبكي.', code: '"earlySwitch"', href: 'docs/configuration/#switching-before-the-limit' },
        { icon: 'lock', title: 'محلي وقابل للفحص ودون اتصال', text: 'Bash وPython، ولا شيء يُثبَّت عبر npm. لا اتصالات شبكية من تلقاء نفسه، ولا قياس عن بُعد، ولا يقرأ ملف بيانات اعتماد أبدًا. تُحفظ الحالة في ‎~/.claude-switch‎ بصلاحيات 600.', code: 'bash test/run-all.sh', href: 'docs/security/' },
      ],
    },
    start: {
      label: '03 — البداية السريعة',
      title: 'خمس دقائق،\nوحساباتك أنت.',
      text: 'تحتاج إلى Claude Code مسجّل الدخول إلى حسابك الأول، وPython 3.6 أو أحدث، وأي bash بدءًا من 3.2. كل حساب تضيفه هو حساب تملكه وتسجّل الدخول إليه بنفسك.',
      fullGuide: 'دليل الإعداد الكامل، بما فيه VS Code',
      copy: 'نسخ',
      copied: 'تم النسخ',
      copyFail: 'حدّد الشيفرة وانسخها يدويًا.',
      steps: [
        { title: 'التثبيت', note: 'ينسخ خمسة أوامر إلى ‎~/.local/bin‎. أو أضفه كإضافة لـ Claude Code وشغّل ‎/cc-setup‎.', code: install },
        { title: 'اعرض الحساب الذي تستخدمه أصلًا', note: 'لا شيء يُضبط: يجده cc بنفسه ويعلّمه بـ (default).', code: 'cc status' },
        { title: 'أضف حسابًا آخر تملكه', note: 'يطلب بريد ذلك الحساب، ويفتح صفحة تسجيل الدخول، ويرفض حسابًا أضفته من قبل.', code: 'cc add work' },
        { title: 'اربط مجلدًا بحساب', note: 'من داخل المجلد، أو بالخيارات من سكربت. اختر معنى بلوغ الحد لذلك المجلد.', code: 'cd ~/work/acme\ncc pin\n\n# or, without the menu:\ncc pin ~/work/acme --account acme --fallback personal' },
        { title: 'شغّل cc بدلًا من claude', note: 'في المجلد المربوط يبدأ على حساب الربط. وفي غيره يستخدم الحساب التالي الذي لديه رصيد.', code: 'cc' },
      ],
      handoffTitle: 'ماذا يحدث عند بلوغ الحد',
      handoff: ['يكتب Claude Code الحد في نص الجلسة', 'ينهي cc التشغيل ويسجّل موعد إعادة ضبط الحساب', 'يُنسخ نص الجلسة إلى الحساب التالي المسموح به، على قرصك', 'يعيد claude --resume فتح الجلسة نفسها هناك'],
      handoffNote: 'في المجلد المربوط، «الحساب التالي المسموح به» هو ما يسمح به الربط فقط: بديله، أو لا شيء.',
    },
    who: {
      label: '04 — لمن هذه الأداة',
      title: 'لمن ينتمي Claude Code لديهم\nإلى أكثر من جهة.',
      cases: [
        { title: 'المستقلون مع عدة عملاء', text: 'كل مجلد عميل مربوط بمقعد ذلك العميل. تبقى مشاريعك على خطتك، ولا تُنسخ محادثة عميل أبدًا إلى حساب عميل آخر.' },
        { title: 'الموظفون بمقعد عمل وخطة شخصية', text: 'مستودعات العمل على المقعد، والمشاريع الجانبية على خطتك. لا يستهلك عمل عطلة الأسبوع حدّ الشركة، ولا يتسرب عمل الشركة إلى سجلك الشخصي.' },
        { title: 'الفرق التي توزّع المقاعد', text: 'ربط لكل مستودع، واختيار «توقّف وانتظر» حيث تمنع السياسة نقل المحادثة، ولا يُكتب أي شيء في المستودع لكي يعمل ذلك.' },
        { title: 'التشغيلات الطويلة التي يجب ألا تتوقف', text: 'في الطرفية، عندما يبلغ حساب تملكه حدّه، ينقل cc المحادثة إلى الحساب التالي ويكملها. خمس تبويبات على حساب واحد يبدّل كل منها من تلقاء نفسه.' },
      ],
      notTitle: 'ليست لك إذا',
      not: [
        'كان لديك حساب Claude واحد. لا يوجد ما يُفصل ولا ما يُنتقل إليه.',
        'كنت تريد رصيدًا أكبر. لا يستطيع cc رفع أي حد؛ يحتفظ كل حساب بحدوده.',
        'بلغت الحد في claude.ai داخل المتصفح. لا يمكن نقل محادثات الويب ولا حدودها.',
        'كنت تريد استخدام اشتراك من مزوّد آخر. لا يتواصل Claude Code إلا مع Anthropic.',
      ],
    },
    faq: { label: '05 — الأسئلة', title: 'قبل أن تثبّت.', text: 'ما يسأله الناس أولًا، بإجابات واضحة.' },
    final: { label: 'أبقِ كل حساب في مكانه', title: 'اربط مجلدك الأول\nالليلة.', text: 'خمس دقائق للتثبيت. حساباتك أنت، على جهازك أنت، ولا يُرسل شيء إلى أي مكان.', primary: 'ابدأ الآن', github: 'المصدر على GitHub' },
    footer: {
      text: 'حساب Claude Code واحد لكل مجلد مشروع، ومحادثة تنجو من بلوغ الحد.',
      docs: 'التوثيق',
      start: 'ابدأ الآن',
      privacy: 'الخصوصية',
      security: 'الأمان',
      changelog: 'سجل التغييرات',
      llms: 'llms.txt',
      license: 'رخصة MIT',
      disclaimer: 'مشروع مفتوح المصدر ومستقل، غير تابع لشركة Anthropic ولا معتمد منها. استخدم الحسابات التي تملكها فقط.',
      otherLanguage: 'Read in English',
    },
  },
}
