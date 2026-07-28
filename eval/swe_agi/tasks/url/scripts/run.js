#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');
const taskFile = path.join(repoRoot, 'TASK.md');
const logFile = path.join(repoRoot, 'log.jsonl');
const logYamlFile = path.join(repoRoot, 'log.yaml');
const metricsFile = path.join(repoRoot, 'run-metrics.json');

const startTime = new Date();
const startMs = Date.now();
let finalized = false;

// Parse command line arguments
const args = process.argv.slice(2);
const runner = args[0] || 'codex';

if (!['codex', 'claude'].includes(runner)) {
  console.error(`Unknown runner: ${runner}`);
  console.error('Usage: run.js [codex|claude]');
  process.exit(1);
}

// Runner configurations
const runners = {
  codex: {
    command: 'codex',
    args: [
      'exec',
      '--json',
      '--dangerously-bypass-approvals-and-sandbox',
      '--skip-git-repo-check',
      '--config',
      'model_reasoning_effort=high',
      '-m',
      process.env.CODEX_MODEL || 'gpt-5.2-codex',
      '-',
    ],
    useStdin: true,
    stdio: ['pipe', 'pipe', 'inherit'],
  },
  claude: {
    command: 'claude',
    args: [
      '--print',
      '--output-format', 'stream-json',
      '--verbose',
      '--dangerously-skip-permissions',
      '--model', process.env.CLAUDE_MODEL || 'opus',
    ],
    useStdin: false,
    stdio: ['inherit', 'pipe', 'inherit'],
  },
};

const config = runners[runner];

function finalize(exitCode, signal, testResults) {
  if (finalized) {
    return;
  }
  finalized = true;

  const endTime = new Date();
  const metrics = {
    runner,
    start_time: startTime.toISOString(),
    end_time: endTime.toISOString(),
    elapsed_ms: Date.now() - startMs,
    exit_code: exitCode === null ? null : exitCode,
    test_results: testResults || null,
  };

  try {
    fs.writeFileSync(metricsFile, JSON.stringify(metrics, null, 2) + '\n');
  } catch (err) {
    console.error(`Failed to write ${metricsFile}:`, err);
  }

  if (signal) {
    console.error(`${runner} exited with signal ${signal}`);
  }

  process.exitCode = exitCode === null ? 1 : exitCode;
}

function runJsonlToYaml(callback) {
  const yq = spawn('yq', ['-p=json', '-o=yaml', '-P', '.', logFile], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'inherit'],
  });

  yq.on('error', (err) => {
    console.error('Failed to start yq:', err);
    callback(1);
  });

  const yamlOut = fs.createWriteStream(logYamlFile, { flags: 'w' });
  yamlOut.on('error', (err) => {
    console.error(`Failed to write ${logYamlFile}:`, err);
    yq.kill('SIGTERM');
    callback(1);
  });

  yq.stdout.pipe(yamlOut);
  yq.on('close', (code, signal) => {
    if (signal) {
      console.error(`yq exited with signal ${signal}`);
      callback(1);
      return;
    }
    callback(code === null ? 1 : code);
  });
}

function parseTestOutput(output) {
  const match = output.match(/Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)/);
  if (match) {
    return {
      total_tests: parseInt(match[1], 10),
      passed: parseInt(match[2], 10),
      failed: parseInt(match[3], 10),
    };
  }
  return null;
}

function runMoonTest(callback) {
  const moonTest = spawn('moon', ['test'], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let output = '';

  moonTest.stdout.on('data', (data) => { output += data; });
  moonTest.stderr.on('data', (data) => { output += data; });

  moonTest.on('error', (err) => {
    console.error('Failed to start moon test:', err);
    callback(1, null);
  });

  moonTest.on('close', (code, signal) => {
    if (signal) {
      console.error(`moon test exited with signal ${signal}`);
      callback(1, null);
      return;
    }

    const testResults = parseTestOutput(output);
    callback(code === null ? 1 : code, testResults);
  });
}

// Build final args based on runner type
let finalArgs = config.args;
if (!config.useStdin) {
  const taskContent = fs.readFileSync(taskFile, 'utf-8');
  finalArgs = [...config.args, taskContent];
}

const child = spawn(config.command, finalArgs, {
  cwd: repoRoot,
  stdio: config.stdio,
});

child.on('error', (err) => {
  console.error(`Failed to start ${runner}:`, err);
  finalize(1, null, null);
});

// Pipe stdin if required (for codex)
if (config.useStdin) {
  const input = fs.createReadStream(taskFile);
  input.on('error', (err) => {
    console.error(`Failed to read ${taskFile}:`, err);
    child.kill('SIGTERM');
    finalize(1, 'SIGTERM', null);
  });
  input.pipe(child.stdin);
}

const output = fs.createWriteStream(logFile, { flags: 'w' });
output.on('error', (err) => {
  console.error(`Failed to write ${logFile}:`, err);
  child.kill('SIGTERM');
});
child.stdout.pipe(output);

child.on('close', (code, signal) => {
  if (code !== 0 || signal) {
    finalize(code, signal, null);
    return;
  }

  runJsonlToYaml((yqExitCode) => {
    if (yqExitCode !== 0) {
      finalize(yqExitCode, null, null);
      return;
    }

    runMoonTest((testExitCode, testResults) => {
      finalize(code, null, testResults);
    });
  });
});
