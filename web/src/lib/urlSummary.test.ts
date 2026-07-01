import assert from 'node:assert/strict';
import test from 'node:test';

import { urlOnlyCapture } from './urlSummary';

test('detects URL-only captures for automatic summaries', () => {
  assert.equal(urlOnlyCapture(' https://example.com/article '), 'https://example.com/article');
  assert.equal(urlOnlyCapture('http://example.com/'), 'http://example.com/');
});

test('leaves normal todo text and unsafe schemes alone', () => {
  assert.equal(urlOnlyCapture('read https://example.com/article'), null);
  assert.equal(urlOnlyCapture('obsidian://open?vault=Notes'), null);
  assert.equal(urlOnlyCapture('example.com/article'), null);
});

