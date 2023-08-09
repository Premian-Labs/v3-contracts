import * as child_process from 'child_process';

export function getCommitHash() {
  return child_process.execSync('git rev-parse HEAD').toString().trim();
}
