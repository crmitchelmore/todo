import assert from 'node:assert/strict';
import test from 'node:test';

import {
  generateUrlSummaryDocument,
  parseSummaryPayload,
  renderObsidianMarkdown,
  urlOnlyCapture,
  type RunCommand,
} from './urlSummary.js';

test('urlOnlyCapture marks only bare web URLs', () => {
  assert.equal(urlOnlyCapture(' https://example.com/article '), 'https://example.com/article');
  assert.equal(urlOnlyCapture('read https://example.com/article'), null);
  assert.equal(urlOnlyCapture('obsidian://open?vault=Notes'), null);
});

test('parseSummaryPayload enforces overview and 3-5 paragraphs', () => {
  const payload = parseSummaryPayload(JSON.stringify({
    title: 'Long article',
    overview: 'One sentence. A second sentence. A third sentence should be dropped.',
    summary_paragraphs: ['First paragraph.', 'Second paragraph.', 'Third paragraph.'],
  }), 'https://example.com/article');

  assert.equal(payload.overview, 'One sentence. A second sentence.');
  assert.deepEqual(payload.paragraphs, ['First paragraph.', 'Second paragraph.', 'Third paragraph.']);
  assert.throws(
    () => parseSummaryPayload(JSON.stringify({ title: 'x', overview: 'ok', summary_paragraphs: ['one'] }), 'https://example.com'),
    /3-5 summary paragraphs/
  );
});

test('renderObsidianMarkdown writes overview and paragraph summary in one note', () => {
  const markdown = renderObsidianMarkdown('https://example.com/article', {
    title: 'Example Article',
    overview: 'This is the overview.',
    paragraphs: ['First paragraph.', 'Second paragraph.', 'Third paragraph.'],
  }, new Date('2026-07-01T10:00:00.000Z'));

  assert.match(markdown, /^---\ntitle: "Example Article"/);
  assert.match(markdown, /> \[!summary\] Overview\n> This is the overview\./);
  assert.match(markdown, /## Summary\n\nFirst paragraph\.\n\nSecond paragraph\.\n\nThird paragraph\./);
});

test('generateUrlSummaryDocument fetches content, calls LLM, and writes through Obsidian CLI when configured', async () => {
  const commands: Array<{ command: string; args: readonly string[] }> = [];
  const runCommand: RunCommand = async (command, args) => {
    commands.push({ command, args });
    return { stdout: '', stderr: '' };
  };
  const document = await generateUrlSummaryDocument('https://example.com/article', {
    now: new Date('2026-07-01T10:00:00.000Z'),
    env: {
      OPENAI_API_KEY: 'test-key',
      OPENAI_BASE_URL: 'https://llm.example/v1',
      URL_SUMMARY_LLM_MODEL: 'summary-model',
      OBSIDIAN_CLI_ENABLED: '1',
      OBSIDIAN_CLI_COMMAND: 'obsidian',
      OBSIDIAN_VAULT: 'Knowledge',
      OBSIDIAN_SUMMARY_FOLDER: 'Inbox/Summaries',
      URL_SUMMARY_DISABLE_DEFUDDLE: '1',
    },
    runCommand,
    fetchImpl: async (input) => {
      const url = String(input);
      if (url.includes('/chat/completions')) {
        return new Response(JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: 'Example Article',
                overview: 'The article explains the main idea in compact form.',
                summary_paragraphs: ['Paragraph one.', 'Paragraph two.', 'Paragraph three.'],
              }),
            },
          }],
        }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      return new Response('<article><h1>Example</h1><p>This page has enough readable article content to summarise for Capture users, including clear claims, supporting context, and practical implications.</p><p>It includes meaningful details that should survive extraction.</p></article>', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      });
    },
  });

  assert.equal(document.title, 'Example Article');
  assert.equal(document.model, 'summary-model');
  assert.equal(document.obsidianPath, 'Inbox/Summaries/2026-07-01-example-article.md');
  assert.equal(commands[0].command, 'obsidian');
  assert.ok(commands[0].args.includes('vault=Knowledge'));
  assert.ok(commands[0].args.includes('path=Inbox/Summaries/2026-07-01-example-article.md'));
});
