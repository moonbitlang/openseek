#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
for (const [command, args] of [
  [process.execPath, ['desktop/package/build.mjs', 'browser', '--release']],
  [join(root, 'android', process.platform === 'win32' ? 'gradlew.bat' : 'gradlew'),
    ['-p', 'android', 'assembleDebug', 'lintDebug']],
]) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log('APK: android/app/build/outputs/apk/debug/app-debug.apk');
