import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const e2e = fileURLToPath(new URL('.', import.meta.url));
const repo = fileURLToPath(new URL('../../', import.meta.url));
function run(program, args, options = {}) {
  execFileSync(program, args, { cwd: repo, stdio: 'inherit', timeout: 300_000, ...options });
}
run(process.execPath, [join(repo, 'desktop/package/build.mjs'), 'browser', '--release'], { cwd: join(repo, 'desktop') });
run(process.execPath, [join(e2e, 'node_modules/@playwright/test/cli.js'), 'test', '--config', 'playwright.artifact-offline.config.js'], {
  cwd: e2e,
  env: { ...process.env, OPENSEEK_DESKTOP_OFFLINE_ASSETS: join(repo, 'desktop/dist/browser') },
});
