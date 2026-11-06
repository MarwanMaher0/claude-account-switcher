#!/usr/bin/env node
// Builds the site's pages from the repository's own Markdown so the two cannot drift.
// Runs before `astro dev` and `astro build` (npm predev/prebuild). Nothing it writes is committed:
//   src/content/docs/index.mdx         home page (layout here, text from README.md)
//   src/content/docs/docs/*.md         one page per entry in site.config.mjs
//   src/generated/home/*.md            README excerpts the home page imports
//   src/assets/generated/*             images referenced by those pages
// It fails when a section named in site.config.mjs is missing, or when a source links to a
// heading that does not exist, so a renamed heading breaks the build instead of the site.
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, posix, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import GithubSlugger from 'github-slugger'
import { base, branch, faq, groups, home, pages, repo, siteUrl } from '../site.config.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '../..')
const site = resolve(here, '..')
const out = {
  content: resolve(site, 'src/content/docs'),
  docs: resolve(site, 'src/content/docs/docs'),
  home: resolve(site, 'src/generated/home'),
  assets: resolve(site, 'src/assets/generated'),
  generated: resolve(site, 'src/generated'),
  public: resolve(site, 'public'),
}

const fail = (message) => {
  console.error(`sync-docs: ${message}`)
  process.exit(1)
}
const warnings = []

// ---------------------------------------------------------------------------
// Reading and splitting Markdown
// ---------------------------------------------------------------------------

const FENCE = /^\s*(```|~~~)/
const HEADING = /^(#{1,6})\s+(.+?)\s*#*\s*$/

/** Heading text as GitHub slugs it: inline code, emphasis and links reduced to their text. */
const plain = (text) =>
  text
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/(\*\*|__)(.*?)\1/g, '$2')
    .replace(/(\*|_)(.*?)\1/g, '$2')
    .trim()

/** Calls fn(line, index, inFence) for every line, tracking fenced code blocks. */
function eachLine(lines, fn) {
  let fence = null
  lines.forEach((line, i) => {
    const m = line.match(FENCE)
    if (m && (!fence || line.trim().startsWith(fence))) {
      fn(line, i, true)
      fence = fence ? null : m[1]
      return
    }
    fn(line, i, Boolean(fence))
  })
}

function headingsOf(lines) {
  const list = []
  eachLine(lines, (line, i, inFence) => {
    const m = !inFence && line.match(HEADING)
    if (m) list.push({ line: i, level: m[1].length, raw: m[2], text: plain(m[2]) })
  })
  return list
}

/** README's centred HTML header goes; its screenshot becomes a Markdown image. Rules go too. */
function clean(markdown) {
  const html = markdown
    .replace(/<div align="center">\s*<img src="([^"]+)" alt="([^"]*)"[^>]*>\s*<\/div>/g, (_, src, alt) => `![${alt}](${src})`)
    .replace(/<div align="center">[\s\S]*?<\/div>\n?/g, '')
  const lines = html.split('\n')
  const kept = []
  eachLine(lines, (line, _i, inFence) => {
    if (!inFence && /^\s*(---|\*\*\*|___)\s*$/.test(line)) return
    kept.push(line)
  })
  return kept.join('\n')
}

const sources = new Map()
/**
 * Loads a repository file once. `headings` keeps every heading of the original file with the
 * slug GitHub gives it, so links like CONFIG.md#auto-continue can be resolved; `placed` records
 * where each heading ended up on the site.
 */
function source(file) {
  if (sources.has(file)) return sources.get(file)
  const path = resolve(root, file)
  if (!existsSync(path)) fail(`${file} does not exist`)
  const raw = readFileSync(path, 'utf8').replace(/\r\n/g, '\n')
  const slugger = new GithubSlugger()
  const originalHeadings = headingsOf(raw.split('\n')).map((h) => ({ ...h, slug: slugger.slug(h.text) }))
  const lines = clean(raw).split('\n')
  const entry = { file, lines, headings: headingsOf(lines), original: originalHeadings, placed: new Map() }
  sources.set(file, entry)
  return entry
}

/**
 * Lines of one section. `#intro` is everything before the first H2 (without the H1). A named
 * section runs from its heading to the next heading of the same or a higher level.
 */
function section(src, name, { exclude = [], until } = {}) {
  let start, end, heading
  if (name === '#intro') {
    const firstH2 = src.headings.find((h) => h.level <= 2 && h.level > 1)
    const h1 = src.headings.find((h) => h.level === 1)
    start = h1 && (!firstH2 || h1.line < firstH2.line) ? h1.line + 1 : 0
    end = firstH2 ? firstH2.line : src.lines.length
  } else {
    heading = src.headings.find((h) => h.text === name)
    if (!heading) fail(`${src.file} has no heading "${name}" (named in site.config.mjs)`)
    const next = src.headings.find((h) => h.line > heading.line && h.level <= heading.level)
    start = heading.line
    end = next ? next.line : src.lines.length
  }
  const drop = new Set()
  for (const sub of exclude) {
    const h = src.headings.find((x) => x.text === sub && x.line > start && x.line < end)
    if (!h) fail(`${src.file}: "${sub}" is not inside "${name}"`)
    const next = src.headings.find((x) => x.line > h.line && x.level <= h.level)
    for (let i = h.line; i < Math.min(next ? next.line : end, end); i++) drop.add(i)
  }
  let lines = []
  for (let i = start; i < end; i++) if (!drop.has(i)) lines.push({ text: src.lines[i], index: i })
  if (until) {
    const stop = lines.findIndex((l) => l.text.includes(until))
    if (stop < 0) fail(`${src.file}: "${until}" not found in "${name}"`)
    lines = lines.slice(0, stop)
  }
  return { heading, lines }
}

/** Splits Markdown into blocks: paragraphs, list items, quotes, tables, code. */
function blocks(markdown) {
  const lines = markdown.split('\n')
  const result = []
  const isItem = (l) => /^([-*+]|\d+\.)\s/.test(l)
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if (!line.trim()) { i++; continue }
    const take = (type, test) => {
      const start = i
      i++
      while (i < lines.length && test(lines[i])) i++
      result.push({ type, text: lines.slice(start, i).join('\n') })
    }
    const fence = line.match(FENCE)
    if (fence) {
      const start = i
      i++
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) i++
      i++
      result.push({ type: 'code', text: lines.slice(start, i).join('\n') })
    } else if (HEADING.test(line)) {
      result.push({ type: 'heading', text: line })
      i++
    } else if (isItem(line)) {
      const start = i
      i++
      while (i < lines.length) {
        const l = lines[i]
        if (/^\s+\S/.test(l)) { i++; continue }
        if (!l.trim() && i + 1 < lines.length && /^\s+\S/.test(lines[i + 1])) { i++; continue }
        break
      }
      result.push({ type: 'item', text: lines.slice(start, i).join('\n') })
    } else if (line.startsWith('>')) {
      take('quote', (l) => l.startsWith('>'))
    } else if (line.startsWith('|')) {
      take('table', (l) => l.startsWith('|'))
    } else {
      take('para', (l) => l.trim() && !isItem(l) && !l.startsWith('>') && !HEADING.test(l) && !FENCE.test(l))
    }
  }
  return result
}

/** A list item or a quote as a plain paragraph, for quoting it out of context. */
function unwrap(block) {
  if (block.type === 'item') {
    const [first, ...rest] = block.text.split('\n')
    return [first.replace(/^([-*+]|\d+\.)\s+/, ''), ...rest.map((l) => l.replace(/^\s{1,4}/, ''))].join('\n')
  }
  if (block.type === 'quote') {
    return block.text.split('\n').map((l) => l.replace(/^>\s?/, '')).filter((l) => !/^\[!\w+\]\s*$/.test(l)).join('\n')
  }
  return block.text
}

function shiftHeadings(lines, delta) {
  if (!delta) return lines
  const outLines = []
  eachLine(lines, (line, _i, inFence) => {
    const m = !inFence && line.match(HEADING)
    outLines.push(m ? `${'#'.repeat(Math.min(6, Math.max(2, m[1].length + delta)))} ${m[2]}` : line)
  })
  return outLines
}

/** GitHub alerts become Starlight asides. */
function alertsToAsides(markdown) {
  const kinds = { NOTE: 'note', TIP: 'tip', IMPORTANT: 'caution', WARNING: 'caution', CAUTION: 'danger' }
  const titles = { NOTE: 'Note', TIP: 'Tip', IMPORTANT: 'Important', WARNING: 'Warning', CAUTION: 'Caution' }
  const lines = markdown.split('\n')
  const result = []
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/)
    if (!m) { result.push(lines[i]); continue }
    const body = []
    while (i + 1 < lines.length && lines[i + 1].startsWith('>')) body.push(lines[++i].replace(/^>\s?/, ''))
    result.push(`:::${kinds[m[1]]}[${titles[m[1]]}]`, ...body, ':::')
  }
  return result.join('\n')
}

// ---------------------------------------------------------------------------
// Assembling pages
// ---------------------------------------------------------------------------

const pageUrl = (slug) => `${base}docs/${slug}/`
const pageBySlug = new Map(pages.map((p) => [p.slug, p]))

/**
 * Turns one source entry into Markdown for a page and records, for every heading it carries,
 * the original heading so links can be pointed at the right page and anchor.
 */
function chunk(entry) {
  const src = source(entry.file)
  if (!entry.section) {
    const h1 = src.headings.find((h) => h.level === 1)
    const lines = src.lines.map((text, index) => ({ text, index })).filter((l) => !h1 || l.index !== h1.line)
    return { src, heading: null, lines: lines.map((l) => l.text), indexes: lines.map((l) => l.index), titleHeading: h1, delta: 0 }
  }
  const { heading, lines } = section(src, entry.section, entry)
  if (entry.title) {
    const body = lines.slice(1)
    return { src, heading, lines: body.map((l) => l.text), indexes: body.map((l) => l.index), titleHeading: heading, delta: 2 - (heading.level + 1) }
  }
  return { src, heading, lines: lines.map((l) => l.text), indexes: lines.map((l) => l.index), titleHeading: null, delta: 2 - heading.level }
}

/** Maps a heading line of the cleaned source back to the heading of the original file. */
function originalOf(src, cleanedHeading) {
  const nth = src.headings.filter((h) => h.text === cleanedHeading.text && h.line < cleanedHeading.line).length
  return src.original.filter((h) => h.text === cleanedHeading.text)[nth]
}

/** Records where each heading of a chunk lands: page URL plus the slug the page will give it. */
function place(c, url, slugger) {
  if (c.titleHeading) {
    const o = originalOf(c.src, c.titleHeading)
    if (o) c.src.placed.set(o.slug, { url, anchor: null })
  }
  for (const h of c.src.headings) {
    const pos = c.indexes.indexOf(h.line)
    if (pos < 0) continue
    const o = originalOf(c.src, h)
    const anchor = slugger.slug(h.text)
    if (o && !c.src.placed.has(o.slug)) c.src.placed.set(o.slug, { url, anchor })
  }
}

// Pass 1: build every page body and learn where every heading lives.
const built = []
for (const page of pages.filter((p) => p.sources)) {
  const slugger = new GithubSlugger()
  const chunks = page.sources.map(chunk)
  for (const c of chunks) place(c, pageUrl(page.slug), slugger)
  built.push({ page, chunks })
}
// Whole-file sources own their file; README.md itself maps to the home page.
const fileHome = new Map([['README.md', base]])
for (const page of pages) for (const s of page.sources || []) if (!s.section) fileHome.set(s.file, pageUrl(page.slug))

// Home sections claim the README headings they show, unless a docs page already does.
const homeSlugger = new GithubSlugger()
const homeAnchors = home.sections.map((s) => homeSlugger.slug(s.heading))
home.sections.forEach((s, i) => {
  if (s.from.section === '#intro' || s.from.until) return
  const src = source(s.from.file)
  const h = src.headings.find((x) => x.text === s.from.section)
  const o = h && originalOf(src, h)
  if (o && !src.placed.has(o.slug)) src.placed.set(o.slug, { url: base, anchor: homeAnchors[i] })
})

// FAQ question anchors, used for the "From …" links back to the source.
const faqSlugger = new GithubSlugger()
const faqAnchors = faq.map((f) => faqSlugger.slug(plain(f.q)))

// ---------------------------------------------------------------------------
// Links and images
// ---------------------------------------------------------------------------

const blobUrl = (path, anchor) => {
  const kind = existsSync(resolve(root, path)) && statSync(resolve(root, path)).isDirectory() ? 'tree' : 'blob'
  return `${repo}/${kind}/${branch}/${path}${anchor ? `#${anchor}` : ''}`
}
const target = ({ url, anchor }, currentUrl) => (url === currentUrl && anchor ? `#${anchor}` : `${url}${anchor ? `#${anchor}` : ''}`)

/** Where a link to `file#anchor` in the repository should point on the site. */
function resolveLink(file, anchor, from) {
  const src = sources.get(file) || (fileHome.has(file) || pages.some((p) => (p.sources || []).some((s) => s.file === file)) ? source(file) : null)
  if (!src) return null
  if (!anchor) return fileHome.has(file) ? { url: fileHome.get(file), anchor: null } : null
  const slug = decodeURIComponent(anchor).toLowerCase()
  if (!src.original.some((h) => h.slug === slug)) fail(`${from} links to ${file}#${anchor}, but ${file} has no such heading`)
  return src.placed.get(slug) || { external: blobUrl(file, anchor) }
}

let imageCount = 0
/** Rewrites every Markdown link and image of text that came from `file`, for a page at `outFile`. */
function rewrite(markdown, file, currentUrl, outFile) {
  const lines = markdown.split('\n')
  const result = []
  eachLine(lines, (line, _i, inFence) => {
    if (inFence) { result.push(line); return }
    result.push(line.replace(/(!?)\[((?:[^\][]|\[[^\]]*\])*)\]\(([^)\s]+)(\s+"[^"]*")?\)/g, (whole, bang, text, href, title = '') => {
      if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return whole
      const [path, anchor] = href.split('#')
      const repoPath = path ? posix.normalize(posix.join(posix.dirname(file), path)) : file
      if (bang) {
        const abs = resolve(root, repoPath)
        if (!existsSync(abs)) fail(`${file} shows a missing image ${href}`)
        mkdirSync(out.assets, { recursive: true })
        copyFileSync(abs, resolve(out.assets, posix.basename(repoPath)))
        imageCount++
        const rel = posix.relative(posix.dirname(outFile), posix.join(site, 'src/assets/generated', posix.basename(repoPath)))
        return `![${text}](${rel.startsWith('.') ? rel : `./${rel}`}${title})`
      }
      const hit = resolveLink(repoPath, anchor, file)
      if (hit && hit.external) return `[${text}](${hit.external}${title})`
      if (hit) return `[${text}](${target(hit, currentUrl)}${title})`
      if (!existsSync(resolve(root, repoPath))) warnings.push(`${file} links to ${repoPath}, which is not in this checkout; linked on GitHub`)
      return `[${text}](${blobUrl(repoPath, anchor)}${title})`
    }))
  })
  return result.join('\n')
}

/** Links in site.config.mjs text name pages by slug: [VS Code](vscode#anchor). */
function rewriteSlugLinks(markdown, where) {
  return markdown.replace(/\]\(([a-z0-9-]+)(#[^)]+)?\)/g, (_, slug, hash = '') => {
    if (!pageBySlug.has(slug)) fail(`${where} links to unknown page "${slug}"`)
    return `](${pageUrl(slug)}${hash})`
  })
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

for (const dir of [out.docs, out.home, out.assets]) rmSync(dir, { recursive: true, force: true })
rmSync(resolve(out.content, 'index.mdx'), { force: true })
for (const dir of [out.docs, out.home]) mkdirSync(dir, { recursive: true })

const yaml = (value) => JSON.stringify(value)
const sourceLink = (file, heading) => {
  const o = heading ? originalOf(source(file), heading) : null
  return `[${file}${heading ? ` › ${heading.text}` : ''}](${blobUrl(file, o ? o.slug : null)})`
}
const footer = (refs) => `\n\n---\n\n<small class="source-note">Generated from ${refs.join(', ')}. Edit the source in the repository; this page is rebuilt from it.</small>\n`

function frontmatter(page, editFile) {
  return ['---', `title: ${yaml(page.title)}`, `description: ${yaml(page.description)}`, `editUrl: ${yaml(`${repo}/edit/${branch}/${editFile}`)}`, '---', ''].join('\n')
}

// Docs pages.
for (const { page, chunks } of built) {
  const outFile = resolve(out.docs, `${page.slug}.md`)
  const url = pageUrl(page.slug)
  const parts = chunks.map((c) => rewrite(alertsToAsides(shiftHeadings(c.lines, c.delta).join('\n').trim()), c.src.file, url, outFile))
  if (page.tip) parts.push(`:::tip\n${rewriteSlugLinks(page.tip.text, page.slug)}\n:::`)
  const refs = chunks.map((c) => sourceLink(c.src.file, c.heading))
  writeFileSync(outFile, `${frontmatter(page, page.sources[0].file)}\n${parts.join('\n\n')}${footer(refs)}`)
}

// FAQ.
{
  const page = pages.find((p) => p.faq)
  const outFile = resolve(out.docs, `${page.slug}.md`)
  const url = pageUrl(page.slug)
  const entries = faq.map((item, n) => {
    const picks = [].concat(item.from)
    const answer = picks.map((pick) => {
      const src = source(pick.file)
      const { heading, lines } = section(src, pick.section)
      const body = (heading ? lines.slice(1) : lines).map((l) => l.text).join('\n')
      let text
      if (pick.match) {
        const block = blocks(body).find((b) => b.text.includes(pick.match))
        if (!block) fail(`FAQ "${item.q}": "${pick.match}" not found in ${pick.file} › ${pick.section}`)
        text = unwrap(block)
      } else {
        text = body.trim()
      }
      return rewrite(alertsToAsides(text), pick.file, url, outFile)
    })
    const first = [].concat(item.from)[0]
    const src = source(first.file)
    const h = first.section === '#intro' ? null : src.headings.find((x) => x.text === first.section)
    const o = h ? originalOf(src, h) : null
    const where = o ? src.placed.get(o.slug) : { url: fileHome.get(first.file) || base, anchor: null }
    const label = h ? plain(h.raw) : first.file
    const pageTitle = where.url === base ? 'Home' : pages.find((p) => pageUrl(p.slug) === where.url)?.title
    if (!pageTitle) fail(`FAQ "${item.q}": ${first.file} › ${first.section} is not shown on any page`)
    const fromLink = `[${pageTitle}${label && label !== pageTitle && label !== first.file ? ` › ${label}` : ''}](${target(where, url)})`
    return { anchor: faqAnchors[n], md: `## ${item.q}\n\n${answer.join('\n\n')}\n\n<small class="faq-source">From ${fromLink}</small>` }
  })
  const files = [...new Set(faq.flatMap((f) => [].concat(f.from).map((p) => p.file)))]
  writeFileSync(
    outFile,
    `${frontmatter(page, 'site/site.config.mjs')}\n${entries.map((e) => e.md).join('\n\n')}${footer(files.map((f) => sourceLink(f)))}`,
  )
}

// Home: excerpts as Markdown files, imported by a generated MDX page.
{
  const imports = []
  const body = []
  home.sections.forEach((s, i) => {
    const src = source(s.from.file)
    const { heading, lines } = section(src, s.from.section, s.from)
    const text = (heading ? lines.slice(1) : lines).map((l) => l.text).join('\n').trim()
    const name = `Section${i}`
    const outFile = resolve(out.home, `${i}.md`)
    writeFileSync(outFile, `${rewrite(alertsToAsides(text), s.from.file, base, outFile)}\n`)
    imports.push(`import ${name} from '../../generated/home/${i}.md'`)
    body.push(`## ${s.heading}`, '', `<div class="home-excerpt">`, `<${name} />`, `</div>`, '')
    if (s.more) body.push(`<LinkButton href="${pageUrl(s.more.slug)}" variant="secondary" icon="right-arrow">${s.more.text}</LinkButton>`, '')
    if (i === 1) {
      body.push('## Find your way', '', '<CardGrid>')
      for (const p of pages) body.push(`  <LinkCard title=${yaml(p.sidebarLabel || p.title)} description=${yaml(p.description)} href="${pageUrl(p.slug)}" />`)
      body.push('</CardGrid>', '')
    }
  })
  // README's bold tagline is the hero's tagline.
  const tagline = readFileSync(resolve(root, 'README.md'), 'utf8').match(/^\*\*(.+)\*\*\s*$/m)
  if (!tagline) fail('README.md has no bold tagline line')
  const mdx = [
    '---',
    `title: ${yaml(home.title)}`,
    `description: ${yaml(home.description)}`,
    'template: splash',
    'editUrl: false',
    'pagefind: true',
    'hero:',
    `  title: ${yaml(home.title)}`,
    `  tagline: ${yaml(tagline[1])}`,
    '  actions:',
    `    - text: Get started`,
    `      link: ${pageUrl('get-started')}`,
    '      icon: right-arrow',
    `    - text: One account per folder`,
    `      link: ${pageUrl('separate-projects')}`,
    '      variant: secondary',
    `    - text: View on GitHub`,
    `      link: ${repo}`,
    '      icon: external',
    '      variant: minimal',
    '---',
    '',
    "import { CardGrid, LinkCard, LinkButton } from '@astrojs/starlight/components'",
    ...imports,
    '',
    ...body,
    `<small class="source-note">Generated from [README.md](${blobUrl('README.md')}). Edit the source in the repository; this page is rebuilt from it.</small>`,
    '',
  ].join('\n')
  writeFileSync(resolve(out.content, 'index.mdx'), mdx)
}

writeFileSync(
  resolve(out.content, '404.md'),
  [
    '---',
    'title: Page not found',
    'template: splash',
    'editUrl: false',
    'pagefind: false',
    'draft: true',
    'hero:',
    '  title: Page not found',
    '  tagline: This page does not exist. Use search, or start from one of these.',
    '  actions:',
    '    - text: Get started',
    `      link: ${pageUrl('get-started')}`,
    '      icon: right-arrow',
    '    - text: Home',
    `      link: ${base}`,
    '      variant: secondary',
    '---',
    '',
  ].join('\n'),
)

const pluginPath = resolve(root, '.claude-plugin/plugin.json')
if (!existsSync(pluginPath)) fail('.claude-plugin/plugin.json does not exist')
const plugin = JSON.parse(readFileSync(pluginPath, 'utf8'))
const readme = readFileSync(resolve(root, 'README.md'), 'utf8')
const testBadge = readme.match(/tests-(\d+)%20checks/)
const facts = {
  version: plugin.version,
  tests: testBadge ? Number(testBadge[1]) : null,
  commands: ['cc', 'cc-detect', 'cc-watch', 'cc-vscode', 'cc-claude-wrapper'],
  license: 'MIT',
}
mkdirSync(out.generated, { recursive: true })
writeFileSync(resolve(out.generated, 'facts.json'), `${JSON.stringify(facts, null, 2)}\n`)

const intro = [
  '# cc-switch (claude-account-switcher)',
  '',
  '> cc-switch is an MIT-licensed launcher for Claude Code on Linux and macOS. It pins each project folder to the Claude Code account it belongs to and moves a session to the next account you own when one reaches its usage limit.',
  '',
  `Current version: ${facts.version}. The tool does not pool, share or bypass accounts or limits, and it cannot raise any limit.`,
  '',
  `Landing page: ${siteUrl}`,
  `Arabic landing page: ${siteUrl}ar/`,
  `Source repository: ${repo}`,
  '',
]
const llms = [...intro, '## Documentation', '']
for (const group of groups) {
  llms.push(`### ${group.label}`, '')
  for (const page of pages.filter((p) => p.group === group.id)) {
    llms.push(`- [${page.sidebarLabel || page.title}](${siteUrl}docs/${page.slug}/): ${page.description}`)
  }
  llms.push('')
}
llms.push(`## Full text`, '', `- [llms-full.txt](${siteUrl}llms-full.txt): every documentation page in one Markdown file.`, '')
mkdirSync(out.public, { recursive: true })
writeFileSync(resolve(out.public, 'llms.txt'), llms.join('\n'))

const full = [...intro]
for (const page of pages) {
  const pagePath = resolve(out.docs, `${page.slug}.md`)
  if (!existsSync(pagePath)) continue
  full.push('---', '', `# ${page.title}`, '', `Source: ${siteUrl}docs/${page.slug}/`, '', readFileSync(pagePath, 'utf8').replace(/^---[\s\S]*?---\n/, ''), '')
}
writeFileSync(resolve(out.public, 'llms-full.txt'), full.join('\n'))

for (const w of [...new Set(warnings)]) console.warn(`sync-docs: note: ${w}`)
console.log(`sync-docs: ${pages.length} pages + home from ${sources.size} source files, ${faq.length} FAQ answers, ${imageCount} image reference(s)`)
