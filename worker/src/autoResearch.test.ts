import assert from 'node:assert/strict';
import test from 'node:test';

import {
  instructionsFromInterview,
  interviewPromptFor,
  needsInterview,
  parseInterviewResumePayload,
} from './autoResearch.js';

const discovery = {
  taskId: 'task-1',
  title: 'Find a dentist near me',
  query: 'Find a dentist near me',
  location: { source: 'unavailable' as const, label: null, latitude: null, longitude: null, timeZone: 'Europe/London' },
  web: { source: 'not_configured' as const, query: 'Find a dentist near me', results: [] },
  memories: [],
  nextActions: ['Run web search for "Find a dentist near me"', 'Add current location before choosing a nearby option'],
  confidence: 0.5,
};

test('needsInterview pauses when evidence is thin or research failed', () => {
  assert.equal(needsInterview(discovery, null), true);
  assert.equal(needsInterview(discovery, {
    source: 'llm',
    body: 'Thin answer',
    nextActions: [],
    confidence: 0.3,
    model: 'test',
  }), true);
  assert.equal(needsInterview({
    ...discovery,
    location: { source: 'env' as const, label: 'Leeds', latitude: null, longitude: null, timeZone: 'Europe/London' },
    web: { source: 'configured_endpoint' as const, query: 'Find a dentist near me Leeds', results: [{ title: 'Dentist', url: null, snippet: null }] },
    confidence: 0.8,
  }, {
    source: 'llm',
    body: 'Evidence-backed answer',
    nextActions: ['Call the dentist'],
    confidence: 0.8,
    model: 'test',
  }), false);
});

test('needsInterview accepts high-confidence research with built-in web results', () => {
  assert.equal(needsInterview({
    ...discovery,
    web: { source: 'builtin' as const, query: 'carbon steel wok UK', results: [{ title: 'Wok guide', url: 'https://example.invalid/wok', snippet: 'Carbon steel options.' }] },
    confidence: 0.7,
  }, {
    source: 'llm',
    body: 'Evidence-backed answer',
    nextActions: ['Compare the top options'],
    confidence: 0.91,
    model: 'gpt-5.6-sol',
  }), false);
});

test('interviewPromptFor prefers clickable options with free-text fallback', () => {
  const prompt = interviewPromptFor(discovery, 'web search unavailable');
  assert.match(prompt.question, /Find a dentist/);
  assert.equal(prompt.allowFreeText, true);
  assert.ok(prompt.options.some((option) => option.id === 'add-location'));
  assert.ok(prompt.options.some((option) => option.id === 'provide-source'));
  assert.ok(prompt.options.length <= 6);
});

test('parseInterviewResumePayload extracts option and fallback text', () => {
  const resume = parseInterviewResumePayload({
    selected_option: { id: 'add-location', label: 'Add location/context', value: 'Use Leeds city centre' },
    free_text: 'Prefer NHS if possible',
  });
  assert.ok(resume);
  assert.equal(resume.selectedOptionId, 'add-location');
  assert.match(instructionsFromInterview(resume), /Use Leeds city centre/);
  assert.match(instructionsFromInterview(resume), /Prefer NHS/);

  assert.equal(parseInterviewResumePayload({ selected_option: {}, free_text: '' }), null);
});
