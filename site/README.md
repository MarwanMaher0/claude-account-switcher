# Site

Astro + Starlight site for cc-switch, built from this repository's own Markdown. On every
`npm run dev` or `npm run build`, `scripts/sync-docs.mjs` regenerates the docs content from
`README.md`, `docs/`, `PRIVACY.md`, `SECURITY.md` and `CHANGELOG.md` at the repository root;
page titles, descriptions, sidebar groups and FAQ questions live in `site.config.mjs`. OG
images are rendered by `scripts/og-image.mjs`, and `scripts/check-links.mjs` validates
internal links, anchors and the sitemap afterwards.

## Deployment

Published to GitHub Pages at <https://marwanmaher0.github.io/claude-account-switcher/> by
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml). On a push to `main` that
touches `site/`, `docs/`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`,
`PRIVACY.md`, `SECURITY.md` or the workflow itself, the workflow checks out the repository,
installs with `npm ci` under the Node version pinned in `.nvmrc`, runs `npm run build` (which
syncs the Markdown and generates the OG images first) and `npm run check:links`, uploads
`site/dist` as the Pages artifact, and deploys it. Pull requests run the same build and link
checks without deploying, and the workflow can be started manually (`workflow_dispatch`).

## Local preview

Node 22 is required: `.nvmrc` pins `22.23.4` and `package.json` declares
`engines.node >=22.23.4` (Astro 7 refuses older Node).

```bash
cd site
nvm install && nvm use    # reads .nvmrc
npm ci
npm run dev               # http://localhost:4321/claude-account-switcher/
npm run build             # production build into dist/ (sync + OG + postbuild checks)
npm run preview           # serve the built dist/ locally
```

`npm run check` runs Astro's own diagnostics; `npm run check:links` re-validates internal
links and anchors in `dist/`.