import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const write = (p, s) => fs.writeFileSync(path.join(root, p), s);
const state = JSON.parse(read('release/version.json'));
const pkg = JSON.parse(read('package.json'));
const valid = v => /^\d+\.\d+\.\d+$/.test(v);
if (process.argv[2] === '--guard') {
  const target = process.argv[3];
  if (!valid(target)) throw Error('Expected a numeric semantic version.');
  if (state.freezeUntilStoresPublished && target !== '0.1.0') {
    throw Error('Version is frozen at 0.1.0 until the owner records store publication and lifts the freeze.');
  }
  process.exit(0);
}
if (!valid(pkg.version)) throw Error('Invalid package version.');
if (state.freezeUntilStoresPublished && pkg.version !== '0.1.0') throw Error('Version freeze violated.');
const projects = ['apps/macos/Tetherly.xcodeproj/project.pbxproj', 'apps/ios/TetherlyiOS.xcodeproj/project.pbxproj'];
const gradle = 'apps/android/app/build.gradle.kts';
if (process.argv[2] === '--check') {
  if (state.version !== pkg.version) throw Error('Release metadata version differs.');
  for (const p of projects) {
    const versions = [...read(p).matchAll(/MARKETING_VERSION = ([^;]+);/g)].map(m => m[1]);
    if (!versions.length || versions.some(v => v !== pkg.version)) throw Error(`Version differs in ${p}`);
  }
  if (!read(gradle).includes(`versionName = "${pkg.version}"`)) throw Error('Android version differs.');
  console.log(`All app versions match ${pkg.version}. Freeze: ${state.freezeUntilStoresPublished}.`);
} else if (process.argv[2] === '--sync') {
  state.version = pkg.version;
  write('release/version.json', JSON.stringify(state, null, 2) + '\n');
  for (const p of projects) write(p, read(p).replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${pkg.version};`).replace(/CURRENT_PROJECT_VERSION = \d+;/g, `CURRENT_PROJECT_VERSION = ${state.build};`));
  write(gradle, read(gradle).replace(/versionName = "[^"]+"/, `versionName = "${pkg.version}"`).replace(/versionCode = \d+/, `versionCode = ${state.build}`));
  const web = 'apps/web/package.json';
  const w = JSON.parse(read(web)); w.version = pkg.version; write(web, JSON.stringify(w, null, 2) + '\n');
  const latest = read('CHANGELOG.md').split(/^## /m)[1]?.split(/^## /m)[0].split('\n').slice(1).join('\n').trim() || state.notes.join('\n');
  for (const p of ['apps/macos/Tetherly/MenuView.swift', 'apps/ios/TetherlyiOS/HomeView.swift', 'apps/android/app/src/main/java/link/tetherly/MainActivity.kt']) {
    const literal = JSON.stringify(latest);
    const value = p.endsWith('.kt') ? literal.replaceAll('$', '\\$') : literal;
    write(p, read(p).replace(/((?:private let|val) releaseNotesText = ).*?( \/\/ RELEASE_NOTES_TEXT)/, (_, prefix, suffix) => prefix + value + suffix));
  }
  write('apps/web/src/content/changelog.json', JSON.stringify({ version: pkg.version, markdown: read('CHANGELOG.md') }, null, 2) + '\n');
  console.log(`Synchronized ${pkg.version} (${state.build}).`);
} else throw Error('Use --check, --sync, or --guard VERSION.');
