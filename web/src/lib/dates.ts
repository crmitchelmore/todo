// Shared date logic for "view by date": bucketing + quick-date presets.
// Bucketing is done on the user's LOCAL calendar day (not raw timestamps) so a task due
// "today at 00:00" reads as Today, never Overdue. Mirrors Swift DateGrouping.swift.

export type DateBucketKey = 'overdue' | 'today' | 'tomorrow' | 'thisWeek' | 'later' | 'noDate';

export interface DateBucket {
  key: DateBucketKey;
  label: string;
  order: number;
}

const BUCKETS: Record<DateBucketKey, DateBucket> = {
  overdue: { key: 'overdue', label: 'Overdue', order: 0 },
  today: { key: 'today', label: 'Today', order: 1 },
  tomorrow: { key: 'tomorrow', label: 'Tomorrow', order: 2 },
  thisWeek: { key: 'thisWeek', label: 'This week', order: 3 },
  later: { key: 'later', label: 'Later', order: 4 },
  noDate: { key: 'noDate', label: 'No date', order: 5 }
};

/** Whole-day difference between two dates measured in the local calendar (due - now). */
export function localDayDiff(due: Date, now: Date): number {
  const a = new Date(due.getFullYear(), due.getMonth(), due.getDate());
  const b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((a.getTime() - b.getTime()) / 86_400_000);
}

/** Classify a due date into a bucket relative to `now` (defaults to the current time). */
export function dateBucket(dueIso: string | null | undefined, now: Date = new Date()): DateBucket {
  if (!dueIso) return BUCKETS.noDate;
  const due = new Date(dueIso);
  if (Number.isNaN(due.getTime())) return BUCKETS.noDate;
  const diff = localDayDiff(due, now);
  if (diff < 0) return BUCKETS.overdue;
  if (diff === 0) return BUCKETS.today;
  if (diff === 1) return BUCKETS.tomorrow;
  if (diff <= 7) return BUCKETS.thisWeek;
  return BUCKETS.later;
}

export type DatePreset = 'today' | 'tomorrow' | 'weekend' | 'nextWeek' | 'clear';

/**
 * Quick-date presets, in local time. Day-level semantics (bucketing is day-based) so the time
 * is just a sensible default for display/reminders. Mirrors Swift DateGrouping.preset.
 */
export function presetDate(preset: DatePreset, now: Date = new Date()): string | null {
  if (preset === 'clear') return null;
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 9, 0, 0, 0);
  switch (preset) {
    case 'today':
      d.setHours(17, 0, 0, 0); // later today, not midnight
      break;
    case 'tomorrow':
      d.setDate(d.getDate() + 1);
      break;
    case 'weekend': {
      // next Saturday (or today if it's already Saturday)
      const delta = (6 - d.getDay() + 7) % 7;
      d.setDate(d.getDate() + delta);
      break;
    }
    case 'nextWeek': {
      // next Monday
      const delta = ((1 - d.getDay() + 7) % 7) || 7;
      d.setDate(d.getDate() + delta);
      break;
    }
  }
  return d.toISOString();
}

export const PRESET_LABELS: { preset: DatePreset; label: string }[] = [
  { preset: 'today', label: 'Today' },
  { preset: 'tomorrow', label: 'Tomorrow' },
  { preset: 'weekend', label: 'Weekend' },
  { preset: 'nextWeek', label: 'Next week' }
];
