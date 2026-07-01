import assert from 'node:assert/strict';
import test from 'node:test';

import { urlOnlyCapture } from '../src/urlSummary.ts';

test('urlOnlyCapture marks bare HTTP URLs for summary handling', () => {
  assert.equal(urlOnlyCapture(' https://example.com/article '), 'https://example.com/article');
  assert.equal(urlOnlyCapture('http://example.com/'), 'http://example.com/');
});

test('urlOnlyCapture ignores ordinary task text and non-web schemes', () => {
  assert.equal(urlOnlyCapture('summarise https://example.com/article'), null);
  assert.equal(urlOnlyCapture('obsidian://open?vault=Notes'), null);
  assert.equal(urlOnlyCapture('example.com/article'), null);
});
