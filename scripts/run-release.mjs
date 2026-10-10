import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const state = JSON.parse(fs.readFileSync(new URL('../release/version.json', import.meta.url), 'utf8'));
const options = process.argv.slice(2);
if (state.freezeUntilStoresPublished && options.some(arg => /^(--increment|--major|--minor|--patch)/.test(arg))) {
  throw Error('App version is frozen. Record store publication and lift the freeze before requesting a bump.');
}
const command = fileURLToPath(new URL('../node_modules/release-it/bin/release-it.js', import.meta.url));
const result = spawnSync(process.execPath, [command, ...(state.freezeUntilStoresPublished ? ['--no-increment'] : []), ...options], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
process.exit(result.status ?? 1);
