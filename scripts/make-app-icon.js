// Renders scripts/app-icon.svg into App/Assets.xcassets/AppIcon.appiconset at every size macOS
// asks for. Needs Node and Playwright with Chromium (a dev tool only; nothing ships with the app):
//   node scripts/make-app-icon.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const svg = fs.readFileSync(path.join(root, 'scripts/app-icon.svg'), 'utf8');
const out = path.join(root, 'App/Assets.xcassets/AppIcon.appiconset');
const sizes = [16, 32, 64, 128, 256, 512, 1024];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const size of sizes) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<html><body style="margin:0;background:transparent">
      <img src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" width="${size}" height="${size}" style="display:block">
      </body></html>`);
    await page.screenshot({ path: path.join(out, `icon_${size}.png`), omitBackground: true });
  }
  await browser.close();
})();
