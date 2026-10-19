#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

const root = fileURLToPath(new URL('../', import.meta.url));
const { values } = parseArgs({ options: {
  release: { type: 'boolean', default: false },
  'browser-bundle': { type: 'string' },
} });
if (values.release) {
  for (const name of ['KEYSTORE_PATH', 'KEYSTORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD']) {
    if (!process.env[`OPENSEEK_ANDROID_${name}`]) {
      throw new Error(`Set OPENSEEK_ANDROID_${name} for a signed release APK`);
    }
  }
}
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
if (values['browser-bundle']) {
  // CI supplies the archive from this same release's browser build job.
  rmSync(join(root, 'desktop/dist/browser'), { recursive: true, force: true });
  mkdirSync(join(root, 'desktop/dist'), { recursive: true });
  run('tar', ['-xzf', resolve(values['browser-bundle']), '-C', join(root, 'desktop/dist')]);
} else {
  run(process.execPath, ['desktop/package/build.mjs', 'browser', '--release']);
}
const variant = values.release ? 'Release' : 'Debug';
run(join(root, 'android', process.platform === 'win32' ? 'gradlew.bat' : 'gradlew'),
  ['-p', 'android', `assemble${variant}`, `lint${variant}`, `test${variant}UnitTest`]);
const apk = join(root, `android/app/build/outputs/apk/${variant.toLowerCase()}/app-${variant.toLowerCase()}.apk`);
if (values.release) {
  const published = join(root, 'desktop/dist/SeekMoon-android.apk');
  cpSync(apk, published);
  console.log(`APK: ${published}`);
} else {
  console.log(`APK: ${apk}`);
}
