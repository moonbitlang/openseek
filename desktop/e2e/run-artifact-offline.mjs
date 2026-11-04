import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const e2e = fileURLToPath(new URL('.', import.meta.url));
const repo = fileURLToPath(new URL('../../', import.meta.url));
const temporary = await mkdtemp(join(tmpdir(), 'openseek-artifact-offline-'));
function run(program, args, options = {}) {
  execFileSync(program, args, { cwd: repo, stdio: 'inherit', timeout: 300_000, ...options });
}
try {
  run(process.execPath, ['--test', join(e2e, 'artifact-component.test.mjs')]);
  const scratch = join(temporary, 'scratch');
  const artifact = join(scratch, 'artifact');
  await mkdir(scratch);
  run('moon', ['run', '--target-dir', join(temporary, 'init-build'), join(repo, 'share/artifact/init.mbtx'), scratch, join(repo, 'share/artifact/rabbita'), 'preview']);
  const project = join(temporary, 'scratch/component-work/preview');
  run('moon', ['run', '--target-dir', join(temporary, 'recipe-build'), join(repo, 'share/artifact/build.mbtx'), project, artifact, 'speedup-v1.html']);
  run(process.execPath, [join(repo, 'desktop/package/build.mjs'), 'browser', '--release'], { cwd: join(repo, 'desktop') });
  run(process.execPath, [join(e2e, 'node_modules/@playwright/test/cli.js'), 'test', '--config', 'playwright.artifact-offline.config.js'], {
    cwd: e2e,
    env: {
      ...process.env,
      OPENSEEK_DESKTOP_OFFLINE_ASSETS: join(repo, 'desktop/dist/browser'),
      OPENSEEK_COMPONENT_HTML: join(artifact, 'speedup-v1.html'),
    },
  });
} finally {
  await rm(temporary, { recursive: true, force: true });
}
