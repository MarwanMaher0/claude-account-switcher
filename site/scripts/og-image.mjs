// Renders the Open Graph images (1200x630) for both locales with satori + resvg.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import satori from 'satori'
import { Resvg } from '@resvg/resvg-js'

const here = dirname(fileURLToPath(import.meta.url))
const fontDir = resolve(here, 'og-fonts')
const outDir = resolve(here, '../public/og')
const facts = JSON.parse(readFileSync(resolve(here, '../src/generated/facts.json'), 'utf8'))

const font = (file) => readFileSync(resolve(fontDir, file))
const fonts = [
  { name: 'Display', data: font('BricolageGrotesque-Display.ttf'), weight: 800, style: 'normal' },
  { name: 'Text', data: font('BricolageGrotesque-Text.ttf'), weight: 500, style: 'normal' },
  { name: 'Arabic', data: font('IBMPlexSansArabic-Regular.ttf'), weight: 400, style: 'normal' },
  { name: 'Arabic', data: font('IBMPlexSansArabic-Bold.ttf'), weight: 700, style: 'normal' },
  { name: 'Mono', data: font('IBMPlexMono-Regular.ttf'), weight: 400, style: 'normal' },
]

const copy = {
  en: {
    dir: 'ltr',
    display: 'Display',
    text: 'Text',
    eyebrow: 'cc-switch  ·  for Claude Code',
    title: ['Each project folder on', 'its own Claude account.'],
    sub: ['Pin a folder to the account it belongs to. Keep working when one of your own accounts hits its limit.'],
    chips: ['MIT', 'No telemetry', `v${facts.version}`, 'Linux · macOS'],
  },
  ar: {
    dir: 'rtl',
    display: 'Arabic',
    text: 'Arabic',
    eyebrow: 'cc-switch  ·  Claude Code',
    title: ['كل مجلد مشروع على', 'حساب Claude الخاص به.'],
    sub: ['اربط مجلدًا بالحساب الذي ينتمي إليه.', 'وواصل العمل عندما يبلغ أحد حساباتك حدّه.'],
    chips: ['MIT', 'بلا قياس عن بُعد', `الإصدار ${facts.version}`, 'Linux · macOS'],
  },
}

const folders = [
  { path: '~/work/acme', acct: 'acme', color: '#ab9fff' },
  { path: '~/clients/globex', acct: 'globex', color: '#ff7fa1' },
  { path: '~/side/app', acct: 'personal', color: '#3fdc9a' },
]

const el = (type, props, ...children) => ({ type, props: { ...props, children: children.length === 1 ? children[0] : children } })

// satori measures right-to-left runs incorrectly; laying out one word per box in a
// row-reverse flex container sidesteps that and still wraps naturally.
const words = (text, style, gap, full) =>
  el(
    'div',
    { style: { display: 'flex', justifyContent: 'flex-end', ...(full ? { width: 1072 } : {}), columnGap: gap, ...style } },
    ...text
      .split(' ')
      .reverse()
      .map((w) => {
        const m = w.match(/^(.*?)([.،:؛!؟]+)$/u)
        return m ? el('div', { style: { display: 'flex' } }, el('span', {}, m[2]), el('span', {}, m[1])) : el('span', {}, w)
      }),
  )
const line = (text, style, rtl, gap, full = true) => (rtl ? words(text, style, gap, full) : el('span', { style }, text))

const mark = () =>
  el(
    'div',
    { style: { width: 44, height: 44, borderRadius: 12, background: '#0b7a55', display: 'flex', alignItems: 'center', justifyContent: 'center' } },
    el('div', { style: { width: 20, height: 4, background: '#f4f6f4', borderRadius: 2, transform: 'rotate(-35deg)' } }),
  )

function tree(locale) {
  const c = copy[locale]
  const rtl = c.dir === 'rtl'
  return el(
    'div',
    {
      style: {
        width: 1200,
        height: 630,
        display: 'flex',
        flexDirection: 'column',
        background: 'linear-gradient(135deg, #0b100d 0%, #0f1a14 60%, #0b2a1e 100%)',
        color: '#eef3ee',
        paddingTop: 48, paddingBottom: 48, paddingLeft: 64, paddingRight: 64,
        fontFamily: c.text,
        position: 'relative',
      },
    },
    el(
      'div',
      { style: { display: 'flex', width: 1072, alignItems: 'center', justifyContent: rtl ? 'flex-end' : 'flex-start', gap: 16, fontFamily: 'Mono', fontSize: 24, color: '#8fa397' } },
      ...(rtl ? [el('span', {}, c.eyebrow), mark()] : [mark(), el('span', {}, c.eyebrow)]),
    ),
    el(
      'div',
      { style: { display: 'flex', flexDirection: 'column', marginTop: 40, fontFamily: c.display, fontWeight: rtl ? 700 : 800, fontSize: rtl ? 68 : 74, lineHeight: rtl ? 1.3 : 1.02, letterSpacing: rtl ? 0 : -2.5 } },
      line(c.title[0], {}, rtl, 18),
      line(c.title[1], { color: '#3fdc9a' }, rtl, 18),
    ),
    el(
      'div',
      { style: { display: 'flex', flexDirection: 'column', marginTop: 20, fontSize: 27, lineHeight: 1.35, color: '#c7d2ca', maxWidth: rtl ? undefined : 800 } },
      ...c.sub.map((t) => line(t, {}, rtl, 8)),
    ),
    el(
      'div',
      { style: { display: 'flex', position: 'absolute', left: 64, top: 462, width: 1072, height: 120, justifyContent: 'space-between', alignItems: 'flex-end' } },
      ...(rtl ? [folderList(), chipList(c, rtl)] : [chipList(c, rtl), folderList()]),
    ),
  )
}

const chipList = (c, rtl) =>
  el(
    'div',
    { style: { display: 'flex', gap: 10, height: 40 } },
    ...(rtl ? [...c.chips].reverse() : c.chips).map((t) =>
      line(t, { fontFamily: rtl ? 'Arabic' : 'Mono', fontSize: 20, height: 40, display: 'flex', alignItems: 'center', padding: '0 14px', border: '2px solid #27332b', borderRadius: 999, color: '#c7d2ca' }, rtl, 6, false),
    ),
  )

const folderList = () =>
  el(
    'div',
    { style: { display: 'flex', flexDirection: 'column', gap: 6, width: 440, height: 120, fontFamily: 'Mono', fontSize: 18 } },
    ...folders.map((f) =>
      el(
        'div',
        { style: { display: 'flex', alignItems: 'center', height: 36, gap: 14, padding: '0 12px', background: '#121a15', border: '2px solid #27332b', borderRadius: 12 } },
        el('span', { style: { color: '#8fa397', width: 200 } }, f.path),
        el('span', { style: { color: '#5b675f' } }, '->'),
        el('span', { style: { width: 12, height: 12, borderRadius: 6, background: f.color } }),
        el('span', { style: { color: f.color } }, f.acct),
      ),
    ),
  )

mkdirSync(outDir, { recursive: true })
for (const locale of Object.keys(copy)) {
  const svg = await satori(tree(locale), { width: 1200, height: 630, fonts })
  const png = new Resvg(svg, { fitTo: { mode: 'width', value: 1200 } }).render().asPng()
  writeFileSync(resolve(outDir, `${locale}.png`), png)
  console.log(`og: wrote public/og/${locale}.png (${(png.length / 1024).toFixed(0)} KB)`)
}
