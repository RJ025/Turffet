// Generates PWA icons from public/icons/icon-source.jpg and compresses turf photos.
// Usage: npm run icons
import sharp from 'sharp'
import { readdir, stat, rename, unlink } from 'node:fs/promises'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const iconsDir = path.join(root, 'public', 'icons')
const source = path.join(iconsDir, 'icon-source.jpg')
const BG = { r: 11, g: 15, b: 12, alpha: 1 }

async function icons() {
  // The source art has generous padding already; crop a little for regular icons.
  const meta = await sharp(source).metadata()
  const crop = Math.round(meta.width * 0.16)
  const tight = sharp(source).extract({
    left: crop, top: crop, width: meta.width - crop * 2, height: meta.height - crop * 2,
  })
  const tightBuf = await tight.toBuffer()

  await sharp(tightBuf).resize(192, 192).png().toFile(path.join(iconsDir, 'icon-192.png'))
  await sharp(tightBuf).resize(512, 512).png().toFile(path.join(iconsDir, 'icon-512.png'))
  await sharp(tightBuf).resize(180, 180).png().toFile(path.join(iconsDir, 'apple-touch-icon.png'))
  await sharp(tightBuf).resize(48, 48).png().toFile(path.join(iconsDir, 'favicon-48.png'))
  // Maskable: full source (content sits well inside the 80% safe zone)
  await sharp(source).resize(512, 512).flatten({ background: BG }).png().toFile(path.join(iconsDir, 'icon-512-maskable.png'))
  console.log('icons ✓')
}

async function photos() {
  const dir = path.join(root, 'public', 'images', 'turfs')
  for (const f of await readdir(dir)) {
    if (!/\.(jpe?g|png)$/i.test(f)) continue
    const p = path.join(dir, f)
    const before = (await stat(p)).size
    if (before < 300_000) continue
    const tmp = p + '.tmp'
    await sharp(p).resize({ width: 1280, withoutEnlargement: true }).jpeg({ quality: 72, mozjpeg: true }).toFile(tmp)
    await unlink(p)
    await rename(tmp, p)
    const after = (await stat(p)).size
    console.log(`${f}: ${(before / 1024).toFixed(0)}KB → ${(after / 1024).toFixed(0)}KB`)
  }
}

await icons()
await photos()
