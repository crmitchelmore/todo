import assert from 'node:assert/strict';
import test from 'node:test';

import { parseMarkdownList } from './markdownList';

/**
 * Mirrors CaptureCore's MarkdownListParserTests. Pins the paste-to-items behaviour users feel:
 * bullets/numbers/checkboxes split into individual todos, nesting becomes parent links plus
 * compatibility tags, inline #tags are extracted, and prose is left alone (returns null -> single capture).
 */

test('plain prose is not a list', () => {
  assert.equal(parseMarkdownList('buy milk'), null);
  assert.equal(parseMarkdownList('Hello world.\nThis is a paragraph of prose.'), null);
});

test('a stray dash amid prose stays a single capture', () => {
  assert.equal(parseMarkdownList('Some intro line\n- a single point\nmore prose here too'), null);
});

test('simple bullets split into items', () => {
  const items = parseMarkdownList('- buy milk\n- call dentist\n* water plants');
  assert.deepEqual(items?.map((i) => i.title), ['buy milk', 'call dentist', 'water plants']);
  assert.equal(items?.every((i) => !i.isDone && i.tags.length === 0), true);
});

test('numbered lists', () => {
  const items = parseMarkdownList('1. first\n2) second\n3. third');
  assert.deepEqual(items?.map((i) => i.title), ['first', 'second', 'third']);
});

test('checkbox done state', () => {
  const items = parseMarkdownList('- [ ] todo one\n- [x] done two\n- [X] done three');
  assert.deepEqual(items?.map((i) => i.title), ['todo one', 'done two', 'done three']);
  assert.deepEqual(items?.map((i) => i.isDone), [false, true, true]);
});

test('a single ticked checkbox counts as a list', () => {
  const items = parseMarkdownList('- [x] shipped the release');
  assert.equal(items?.length, 1);
  assert.equal(items?.[0].isDone, true);
  assert.equal(items?.[0].title, 'shipped the release');
});

test('nesting becomes project parent links and compatibility tags', () => {
  const text = ['- Acme launch', '  - draft the brief', '  - book the venue', '- Personal', '  - call mum'].join('\n');
  const items = parseMarkdownList(text);
  assert.deepEqual(items?.map((i) => i.title), ['Acme launch', 'draft the brief', 'book the venue', 'Personal', 'call mum']);
  assert.deepEqual(items?.[0].tags, []);
  assert.deepEqual(items?.[1].tags, ['Acme launch']);
  assert.deepEqual(items?.[2].tags, ['Acme launch']);
  assert.deepEqual(items?.[3].tags, []);
  assert.deepEqual(items?.[4].tags, ['Personal']);
  assert.deepEqual(items?.map((i) => i.parentIndex), [null, 0, 0, null, 3]);
  assert.deepEqual(items?.map((i) => i.depth), [0, 1, 1, 0, 1]);
});

test('deep nesting inherits all ancestors', () => {
  const text = ['- Work', '    - Project X', '        - sub task'].join('\n');
  const items = parseMarkdownList(text);
  assert.equal(items?.[items.length - 1].title, 'sub task');
  assert.deepEqual(items?.[items.length - 1].tags, ['Work', 'Project X']);
  assert.deepEqual(items?.map((i) => i.parentIndex), [null, 0, 1]);
});

test('tab indentation', () => {
  const items = parseMarkdownList('- Parent\n\t- child task');
  assert.deepEqual(items?.[items.length - 1].tags, ['Parent']);
});

test('inline hashtags extracted and stripped', () => {
  const items = parseMarkdownList('- call mum #personal #urgent\n- review PR #work');
  assert.equal(items?.[0].title, 'call mum');
  assert.deepEqual(items?.[0].tags, ['personal', 'urgent']);
  assert.equal(items?.[1].title, 'review PR');
  assert.deepEqual(items?.[1].tags, ['work']);
});

test('project and inline tags combine and dedupe case-insensitively', () => {
  const text = ['- Acme', '  - task #acme #ship'].join('\n');
  const items = parseMarkdownList(text);
  assert.deepEqual(items?.[items.length - 1].tags.map((t) => t.toLowerCase()), ['acme', 'ship']);
});

test('non-list trailing line ignored when list dominates', () => {
  const items = parseMarkdownList('- a\n- b\n- c\nsome trailing note');
  assert.deepEqual(items?.map((i) => i.title), ['a', 'b', 'c']);
});
