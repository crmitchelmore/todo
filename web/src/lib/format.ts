export function formatDue(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  const isTomorrow = d.toDateString() === tomorrow.toDateString();

  const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  const hasTime = !(d.getHours() === 0 && d.getMinutes() === 0);

  if (sameDay) return hasTime ? `Today ${time}` : 'Today';
  if (isTomorrow) return hasTime ? `Tomorrow ${time}` : 'Tomorrow';
  const date = d.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
  return hasTime ? `${date} ${time}` : date;
}

export function formatTimestamp(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (sameDay) return `Today ${time}`;
  return d.toLocaleDateString([], { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
}
