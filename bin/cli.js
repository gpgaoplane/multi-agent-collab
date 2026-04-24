#!/usr/bin/env node
// Thin Node shim that spawns the bundled bash bootstrap.
// Hard requirement: bash must be on PATH. On Windows, users need Git Bash or WSL.

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const USAGE = `Usage: multi-agent-collab <command> [args]

Commands:
  init                     Bootstrap multi-agent collab in the current repo
  join <name>              Add a new agent (claude/codex/gemini or any name)
  check                    Audit INDEX vs filesystem
  archive <path>           Archive a file
  register <path>          Register a file in INDEX
  presence start|end ...   Manage ACTIVE.md rows
  catchup ...              Delta-read INDEX / surface handoffs
  handoff <to> --from ...  Write a handoff block to your work log
  --help, -h               Show this help

Requires bash. On Windows, install Git for Windows (https://git-scm.com/download/win)
or use WSL.`;

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === '--help' || argv[0] === '-h') {
    console.log(USAGE);
    process.exit(argv.length === 0 ? 1 : 0);
  }

  const cmd = argv[0];
  const rest = argv.slice(1);

  // Resolve the bundled scripts dir relative to this file.
  const scriptsDir = path.resolve(__dirname, '..', 'scripts');

  let scriptPath;
  let scriptArgs = [];

  switch (cmd) {
    case 'init':
      scriptPath = path.join(scriptsDir, 'collab-init.sh');
      break;
    case 'join':
      if (rest.length === 0) {
        console.error('join: missing <name> argument');
        process.exit(1);
      }
      scriptPath = path.join(scriptsDir, 'collab-init.sh');
      scriptArgs = ['--join', rest[0]];
      break;
    case 'check':
      scriptPath = path.join(scriptsDir, 'collab-check.sh');
      break;
    case 'archive':
      if (rest.length === 0) {
        console.error('archive: missing <path> argument');
        process.exit(1);
      }
      scriptPath = path.join(scriptsDir, 'collab-archive.sh');
      scriptArgs = [rest[0]];
      break;
    case 'register':
      if (rest.length === 0) {
        console.error('register: missing <path> argument');
        process.exit(1);
      }
      scriptPath = path.join(scriptsDir, 'collab-register.sh');
      scriptArgs = [rest[0]];
      break;
    case 'presence':
      scriptPath = path.join(scriptsDir, 'collab-presence.sh');
      scriptArgs = rest;
      break;
    case 'catchup':
      scriptPath = path.join(scriptsDir, 'collab-catchup.sh');
      scriptArgs = rest;
      break;
    case 'handoff':
      scriptPath = path.join(scriptsDir, 'collab-handoff.sh');
      scriptArgs = rest;
      break;
    default:
      console.error(`Unknown command: ${cmd}`);
      console.error(USAGE);
      process.exit(1);
  }

  if (!fs.existsSync(scriptPath)) {
    console.error(`Bundled script missing: ${scriptPath}`);
    console.error('This is a package bug. Reinstall or report.');
    process.exit(1);
  }

  // Detect bash. On Windows, `bash` resolves to Git Bash if installed.
  const bashCmd = process.platform === 'win32' ? 'bash.exe' : 'bash';
  const child = spawn(bashCmd, [scriptPath, ...scriptArgs], {
    stdio: 'inherit',
    shell: false,
  });

  child.on('error', (err) => {
    if (err.code === 'ENOENT') {
      console.error('bash not found on PATH.');
      console.error('  On Windows: install Git for Windows (https://git-scm.com/download/win)');
      console.error('  On Linux/macOS: install bash via your package manager');
      process.exit(127);
    }
    throw err;
  });

  child.on('exit', (code) => {
    process.exit(code ?? 0);
  });
}

main();
