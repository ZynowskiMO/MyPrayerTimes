// tools/build_logo.mjs
// Rasterise the addon logo (Media/logo-source.png, supplied by the PO) to a
// small 32-bit TGA for the minimap button (WoW cannot load PNG). Reproducible:
//
//   npm install --no-save sharp
//   node tools/build_logo.mjs
//
// The committed Media/logo.tga is the output of this script.

import fs from 'node:fs'
import sharp from 'sharp'

const SRC = 'Media/logo-source.png'
const OUT = 'Media/logo.tga'
const SIZE = 64
const INNER = 52 // logo scaled to INNER, padded to SIZE with transparency, so it
                 // sits a little in from the circle edge (more breathing room)

// Uncompressed 32-bit true-colour TGA, top-left origin, BGRA pixel order.
function encodeTGA(rgba, w, h) {
  const header = Buffer.alloc(18)
  header[2] = 2                 // uncompressed true-colour
  header.writeUInt16LE(w, 12)
  header.writeUInt16LE(h, 14)
  header[16] = 32               // bits per pixel
  header[17] = 0x28             // 8 alpha bits + top-left origin
  const body = Buffer.alloc(w * h * 4)
  for (let i = 0; i < w * h; i++) {
    body[i * 4 + 0] = rgba[i * 4 + 2] // B
    body[i * 4 + 1] = rgba[i * 4 + 1] // G
    body[i * 4 + 2] = rgba[i * 4 + 0] // R
    body[i * 4 + 3] = rgba[i * 4 + 3] // A
  }
  return Buffer.concat([header, body])
}

const pad = Math.round((SIZE - INNER) / 2)
const { data, info } = await sharp(SRC)
  .resize(INNER, INNER, { fit: 'fill' })
  .extend({ top: pad, bottom: pad, left: pad, right: pad, background: { r: 0, g: 0, b: 0, alpha: 0 } })
  .ensureAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true })

fs.writeFileSync(OUT, encodeTGA(data, info.width, info.height))
console.log(`wrote ${OUT} (${info.width}x${info.height}, ${fs.statSync(OUT).size} bytes)`)
