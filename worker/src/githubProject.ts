import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export interface GitHubProjectEnv {
  readonly CAPTURE_WORK_ROOT?: string;
  readonly CAPTURE_WORK_ROOT_MAX_REPOS?: string;
}

export interface GitHubRepository {
  fullName: string;
  url: string;
  path: string;
  score: number;
}

interface RepositoryCandidate {
  fullName: string;
  url: string;
  path: string;
  nameTokens: string[];
}

const SKIP_DIRS = new Set([
  '.git',
  '.build',
  'DerivedData',
  'Library',
  'node_modules',
  'vendor',
]);

export function workRootFromEnv(env: GitHubProjectEnv = process.env): string | null {
  const configured = env.CAPTURE_WORK_ROOT?.trim();
  if (configured) return path.resolve(configured.replace(/^~(?=$|\/)/, os.homedir()));
  if (process.platform === 'darwin') return path.join(os.homedir(), 'work');
  return null;
}

export function shouldAssociateGitHubProject(task: {
  title: string;
  category?: string | null;
  suggested_category?: string | null;
  github_repo?: string | null;
}): boolean {
  if (task.github_repo) return false;
  return task.category === 'engineering' || task.suggested_category === 'engineering';
}

export async function bestGitHubRepositoryForTask(
  task: { title: string },
  env: GitHubProjectEnv = process.env
): Promise<GitHubRepository | null> {
  const root = workRootFromEnv(env);
  if (!root) return null;
  const repos = await discoverGitHubRepositories(root, toPositiveInt(env.CAPTURE_WORK_ROOT_MAX_REPOS) ?? 200);
  return bestMatch(task.title, repos);
}

export async function discoverConfiguredGitHubRepositories(
  env: GitHubProjectEnv = process.env
): Promise<RepositoryCandidate[]> {
  const root = workRootFromEnv(env);
  if (!root) return [];
  return discoverGitHubRepositories(root, toPositiveInt(env.CAPTURE_WORK_ROOT_MAX_REPOS) ?? 200);
}

export async function discoverGitHubRepositories(root: string, maxRepos = 200): Promise<RepositoryCandidate[]> {
  const repos: RepositoryCandidate[] = [];
  if (!await exists(root)) return repos;
  await walk(root, 0, repos, Math.max(1, maxRepos));
  return repos;
}

export function bestMatch(title: string, repos: RepositoryCandidate[]): GitHubRepository | null {
  const normalizedTitle = normalise(title);
  let best: GitHubRepository | null = null;
  for (const repo of repos) {
    const repoName = repo.fullName.split('/').at(-1) ?? repo.fullName;
    const slug = normalise(repoName);
    let score = 0;
    if (slug && normalizedTitle.includes(slug)) score += 6;
    for (const token of repo.nameTokens) {
      if (token.length >= 3 && hasToken(normalizedTitle, token)) score += 2;
    }
    const owner = normalise(repo.fullName.split('/')[0] ?? '');
    if (owner && hasToken(normalizedTitle, owner)) score += 1;
    if (!best || score > best.score) best = { ...repo, score };
  }
  return best && best.score >= 4 ? best : null;
}

async function walk(root: string, depth: number, repos: RepositoryCandidate[], maxRepos: number): Promise<void> {
  if (repos.length >= maxRepos || depth > 3) return;
  let entries: Array<{ name: string; isDirectory(): boolean }>;
  try {
    entries = await fs.readdir(root, { withFileTypes: true });
  } catch {
    return;
  }

  if (await exists(path.join(root, '.git'))) {
    const repo = await repositoryAt(root);
    if (repo) repos.push(repo);
    return;
  }

  for (const entry of entries) {
    if (repos.length >= maxRepos) return;
    if (!entry.isDirectory() || SKIP_DIRS.has(entry.name) || entry.name.startsWith('.')) continue;
    await walk(path.join(root, entry.name), depth + 1, repos, maxRepos);
  }
}

async function repositoryAt(repoPath: string): Promise<RepositoryCandidate | null> {
  const config = await fs.readFile(path.join(repoPath, '.git', 'config'), 'utf8').catch(() => '');
  const remote = githubRemote(config);
  if (!remote) return null;
  const repoName = remote.fullName.split('/').at(-1) ?? path.basename(repoPath);
  return {
    ...remote,
    path: repoPath,
    nameTokens: tokenise(repoName),
  };
}

function githubRemote(config: string): Pick<RepositoryCandidate, 'fullName' | 'url'> | null {
  const matches = [...config.matchAll(/url\s*=\s*(.+)/g)].map((match) => match[1]?.trim()).filter(Boolean) as string[];
  for (const remote of matches) {
    const parsed = parseGitHubRemote(remote);
    if (parsed) return parsed;
  }
  return null;
}

function parseGitHubRemote(remote: string): Pick<RepositoryCandidate, 'fullName' | 'url'> | null {
  const https = remote.match(/^https:\/\/github\.com\/([^/\s]+)\/([^/\s]+?)(?:\.git)?$/i);
  const ssh = remote.match(/^git@github\.com:([^/\s]+)\/([^/\s]+?)(?:\.git)?$/i);
  const match = https ?? ssh;
  if (!match) return null;
  const owner = match[1];
  const repo = match[2];
  return {
    fullName: `${owner}/${repo}`,
    url: `https://github.com/${owner}/${repo}`,
  };
}

function tokenise(value: string): string[] {
  return [...new Set(normalise(value).split(' ').filter((token) => token.length >= 3))];
}

function normalise(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function hasToken(haystack: string, token: string): boolean {
  return new RegExp(`(^|\\s)${escapeRegExp(token)}(\\s|$)`).test(haystack);
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function exists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function toPositiveInt(value: string | undefined): number | null {
  if (!value) return null;
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}
