#!/usr/bin/env node
// Enthroned OS wallpaper generator (F2.1).
// Regenerates the PNGs shipped in system_files/usr/share/wallpapers/.
// Pure Node stdlib (zlib) - no dependencies, no network access.
//
// Usage: node scripts/enthroned-wallpapers.js <path-to-system_files/usr/share/wallpapers>
// Check with: git status  (only the six PNGs should change)
'use strict';

const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const OUT_ROOT = process.argv[2];
if (!OUT_ROOT) {
  console.error('usage: node scripts/enthroned-wallpapers.js <system_files/usr/share/wallpapers>');
  process.exit(2);
}

// ---------- minimal PNG writer ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function writePng(file, width, height, rgb) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // color type: truecolor RGB
  const stride = width * 3 + 1;
  const raw = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    raw[y * stride] = 0; // filter: none
    rgb.copy(raw, y * stride + 1, y * width * 3, (y + 1) * width * 3);
  }
  fs.writeFileSync(file, Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

// ---------- rendering ----------
const clamp = (v) => (v < 0 ? 0 : v > 255 ? 255 : v | 0);
function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
}
const lerp = (a, b, t) => a + (b - a) * t;

function render(file, width, height, spec) {
  const rgb = Buffer.alloc(width * height * 3);
  const c0 = hexToRgb(spec.from);
  const c1 = hexToRgb(spec.to);
  const glows = spec.glows.map((g) => ({ ...g, color: hexToRgb(g.color) }));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const u = x / (width - 1);
      const v = y / (height - 1);
      const t = (u + v) / 2; // diagonal gradient
      let r = lerp(c0[0], c1[0], t);
      let g = lerp(c0[1], c1[1], t);
      let b = lerp(c0[2], c1[2], t);
      for (const gl of glows) {
        const dx = (u - gl.x) / gl.r;
        const dy = (v - gl.y * (width / height) / (width / height)) / gl.r;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1) {
          const a = gl.alpha * Math.pow(1 - d, 2);
          r = lerp(r, gl.color[0], a);
          g = lerp(g, gl.color[1], a);
          b = lerp(b, gl.color[2], a);
        }
      }
      const vx = u - 0.5;
      const vy = v - 0.5;
      const vig = 1 - spec.vignette * Math.min(1, (vx * vx + vy * vy) * 2.4);
      const i = (y * width + x) * 3;
      rgb[i] = clamp(r * vig);
      rgb[i + 1] = clamp(g * vig);
      rgb[i + 2] = clamp(b * vig);
    }
  }
  writePng(file, width, height, rgb);
  console.log('generated', path.relative(process.cwd(), file), `${width}x${height}`);
}

const SIZES = [[1920, 1080], [2560, 1440], [3840, 2160]];

// Enthroned (light) - used by the Enthroned Classic profile.
const Enthroned = {
  from: '#E9EDF8',
  to: '#C7D3EE',
  vignette: 0.05,
  glows: [
    { x: 0.74, y: 0.24, r: 0.58, alpha: 0.11, color: '#3E63DD' },
    { x: 0.14, y: 0.78, r: 0.42, alpha: 0.07, color: '#D9A441' },
  ],
};

// EnthronedNocturne (dark) - used by the Enthroned Modern profile.
const EnthronedNocturne = {
  from: '#0C1122',
  to: '#1A2030',
  vignette: 0.08,
  glows: [
    { x: 0.70, y: 0.28, r: 0.62, alpha: 0.17, color: '#2D4FC7' },
    { x: 0.86, y: 0.88, r: 0.30, alpha: 0.06, color: '#D9A441' },
  ],
};

for (const [pkg, spec] of [['Enthroned', Enthroned], ['EnthronedNocturne', EnthronedNocturne]]) {
  const dir = path.join(OUT_ROOT, pkg, 'contents', 'images');
  fs.mkdirSync(dir, { recursive: true });
  for (const [w, h] of SIZES) {
    render(path.join(dir, `${w}x${h}.png`), w, h, spec);
  }
}
console.log('done');
