// Explicit maintenance command. The browser tests never invoke the API.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

for (const name of ['attributes', 'mixed', 'media', 'review-summary', 'code']) {
  const path = suffix => new URL(`./${name}.${suffix}`, import.meta.url);
  const response = execFileSync('gh', ['api', 'markdown', '--method', 'POST', '--input', '-'], {
    input: JSON.stringify({ mode: 'gfm', text: readFileSync(path('md'), 'utf8') }), encoding: 'utf8',
  });
  writeFileSync(path('github.html'), response);
}
