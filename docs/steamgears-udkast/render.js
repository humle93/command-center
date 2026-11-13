// Renderer SVG-udkast til PNG og laver et samlet oversigtsbillede.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const dir = process.argv[2];
  const scale = Number(process.argv[3] || 2);
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.svg')).sort();
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 500, height: 700 }, deviceScaleFactor: scale });
  for (const f of files) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await page.screenshot({ path: path.join(dir, f.replace('.svg', '.png')) });
  }
  const cells = files.map(f => `<figure style="margin:0"><div style="box-shadow:0 2px 8px #0003">${fs.readFileSync(path.join(dir, f), 'utf8')}</div>
    <figcaption style="font:13px Inter;text-align:center;padding:6px">${f.replace('.svg', '')}</figcaption></figure>`).join('');
  const sheet = await browser.newPage({ viewport: { width: 1580, height: 1520 }, deviceScaleFactor: 1 });
  await sheet.setContent(`<html><body style="margin:0;background:#f4f1ea;padding:20px;display:grid;grid-template-columns:repeat(3,500px);gap:20px">${cells}</body></html>`);
  await sheet.screenshot({ path: path.join(dir, 'oversigt.png'), fullPage: true });
  await browser.close();
  console.log('rendered', files.length);
})();
