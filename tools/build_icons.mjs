// tools/build_icons.mjs
// Rasterise the chosen Lucide icons (MIT/ISC) to white-on-transparent 32-bit
// TGA files under Media/icons/, so WoW can load them (it cannot read SVG) and
// we can tint them at runtime via SetVertexColor. Reproducible asset build:
//
//   npm install --no-save lucide-static @resvg/resvg-js
//   node tools/build_icons.mjs
//
// The committed Media/icons/*.tga are the output of this script. Lucide's
// licence is recorded in THIRD_PARTY_LICENSES.md.

import fs from 'node:fs'
import path from 'node:path'
import { Resvg } from '@resvg/resvg-js'

const SIZE = 64
const ICONS = ['moon', 'moon-star', 'sun', 'sunrise', 'sunset']
const SRC = 'node_modules/lucide-static/icons'
const OUT = 'Media/icons'

// Uncompressed 32-bit true-colour TGA, top-left origin, BGRA pixel order.
function encodeTGA(rgba, w, h) {
  const header = Buffer.alloc(18)
  header[2] = 2            // image type: uncompressed true-colour
  header.writeUInt16LE(w, 12)
  header.writeUInt16LE(h, 14)
  header[16] = 32          // bits per pixel
  header[17] = 0x28        // 8 alpha bits (0x08) + top-left origin (0x20)
  const body = Buffer.alloc(w * h * 4)
  for (let i = 0; i < w * h; i++) {
    body[i * 4 + 0] = rgba[i * 4 + 2] // B
    body[i * 4 + 1] = rgba[i * 4 + 1] // G
    body[i * 4 + 2] = rgba[i * 4 + 0] // R
    body[i * 4 + 3] = rgba[i * 4 + 3] // A
  }
  return Buffer.concat([header, body])
}

fs.mkdirSync(OUT, { recursive: true })
for (const name of ICONS) {
  let svg = fs.readFileSync(path.join(SRC, `${name}.svg`), 'utf8')
  // Lucide strokes use currentColor; force white so the icon tints cleanly.
  svg = svg.replace(/currentColor/g, '#ffffff')
  const img = new Resvg(svg, { fitTo: { mode: 'width', value: SIZE } }).render()
  const tga = encodeTGA(img.pixels, img.width, img.height)
  fs.writeFileSync(path.join(OUT, `${name}.tga`), tga)
  console.log(`wrote ${OUT}/${name}.tga  (${img.width}x${img.height}, ${tga.length} bytes)`)
}
