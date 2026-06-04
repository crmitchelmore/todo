import { createHash } from "crypto";
import { ObsidianConnector } from "./obsidian.js";
import { VaultNote, VaultSearchHit, VaultSemanticChunk, VaultSemanticHit } from "./types.js";

const DEFAULT_DIMS = 256;
const DEFAULT_MAX_CHARS = 1_600;
const DEFAULT_TOP_K = 8;
const DEFAULT_MAX_NOTES = 24;

const STOP_WORDS = new Set([
  "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "i", "in",
  "is", "it", "me", "my", "of", "on", "or", "that", "the", "this", "to", "was", "with",
]);

export interface ChunkMarkdownOptions {
  readonly maxChars?: number;
}

export interface BuildSemanticIndexOptions extends ChunkMarkdownOptions {
  readonly maxNotes?: number;
}

interface EmbeddedChunk {
  readonly chunk: VaultSemanticChunk;
  readonly vector: Map<number, number>;
  readonly norm: number;
}

export class VaultSemanticIndex {
  private readonly chunks: readonly EmbeddedChunk[];

  private constructor(chunks: readonly EmbeddedChunk[]) {
    this.chunks = chunks;
  }

  static fromNotes(notes: readonly VaultNote[], options: ChunkMarkdownOptions = {}): VaultSemanticIndex {
    const chunks = notes.flatMap((note) => chunkMarkdownNote(note, options));
    return new VaultSemanticIndex(chunks.map((chunk) => {
      const vector = embed(`${chunk.path}\n${chunk.heading ?? ""}\n${chunk.text}`);
      return { chunk, vector, norm: norm(vector) };
    }));
  }

  get size(): number {
    return this.chunks.length;
  }

  search(query: string, topK = DEFAULT_TOP_K): readonly VaultSemanticHit[] {
    const queryVector = embed(query);
    const queryNorm = norm(queryVector);
    if (queryNorm === 0) return [];

    return this.chunks
      .map(({ chunk, vector, norm: chunkNorm }) => ({
        ...chunk,
        score: chunkNorm === 0 ? 0 : dot(queryVector, vector) / (queryNorm * chunkNorm),
      }))
      .filter((hit) => hit.score > 0)
      .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path) || a.startLine - b.startLine)
      .slice(0, topK);
  }
}

export async function buildObsidianSemanticIndex(
  connector: Pick<ObsidianConnector, "searchVault" | "getNote">,
  seedQueries: readonly string[],
  options: BuildSemanticIndexOptions = {}
): Promise<VaultSemanticIndex> {
  const maxNotes = options.maxNotes ?? DEFAULT_MAX_NOTES;
  const paths = new Map<string, VaultSearchHit>();

  for (const query of seedQueries.map((q) => q.trim()).filter(Boolean)) {
    for (const hit of await connector.searchVault(query)) {
      if (!paths.has(hit.path)) paths.set(hit.path, hit);
      if (paths.size >= maxNotes) break;
    }
    if (paths.size >= maxNotes) break;
  }

  const notes: VaultNote[] = [];
  for (const path of paths.keys()) {
    notes.push(await connector.getNote(path));
  }
  return VaultSemanticIndex.fromNotes(notes, options);
}

export function chunkMarkdownNote(note: VaultNote, options: ChunkMarkdownOptions = {}): readonly VaultSemanticChunk[] {
  const maxChars = options.maxChars ?? DEFAULT_MAX_CHARS;
  const lines = note.content.replace(/\r\n?/g, "\n").split("\n");
  const chunks: VaultSemanticChunk[] = [];
  let heading: string | undefined;
  let buffer: string[] = [];
  let startLine = 1;

  function flush(endLine: number): void {
    const text = buffer.join("\n").trim();
    if (text.length === 0) {
      buffer = [];
      return;
    }
    chunks.push({
      path: note.path,
      heading,
      text,
      startLine,
      endLine,
      tokenCount: tokenize(`${heading ?? ""} ${text}`).length,
    });
    buffer = [];
  }

  lines.forEach((line, index) => {
    const lineNo = index + 1;
    const headingMatch = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (headingMatch) {
      flush(lineNo - 1);
      heading = headingMatch[2];
      startLine = lineNo;
      buffer = [line];
      return;
    }

    const nextLength = buffer.join("\n").length + line.length + 1;
    if (buffer.length > 0 && nextLength > maxChars) {
      flush(lineNo - 1);
      startLine = lineNo;
    }
    if (buffer.length === 0) startLine = lineNo;
    buffer.push(line);
  });
  flush(lines.length);
  return chunks;
}

function tokenize(input: string): readonly string[] {
  const tokens = input
    .toLowerCase()
    .match(/[a-z0-9][a-z0-9'-]*/g) ?? [];
  return tokens
    .map((token) => token.replace(/'s$/, ""))
    .filter((token) => token.length > 1 && !STOP_WORDS.has(token));
}

function embed(input: string, dims = DEFAULT_DIMS): Map<number, number> {
  const vector = new Map<number, number>();
  for (const token of tokenize(input)) {
    const digest = createHash("sha256").update(token).digest();
    const index = digest.readUInt32BE(0) % dims;
    const sign = digest[4] % 2 === 0 ? 1 : -1;
    vector.set(index, (vector.get(index) ?? 0) + sign);
  }
  for (const [index, value] of vector) {
    vector.set(index, Math.sign(value) * Math.sqrt(Math.abs(value)));
  }
  return vector;
}

function norm(vector: Map<number, number>): number {
  let sum = 0;
  for (const value of vector.values()) sum += value * value;
  return Math.sqrt(sum);
}

function dot(a: Map<number, number>, b: Map<number, number>): number {
  let sum = 0;
  const [small, large] = a.size <= b.size ? [a, b] : [b, a];
  for (const [index, value] of small) sum += value * (large.get(index) ?? 0);
  return sum;
}
