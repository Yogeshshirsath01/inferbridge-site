// Generates OG image + favicons from SVG templates via sharp.
// Run once; outputs live in public/.

import { writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const here = dirname(fileURLToPath(import.meta.url));
const PUBLIC = resolve(here, "..", "public");

const ACCENT = "#5B6AF0";
const BG = "#0C0D0F";
const GRAY_50 = "#F4F5F8";
const GRAY_300 = "#9BA1AF";

// ---- OG image (1200×630) ----
const ogSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="${BG}"/>
  <g transform="translate(96,96)">
    <rect x="0" y="0" width="52" height="52" rx="10" fill="${ACCENT}"/>
    <text x="26" y="37" text-anchor="middle"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
          font-size="28" font-weight="600" fill="${GRAY_50}">IB</text>
    <text x="72" y="38" font-family="-apple-system, BlinkMacSystemFont, sans-serif"
          font-size="28" font-weight="600" fill="${GRAY_50}">InferBridge</text>
  </g>
  <text x="96" y="330" font-family="-apple-system, BlinkMacSystemFont, sans-serif"
        font-size="84" font-weight="600" letter-spacing="-2" fill="${GRAY_50}">One API for every LLM.</text>
  <text x="96" y="420" font-family="-apple-system, BlinkMacSystemFont, sans-serif"
        font-size="36" font-weight="400" fill="${GRAY_300}">Global, open-source, and Indian.</text>
  <text x="96" y="548" font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
        font-size="24" font-weight="500" fill="${ACCENT}">inferbridge.dev</text>
</svg>`;

await sharp(Buffer.from(ogSvg)).png({ compressionLevel: 9 }).toFile(resolve(PUBLIC, "og.png"));

// ---- Favicon (SVG — scalable, crisp on retina) ----
const faviconSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="${ACCENT}"/>
  <text x="32" y="44" text-anchor="middle"
        font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
        font-size="32" font-weight="700" fill="${GRAY_50}">IB</text>
</svg>`;
writeFileSync(resolve(PUBLIC, "favicon.svg"), faviconSvg);

// ---- Apple touch icon (180×180 PNG) ----
await sharp(Buffer.from(faviconSvg))
  .resize(180, 180)
  .png({ compressionLevel: 9 })
  .toFile(resolve(PUBLIC, "apple-touch-icon.png"));

console.log("Generated: og.png, favicon.svg, apple-touch-icon.png");
