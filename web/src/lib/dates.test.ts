import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dateBucket, localDayDiff, presetDate } from './dates.ts';

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h, 0, 0).toISOString();

test('dateBucket: null / invalid is noDate', () => {
  assert.equal(dateBucket(null).key, 'noDate');
  assert.equal(dateBucket(undefined).key, 'noDate');
  assert.equal(dateBucket('not-a-date').key, 'noDate');
});

test('dateBucket: local midnight today is Today, not Overdue', () => {
  const now = new Date(2026, 5, 3, 14, 30); // 3 Jun 2026 14:30 local
  const midnight = new Date(2026, 5, 3, 0, 0).toISOString();
  assert.equal(dateBucket(midnight, now).key, 'today');
});

test('dateBucket: yesterday is Overdue', () => {
  const now = new Date(2026, 5, 3, 9, 0);
  assert.equal(dateBucket(at(2026, 6, 2), now).key, 'overdue');
});

test('dateBucket: tomorrow / this week / later boundaries', () => {
  const now = new Date(2026, 5, 3, 9, 0); // Wed 3 Jun
  assert.equal(dateBucket(at(2026, 6, 4), now).key, 'tomorrow');
  assert.equal(dateBucket(at(2026, 6, 5), now).key, 'thisWeek');
  assert.equal(dateBucket(at(2026, 6, 10), now).key, 'thisWeek'); // +7 days
  assert.equal(dateBucket(at(2026, 6, 11), now).key, 'later'); // +8 days
});

test('localDayDiff ignores time-of-day', () => {
  const now = new Date(2026, 5, 3, 23, 30);
  const earlyTomorrow = new Date(2026, 5, 4, 0, 30);
  assert.equal(localDayDiff(earlyTomorrow, now), 1);
});

test('presetDate: clear is null, others land in expected buckets', () => {
  const now = new Date(2026, 5, 3, 9, 0); // Wed
  assert.equal(presetDate('clear', now), null);
  assert.equal(dateBucket(presetDate('today', now), now).key, 'today');
  assert.equal(dateBucket(presetDate('tomorrow', now), now).key, 'tomorrow');
  // Wed -> Saturday is +3 (this week), Wed -> next Monday is +5 (this week)
  const weekend = new Date(presetDate('weekend', now)!);
  assert.equal(weekend.getDay(), 6);
  const nextWeek = new Date(presetDate('nextWeek', now)!);
  assert.equal(nextWeek.getDay(), 1);
});
