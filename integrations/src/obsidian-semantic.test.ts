import assert from "node:assert/strict";
import test from "node:test";

import {
  buildObsidianSemanticIndex,
  chunkMarkdownNote,
  VaultSemanticIndex,
} from "./obsidian-semantic.js";
import { VaultNote, VaultSearchHit } from "./types.js";

const note = (path: string, content: string): VaultNote => ({
  path,
  content,
  contentType: "text/markdown",
  retrievedAt: "2026-06-04T00:00:00.000Z",
});

test("chunkMarkdownNote keeps heading and line provenance", () => {
  const chunks = chunkMarkdownNote(note("Projects/Capture.md", "# Capture\n\nFast inbox.\n\n## Agent\nResearch tasks."), {
    maxChars: 80,
  });

  assert.equal(chunks.length, 2);
  assert.deepEqual(
    chunks.map((chunk) => ({ heading: chunk.heading, startLine: chunk.startLine, endLine: chunk.endLine })),
    [
      { heading: "Capture", startLine: 1, endLine: 4 },
      { heading: "Agent", startLine: 5, endLine: 6 },
    ],
  );
});

test("VaultSemanticIndex ranks the most relevant markdown chunk first", () => {
  const index = VaultSemanticIndex.fromNotes([
    note("Leadership/Roadmap.md", "# Roadmap\nQuarterly planning, OKRs, and platform strategy."),
    note("Home/Dentist.md", "# Dentist\nBook a checkup and update calendar."),
  ]);

  const hits = index.search("platform roadmap calendar", 2);

  assert.equal(hits.length, 2);
  assert.equal(hits[0].path, "Leadership/Roadmap.md");
  assert.ok(hits[0].score > hits[1].score);
});

test("buildObsidianSemanticIndex fetches unique candidate notes from seed searches", async () => {
  const hits: VaultSearchHit[] = [
    { path: "Projects/Capture.md", score: 0.9, matches: [] },
    { path: "Projects/Capture.md", score: 0.7, matches: [] },
    { path: "Projects/Agent.md", score: 0.6, matches: [] },
  ];
  const fetched: string[] = [];
  const connector = {
    searchVault: async () => hits,
    getNote: async (path: string) => {
      fetched.push(path);
      return note(path, `# ${path}\nAgent context and task planning.`);
    },
  };

  const index = await buildObsidianSemanticIndex(connector, ["Capture"], { maxNotes: 5 });

  assert.deepEqual(fetched, ["Projects/Capture.md", "Projects/Agent.md"]);
  assert.equal(index.size, 2);
  assert.equal(index.search("agent planning", 1)[0].path, "Projects/Agent.md");
});
