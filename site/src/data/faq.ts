export type Locale = 'en' | 'ar'

export interface Faq {
  question: string
  answer: string
}

export const faqs: Record<Locale, Faq[]> = {
  en: [
    {
      question: 'Do I need more than one Claude account?',
      answer: 'Yes. cc-switch is for people who already have two or more Claude Code accounts of their own, for example an employer’s seat and a personal plan, or seats from several clients. With one account there is nothing to separate and nothing to switch to.',
    },
    {
      question: 'Does it pool, share or bypass accounts or limits?',
      answer: 'No. Each account must be your own and signed in by you in your own browser. Every account keeps its own limits, cc cannot raise any limit, and it never reads, copies or prints credentials. It only chooses which of your own signed-in accounts a session starts on.',
    },
    {
      question: 'How does a pin keep a client’s work off my personal account?',
      answer: 'cc pin ties a folder, and all of its subfolders, to one account. A pinned account is never picked outside its folders, a company account can never fall back to another company’s account, and the only fallback a pin may name is an account that is not pinned anywhere, normally your own default. Pins live in ~/.claude-switch/pins.json; nothing is written into the repository.',
    },
    {
      question: 'What happens to the conversation when an account hits its limit?',
      answer: 'In a terminal, cc ends the run, records when the account resets, copies the session transcript to the next allowed account on your own machine, resumes the same session there and, by default, sends “Continue where you left off.” for you. If a pin says “Stop and wait for reset”, cc stops instead and shows when the account frees up.',
    },
    {
      question: 'Does it work with the Claude panel in VS Code?',
      answer: 'Yes. cc vscode on sets one user setting, claudeCode.claudeProcessWrapper, and installs a small companion extension built on your machine, so each window runs the panel on its folder’s account and shows it in the status bar. After a limit, new chats start on the next allowed account; a chat that is already running keeps its account until you start a new one. Install the plugin in each account so limits are recorded the moment they happen.',
    },
    {
      question: 'Does it send anything anywhere?',
      answer: 'The tool makes no network calls of its own and has no telemetry. The one exception is the optional live usage check, which runs your own claude -p /usage for your own accounts; it is on by default for cc status and can be turned off with CC_LIVE_CHECK=0 or "liveCheck": false. Hooks never run it. Transcripts are only ever copied between folders on your own disk.',
    },
    {
      question: 'My employer forbids moving chats. Can I still use it?',
      answer: 'Yes. Choose “Stop and wait for reset” when you pin the folder. Then a limit on that account stops the session rather than copying the chat anywhere. Falling back to your personal account would copy that chat into your personal account’s folder on this machine, so if even that is not allowed, pick stop.',
    },
    {
      question: 'Can it switch at 98% instead of at the wall?',
      answer: 'Optionally. On Pro and Max plans Claude Code already reports usage to status line commands; cc can read it from there and switch between turns once an account passes a threshold. It is off by default, adds no network call, and only applies to sessions started by cc in a terminal.',
    },
    {
      question: 'What does it run on?',
      answer: 'Linux and macOS, with Claude Code signed in to your first account, any bash from 3.2 up (including the one macOS ships) and Python 3.6 or newer. It installs five commands into ~/.local/bin and changes nothing else on your machine.',
    },
    {
      question: 'Is this an official Anthropic tool?',
      answer: 'No. cc-switch is an independent open-source project under the MIT licence, not affiliated with or endorsed by Anthropic. Claude Code remains the only thing that talks to Anthropic, using your own accounts’ logins.',
    },
  ],
  ar: [
    {
      question: 'هل أحتاج إلى أكثر من حساب Claude واحد؟',
      answer: 'نعم. صُمم cc-switch لمن لديهم حسابان أو أكثر في Claude Code يملكونها بأنفسهم، مثل مقعد من جهة العمل وخطة شخصية، أو مقاعد من عدة عملاء. مع حساب واحد لا يوجد ما يُفصل ولا ما يُنتقل إليه.',
    },
    {
      question: 'هل يجمع الحسابات أو يشاركها أو يتجاوز حدودها؟',
      answer: 'لا. يجب أن يكون كل حساب ملكك أنت، وأن تسجّل الدخول إليه بنفسك في متصفحك. يحتفظ كل حساب بحدوده الخاصة، ولا يستطيع cc رفع أي حد، ولا يقرأ بيانات الاعتماد أو ينسخها أو يطبعها أبدًا. كل ما يفعله هو اختيار أي حساباتك المسجّلة تبدأ عليه الجلسة.',
    },
    {
      question: 'كيف يُبقي الربط عمل العميل بعيدًا عن حسابي الشخصي؟',
      answer: 'يربط الأمر cc pin مجلدًا، بكل مجلداته الفرعية، بحساب واحد. لا يُختار الحساب المربوط أبدًا خارج مجلداته، ولا يمكن لحساب شركة أن يرجع إلى حساب شركة أخرى، والبديل الوحيد الذي يجوز للربط تسميته هو حساب غير مربوط في أي مكان، وهو عادةً حسابك الافتراضي. تُحفظ عمليات الربط في ‎~/.claude-switch/pins.json‎ ولا يُكتب أي شيء داخل المستودع.',
    },
    {
      question: 'ماذا يحدث للمحادثة عندما يبلغ حساب حدّه؟',
      answer: 'في الطرفية، ينهي cc التشغيل، ويسجّل موعد إعادة ضبط الحساب، وينسخ نص الجلسة إلى الحساب التالي المسموح به على جهازك، ويستأنف الجلسة نفسها هناك، ويرسل افتراضيًا رسالة «أكمل من حيث توقفت» نيابةً عنك. أما إذا كان الربط يقول «توقّف وانتظر إعادة الضبط»، فيتوقف cc ويعرض متى يتحرر الحساب.',
    },
    {
      question: 'هل يعمل مع لوحة Claude في VS Code؟',
      answer: 'نعم. يضبط الأمر cc vscode on إعدادًا واحدًا للمستخدم، claudeCode.claudeProcessWrapper، ويثبّت امتدادًا مرافقًا صغيرًا يُبنى على جهازك، فتعمل كل نافذة على حساب مجلدها ويظهر اسمه في شريط الحالة. بعد بلوغ حد، تبدأ المحادثات الجديدة على الحساب التالي المسموح به، وتبقى المحادثة الجارية على حسابها حتى تبدأ محادثة جديدة. ثبّت الإضافة في كل حساب حتى يُسجَّل الحد لحظة حدوثه.',
    },
    {
      question: 'هل يرسل أي شيء إلى أي مكان؟',
      answer: 'لا يجري الأداة أي اتصال شبكي من تلقاء نفسها ولا تحتوي على أي قياس عن بُعد. الاستثناء الوحيد هو فحص الاستخدام المباشر الاختياري، الذي يشغّل أمر claude -p /usage الخاص بك لحساباتك أنت؛ وهو مفعّل افتراضيًا في cc status ويمكن إيقافه بـ CC_LIVE_CHECK=0 أو "liveCheck": false. لا تشغّله الخطافات أبدًا. ولا تُنسخ نصوص الجلسات إلا بين مجلدات على قرصك.',
    },
    {
      question: 'جهة عملي تمنع نقل المحادثات. هل يمكنني استخدامه؟',
      answer: 'نعم. اختر «توقّف وانتظر إعادة الضبط» عند ربط المجلد. عندها يوقف بلوغُ الحد الجلسةَ بدلًا من نسخ المحادثة إلى أي مكان. أما الرجوع إلى حسابك الشخصي فينسخ تلك المحادثة إلى مجلد حسابك الشخصي على هذا الجهاز، فإن كان حتى هذا غير مسموح، فاختر التوقف.',
    },
    {
      question: 'هل يمكنه التبديل عند 98% بدلًا من الانتظار حتى الحد؟',
      answer: 'اختياريًا. في خطتي Pro وMax يمرّر Claude Code نسبة الاستخدام إلى أوامر شريط الحالة، ويستطيع cc قراءتها من هناك والتبديل بين الأدوار بمجرد تجاوز الحساب عتبة معيّنة. الخيار متوقف افتراضيًا، ولا يضيف أي اتصال شبكي، ولا ينطبق إلا على الجلسات التي يبدأها cc في الطرفية.',
    },
    {
      question: 'على ماذا يعمل؟',
      answer: 'على لينكس وmacOS، مع Claude Code مسجّل الدخول إلى حسابك الأول، وأي إصدار من bash بدءًا من 3.2 (بما فيه الإصدار المرفق مع macOS)، وPython 3.6 أو أحدث. يثبّت خمسة أوامر في ‎~/.local/bin‎ ولا يغيّر أي شيء آخر على جهازك.',
    },
    {
      question: 'هل هذه أداة رسمية من Anthropic؟',
      answer: 'لا. cc-switch مشروع مفتوح المصدر ومستقل برخصة MIT، وليس تابعًا لشركة Anthropic ولا معتمدًا منها. يبقى Claude Code هو الوحيد الذي يتواصل مع Anthropic، مستخدمًا تسجيلات دخول حساباتك أنت.',
    },
  ],
}
