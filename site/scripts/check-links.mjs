#!/usr/bin/env node
import { readFile, readdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { base, repo, siteOrigin } from '../site.config.mjs'

const siteDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const distDir = path.join(siteDir, process.argv[2] ?? 'dist')
const basePath = base.endsWith('/') ? base : `${base}/`
const repoRoot = path.resolve(siteDir, '..')
const repoBlob = new RegExp(`^${repo.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/(?:blob|tree)/[^/]+/(.+)$`)

if (!existsSync(distDir)) {
  console.error(`check-links: ${path.relative(siteDir, distDir)} does not exist. Run "npm run build" first.`)
  process.exit(1)
}

async function walk(dir) {
  const out = []
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...(await walk(full)))
    else if (entry.name.endsWith('.html')) out.push(full)
  }
  return out
}

const decode = (s) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')

function collectIds(html) {
  const ids = new Set()
  for (const m of html.matchAll(/\s(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) ids.add(decode(m[1] ?? m[2]))
  return ids
}

function collectRefs(html) {
  const refs = []
  const stripped = html
    .replace(/<script\b([^>]*)>[\s\S]*?<\/script>/gi, '<script$1></script>')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
  for (const m of stripped.matchAll(/<(a|link|img|script|source|iframe)\b([^>]*)>/gi)) {
    const tag = m[1].toLowerCase()
    const attrs = m[2]
    const attr = tag === 'a' || tag === 'link' ? 'href' : 'src'
    const am = attrs.match(new RegExp(`\\s${attr}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i'))
    if (am) refs.push({ tag, url: decode(am[1] ?? am[2]) })
    const sm = attrs.match(/\ssrcset\s*=\s*(?:"([^"]*)"|'([^']*)')/i)
    if (sm) {
      for (const part of decode(sm[1] ?? sm[2]).split(',')) {
        const u = part.trim().split(/\s+/)[0]
        if (u) refs.push({ tag, url: u })
      }
    }
  }
  return refs
}

function resolveTarget(pathname) {
  if (!pathname.startsWith(basePath) && pathname !== basePath.slice(0, -1)) return { outside: true }
  let rel = decodeURIComponent(pathname.slice(basePath.length))
  const candidates = []
  if (rel === '' || rel.endsWith('/')) candidates.push(path.join(rel, 'index.html'))
  else {
    candidates.push(rel)
    if (!path.extname(rel)) candidates.push(path.join(rel, 'index.html'), `${rel}.html`)
  }
  for (const c of candidates) {
    const full = path.join(distDir, c)
    if (full.startsWith(distDir) && existsSync(full)) return { file: full }
  }
  return { file: null }
}

const files = await walk(distDir)
const pages = new Map()
for (const file of files) {
  const html = await readFile(file, 'utf8')
  pages.set(file, { html, ids: collectIds(html) })
}

const errors = []
const warnings = []
let checked = 0
let external = 0

for (const [file, { html }] of pages) {
  const pageRel = path.relative(distDir, file)
  const pageUrl = new URL(`https://site.invalid${basePath}${pageRel.replace(/index\.html$/, '')}`)
  for (const { tag, url } of collectRefs(html)) {
    if (!url || /^(mailto:|tel:|javascript:|data:)/i.test(url)) continue
    let target
    try {
      target = new URL(url, pageUrl)
    } catch {
      errors.push(`${pageRel}: <${tag}> malformed URL "${url}"`)
      continue
    }
    if (target.origin !== 'https://site.invalid') {
      external++
      const blob = target.href.split('#')[0].match(repoBlob)
      if (blob && !existsSync(path.join(repoRoot, decodeURIComponent(blob[1])))) {
        warnings.push(`${pageRel}: repository link to missing file "${blob[1]}"`)
      }
      continue
    }
    checked++
    const resolved = resolveTarget(target.pathname)
    if (resolved.outside) {
      errors.push(`${pageRel}: <${tag}> "${url}" points outside the site base ${basePath}`)
      continue
    }
    if (!resolved.file) {
      errors.push(`${pageRel}: <${tag}> "${url}" has no matching file in ${path.basename(distDir)}/`)
      continue
    }
    const hash = decodeURIComponent(target.hash.slice(1))
    if (hash && tag === 'a' && hash !== '_top' && hash !== 'top') {
      const targetPage = pages.get(resolved.file)
      if (targetPage && !targetPage.ids.has(hash)) {
        errors.push(`${pageRel}: "${url}" points to #${hash}, which does not exist on ${path.relative(distDir, resolved.file)}`)
      }
    }
  }
}

function checkSiteReference(rawUrl, source) {
  let target
  try {
    target = new URL(rawUrl, `https://site.invalid${basePath}`)
  } catch {
    errors.push(`${source}: malformed URL "${rawUrl}"`)
    return
  }
  if (target.origin !== siteOrigin && target.origin !== 'https://site.invalid') return
  if (target.origin === siteOrigin) target = new URL(`${target.pathname}${target.search}${target.hash}`, 'https://site.invalid')
  if (!target.pathname.startsWith(basePath)) {
    errors.push(`${source}: "${rawUrl}" points outside the site base ${basePath}`)
    return
  }
  if (target.pathname.endsWith('.xml')) {
    const rel = decodeURIComponent(target.pathname.slice(basePath.length))
    const full = path.join(distDir, rel)
    if (!full.startsWith(distDir) || !existsSync(full)) errors.push(`${source}: "${rawUrl}" has no matching file in ${path.basename(distDir)}/`)
    return
  }
  checked++
  const resolved = resolveTarget(target.pathname)
  if (!resolved.file) {
    errors.push(`${source}: "${rawUrl}" has no matching file in ${path.basename(distDir)}/`)
    return
  }
  const hash = decodeURIComponent(target.hash.slice(1))
  if (hash && hash !== '_top' && hash !== 'top') {
    const targetPage = pages.get(resolved.file)
    if (targetPage && !targetPage.ids.has(hash)) errors.push(`${source}: "${rawUrl}" points to #${hash}, which does not exist on ${path.relative(distDir, resolved.file)}`)
  }
}

for (const name of ['sitemap.xml', 'sitemap-0.xml']) {
  const sitemap = path.join(distDir, name)
  if (!existsSync(sitemap)) {
    errors.push(`dist/${name} is missing`)
    continue
  }
  const xml = await readFile(sitemap, 'utf8')
  for (const m of xml.matchAll(/<loc>([^<]+)<\/loc>|href="([^"]+)"/g)) checkSiteReference(decode(m[1] ?? m[2]), `/${name}`)
}
const sitemapIndex = path.join(distDir, 'sitemap-index.xml')
if (existsSync(sitemapIndex)) {
  const xml = await readFile(sitemapIndex, 'utf8')
  for (const m of xml.matchAll(/<loc>([^<]+)<\/loc>|href="([^"]+)"/g)) checkSiteReference(decode(m[1] ?? m[2]), '/sitemap-index.xml')
}
const robots = path.join(distDir, 'robots.txt')
if (!existsSync(robots)) errors.push('dist/robots.txt is missing')
else {
  const text = await readFile(robots, 'utf8')
  for (const m of text.matchAll(/Sitemap:\s*(\S+)/g)) checkSiteReference(decode(m[1]), '/robots.txt')
}

for (const w of warnings) console.warn(`warning: ${w}`)
if (errors.length) {
  for (const e of errors) console.error(`broken: ${e}`)
  console.error(`check-links: ${errors.length} broken link(s) in ${files.length} page(s).`)
  process.exit(1)
}
console.log(`check-links: ${checked} internal link(s) and anchors OK across ${files.length} page(s); ${external} external link(s) not fetched.`)
