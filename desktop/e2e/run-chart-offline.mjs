import { execFileSync } from 'node:child_process';
import { copyFile, mkdtemp, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const e2e = fileURLToPath(new URL('.', import.meta.url));
const repo = fileURLToPath(new URL('../../', import.meta.url));
const temporary = await mkdtemp(join(tmpdir(), 'openseek-chart-offline-'));
function run(program, args, options = {}) {
  execFileSync(program, args, { cwd: repo, stdio: 'inherit', timeout: 300_000, ...options });
}
try {
  const artifact = join(temporary, 'scratch/artifact');
  const project = join(temporary, 'scratch/chart');
  await mkdir(project, { recursive: true });
  for (const name of ['moon.mod','moon.pkg','main.mbt','index.html']) {
    await copyFile(join(repo,'share/artifact/example',name),join(project,name));
  }
  run('moon',['run','--target-dir',join(temporary,'recipe-build'),join(repo,'share/artifact/build.mbtx'),project,artifact,'chart-v1.html']);
  run(process.execPath,[join(repo,'desktop/package/build.mjs'),'browser','--release'],{cwd:join(repo,'desktop')});
  run(process.execPath,[join(e2e,'node_modules/@playwright/test/cli.js'),'test','--config','playwright.chart-offline.config.js'],{
    cwd:e2e,env:{...process.env,OPENSEEK_DESKTOP_OFFLINE_ASSETS:join(repo,'desktop/dist/browser'),OPENSEEK_ARTIFACT_HTML:join(artifact,'chart-v1.html')},
  });
} finally { await rm(temporary,{recursive:true,force:true}); }
