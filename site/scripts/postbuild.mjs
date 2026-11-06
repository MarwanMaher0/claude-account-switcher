// Writes sitemap.xml (and a copy at sitemap-0.xml, which Starlight's sitemap-index.xml points to)
// with en/ar/x-default alternates and priorities. AR docs are English fallbacks and are excluded.
import { readdirSync, statSync, writeFileSync } from 'node:fs'
import { join, relative, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { siteUrl } from '../site.config.mjs'

const dist = resolve(dirname(fileURLToPath(import.meta.url)), '../dist')

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) walk(p, out)
    else if (name === 'index.html') out.push(p)
  }
  return out
}

const allRoutes = walk(dist)
  .map((p) => relative(dist, dirname(p)).split('\\').join('/'))
  .map((r) => (r === '' ? '' : `${r}/`))
  .filter((r) => r !== '404/' && !r.startsWith('ar/docs/'))
  .sort()

const routable = new Set(
  walk(dist)
    .map((p) => relative(dist, dirname(p)).split('\\').join('/'))
    .map((r) => (r === '' ? '' : `${r}/`))
)

const stripAr = (r) => (r === 'ar/' ? '' : r.startsWith('ar/') ? r.slice(3) : r)
const toAr = (r) => `ar/${r}`
const arDocsFallback = (r) => r.startsWith('ar/docs/')

const entries = allRoutes.map((r) => {
  const en = stripAr(r)
  const ar = toAr(en)
  const alternates = []
  if (routable.has(en)) alternates.push(`    <xhtml:link rel="alternate" hreflang="en" href="${siteUrl}${en}"/>`)
  if (routable.has(ar) && !arDocsFallback(ar)) alternates.push(`    <xhtml:link rel="alternate" hreflang="ar" href="${siteUrl}${ar}"/>`)
  if (routable.has(en)) alternates.push(`    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}${en}"/>`)
  const priority = r === '' || r === 'ar/' ? '1.0' : r.startsWith('docs/') ? '0.8' : '0.5'
  return `  <url>\n    <loc>${siteUrl}${r}</loc>\n${alternates.join('\n')}\n    <changefreq>weekly</changefreq>\n    <priority>${priority}</priority>\n  </url>`
})

const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${entries.join('\n')}\n</urlset>\n`
writeFileSync(join(dist, 'sitemap.xml'), xml)
writeFileSync(join(dist, 'sitemap-0.xml'), xml)
console.log(`postbuild: sitemap.xml with ${allRoutes.length} URLs (AR docs fallbacks excluded)`)
