// Shared vector artwork -> Apple layers, Android resources and web icons.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '../..');
const check = process.argv.includes('--check');
const stale = [];
let count = 0;

async function output(relative, contents) {
  const file = path.join(root, relative);
  const bytes = Buffer.isBuffer(contents) ? contents : Buffer.from(contents);
  const current = await fs.readFile(file).catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return null;
  });
  count++;
  if (current?.equals(bytes)) return;
  if (check) { stale.push(relative); return; }
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, bytes);
}

async function main() {
  const design = JSON.parse(await fs.readFile(path.join(root, 'design/app-icon/design.json'), 'utf8'));
  const football = await fs.readFile(path.join(root, design.football), 'utf8');
  const inner = football.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')
    .replace(/fill="#[a-fA-F0-9]+"/g, `fill="${design.foreground}"`);
  if (!football.includes('viewBox="0 0 24 24"')) throw new Error('Football must use a 24 × 24 viewBox.');
  const { gradient: g } = design;
  const backdrop = `<defs><linearGradient id="background" x1="${g.start[0]}" y1="${g.start[1]}" x2="${g.end[0]}" y2="${g.end[1]}"><stop stop-color="${g.bottomLeft}"/><stop offset="1" stop-color="${g.topRight}"/></linearGradient></defs><path fill="url(#background)" d="M0 0h1024v1024H0z"/>`;
  const svg = content => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${content}</svg>\n`;
  const foreground = scale => `<g transform="translate(${512 * (1 - scale)} ${512 * (1 - scale)}) scale(${1024 * scale / 24})">${inner}</g>`;
  const composite = svg(backdrop + foreground(design.scale));
  const raster = (art, size) => {
    const image = sharp(Buffer.from(art)).resize(size, size);
    // Full backgrounds are opaque, including the App Store fallback.
    if (art.includes('id="background"')) image.removeAlpha();
    return image.png().toBuffer();
  };

  await output('design/app-icon/generated/background.svg', svg(backdrop));
  await output('design/app-icon/generated/foreground.svg', svg(foreground(design.scale)));
  await output('design/app-icon/generated/icon.svg', composite);
  await output('assets/icon/AppIcon.png', await raster(composite, 1024));
  await output('ios/Runner/DAUAppIcon.icon/Assets/football.svg', svg(foreground(design.scale)));
  await output('ios/Runner/DAUAppIcon.icon/Assets/gradient.png', await raster(svg(backdrop), 1024));
  // Keep the old asset catalog usable as a flat fallback; the target uses DAUAppIcon.
  await output('ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png', await raster(composite, 1024));

  for (const [density, multiplier] of Object.entries({ mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 })) {
    const folder = `android/app/src/main/res/mipmap-${density}`;
    await output(`${folder}/ic_launcher.png`, await raster(composite, 48 * multiplier));
    await output(`${folder}/ic_launcher_background.png`, await raster(svg(backdrop), 108 * multiplier));
    const mask = await raster(svg(foreground(design.androidAdaptiveScale)), 108 * multiplier);
    await output(`${folder}/ic_launcher_foreground.png`, mask);
    await output(`${folder}/ic_launcher_monochrome.png`, mask);
  }
  for (const size of [192, 512]) {
    for (const prefix of ['Icon-', 'Icon-maskable-']) {
      await output(`web/icons/${prefix}${size}.png`, await raster(composite, size));
    }
  }
  for (const [file, size] of Object.entries({ 'favicon.png': 32, 'favicon-16x16.png': 16, 'favicon-32x32.png': 32, 'apple-touch-icon.png': 180 })) {
    await output(`web/${file}`, await raster(composite, size));
  }
  // ICO supports PNG entries; package 16, 32 and 48px images without another dependency.
  const sizes = [16, 32, 48];
  const images = await Promise.all(sizes.map(size => raster(composite, size)));
  const header = Buffer.alloc(6 + sizes.length * 16);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  images.forEach((bytes, i) => {
    const entry = 6 + i * 16;
    header[entry] = header[entry + 1] = sizes[i];
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(bytes.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += bytes.length;
  });
  await output('web/favicon.ico', Buffer.concat([header, ...images]));
  if (stale.length) throw new Error(`Regenerate stale icons:\n${stale.join('\n')}`);
  console.log(`${check ? 'Verified' : 'Generated'} ${count} icon assets.`);
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
