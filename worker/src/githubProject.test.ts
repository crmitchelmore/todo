import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  bestMatch,
  discoverGitHubRepositories,
  shouldAssociateGitHubProject,
  workRootFromEnv,
} from './githubProject.js';

test('only engineering tasks without an existing repo are association candidates', () => {
  assert.equal(shouldAssociateGitHubProject({ title: 'Fix API', category: 'engineering' }), true);
  assert.equal(shouldAssociateGitHubProject({ title: 'Fix API', suggested_category: 'engineering' }), true);
  assert.equal(shouldAssociateGitHubProject({ title: 'Buy milk', category: 'errands' }), false);
  assert.equal(shouldAssociateGitHubProject({ title: 'Fix API', category: 'engineering', github_repo: 'owner/repo' }), false);
});

test('discovers GitHub remotes under a work root and matches by repo name', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'capture-work-'));
  const repo = path.join(root, 'todo');
  await mkdir(path.join(repo, '.git'), { recursive: true });
  await writeFile(path.join(repo, '.git', 'config'), [
    '[remote "origin"]',
    '\turl = git@github.com:crmitchelmore/todo.git',
    '',
  ].join('\n'));

  const repos = await discoverGitHubRepositories(root);
  assert.equal(repos.length, 1);
  assert.equal(repos[0]?.fullName, 'crmitchelmore/todo');
  assert.equal(bestMatch('Fix sync in the todo app', repos)?.fullName, 'crmitchelmore/todo');
});

test('configured work root expands home shorthand', () => {
  assert.equal(workRootFromEnv({ CAPTURE_WORK_ROOT: '~/work' }), path.join(os.homedir(), 'work'));
});
