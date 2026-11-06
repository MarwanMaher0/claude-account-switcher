// @ts-check
import { defineConfig } from 'astro/config'
import starlight from '@astrojs/starlight'
import { base, groups, pages, repo, siteName, siteOrigin } from './site.config.mjs'

const sidebar = groups.map((group) => ({
  label: group.label,
  items: pages.filter((p) => p.group === group.id).map((p) => ({ label: p.sidebarLabel || p.title, slug: `docs/${p.slug}` })),
}))

export default defineConfig({
  site: siteOrigin,
  base,
  trailingSlash: 'always',
  compressHTML: true,
  build: { inlineStylesheets: 'auto' },
  redirects: {
    '/docs/': `${base}docs/get-started/`,
    '/ar/docs/': `${base}ar/docs/get-started/`,
  },
  integrations: [
    starlight({
      title: siteName,
      description: 'Keep each project folder on its own Claude Code account, and keep working when one of your accounts hits its limit.',
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en', dir: 'ltr' },
        ar: { label: 'العربية', lang: 'ar', dir: 'rtl' },
      },
      logo: { src: './src/assets/logo.svg', alt: '' },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: repo }],
      sidebar,
      customCss: ['./src/styles/tokens.css', './src/styles/custom.css'],
      components: {
        Head: './src/components/DocsHead.astro',
      },
      markdown: { processedDirs: ['./src/generated'] },
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
      lastUpdated: false,
      pagination: true,
      disable404Route: true,
      credits: false,
      head: [
        { tag: 'meta', attrs: { name: 'theme-color', content: '#0b100d', media: '(prefers-color-scheme: dark)' } },
        { tag: 'meta', attrs: { name: 'theme-color', content: '#f4f6f4', media: '(prefers-color-scheme: light)' } },
        { tag: 'link', attrs: { rel: 'preload', as: 'font', type: 'font/woff2', crossorigin: 'anonymous', href: `${base}fonts/BricolageGrotesque-latin.woff2` } },
      ],
    }),
  ],
})
