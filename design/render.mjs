// Renders every artboard in design/canvas to docs/screenshots/<name>.png.
// Usage: node design/render.mjs
// Requires Playwright with Chromium. Google Fonts are fetched at render time.

import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

const here = dirname(fileURLToPath(import.meta.url));
const srcDir = join(here, 'canvas');
const outDir = join(here, '..', 'docs', 'screenshots');
mkdirSync(outDir, { recursive: true });

function decodeEntities(s) {
  return s.replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}

function attr(attrs, name) {
  const m = new RegExp(`${name}="([^"]*)"`).exec(attrs);
  return m ? m[1] : '';
}

function lookup(path, scope) {
  const p = path.trim();
  if (p === 'true') return true;
  if (p === 'false') return false;
  return p.split('.').reduce((o, k) => (o == null ? undefined : o[k]), scope);
}

function resolve(expr, scope) {
  const m = /^\s*\{\{(.*)\}\}\s*$/.exec(expr);
  return m ? lookup(m[1], scope) : expr;
}

function fill(text, scope) {
  return text.replace(/\{\{([^}]*)\}\}/g, (_, path) => {
    const v = lookup(path, scope);
    return v == null ? '' : String(v);
  });
}

function expand(tpl, scope) {
  let out = '';
  let i = 0;
  while (i < tpl.length) {
    const rest = tpl.slice(i);
    const m = /<(sc-for|sc-if)\b([^>]*)>/.exec(rest);
    if (!m) { out += fill(rest, scope); break; }
    const start = i + m.index;
    out += fill(tpl.slice(i, start), scope);
    const tag = m[1];
    const attrs = m[2];
    const bodyStart = start + m[0].length;
    const re = new RegExp(`<(/?)${tag}\\b[^>]*>`, 'g');
    re.lastIndex = bodyStart;
    let depth = 1, innerEnd = -1, closeEnd = -1, mm;
    while ((mm = re.exec(tpl))) {
      if (mm[1] === '/') { depth--; if (depth === 0) { innerEnd = mm.index; closeEnd = mm.index + mm[0].length; break; } }
      else depth++;
    }
    const inner = tpl.slice(bodyStart, innerEnd);
    if (tag === 'sc-for') {
      const list = resolve(attr(attrs, 'list'), scope) || [];
      const as = attr(attrs, 'as');
      list.forEach((item, idx) => { out += expand(inner, { ...scope, [as]: item, $index: idx }); });
    } else if (resolve(attr(attrs, 'value'), scope)) {
      out += expand(inner, scope);
    }
    i = closeEnd;
  }
  return out;
}

function buildPage(source) {
  const helmet = (/<helmet>([\s\S]*?)<\/helmet>/.exec(source) || [, ''])[1];
  const xdc = (/<x-dc>([\s\S]*?)<\/x-dc>/.exec(source) || [, ''])[1].replace(/<helmet>[\s\S]*?<\/helmet>/, '');
  const scriptTag = /<script type="text\/x-dc" data-dc-script data-props='([^']*)'>([\s\S]*?)<\/script>/.exec(source);
  const propsSpec = JSON.parse(decodeEntities(scriptTag[1]));
  const props = {};
  for (const [k, v] of Object.entries(propsSpec)) if (k !== '$preview' && v && 'default' in v) props[k] = v.default;
  class DCLogic { constructor(p) { this.props = p; this.state = {}; } }
  const Component = new Function('DCLogic', `${scriptTag[2]}; return Component;`)(DCLogic);
  const vals = new Component(props).renderVals() || {};
  const body = expand(xdc, vals);
  const { width, height } = propsSpec.$preview;
  const html = `<!doctype html><html><head><meta charset="utf-8">${helmet}</head><body>${body}</body></html>`;
  return { html, width, height };
}

const browser = await chromium.launch();
for (const file of readdirSync(srcDir).filter(f => f.endsWith('.dc.html')).sort()) {
  const { html, width, height } = buildPage(readFileSync(join(srcDir, file), 'utf8'));
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2 });
  await page.setContent(html, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  const out = join(outDir, file.replace('.dc.html', '.png'));
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width, height } });
  await page.close();
  console.log('wrote', out);
}
await browser.close();
