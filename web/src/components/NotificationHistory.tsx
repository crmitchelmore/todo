import type { NotificationRecord } from '../powersync/schema';

function tone(severity: string | null | undefined): string {
  return severity === 'error' ? 'danger' : severity === 'warning' ? 'signal' : severity === 'success' ? 'mint' : 'iris';
}

function time(value: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  return date.toLocaleString([], { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
}

export function NotificationHistory({ notifications }: { notifications: NotificationRecord[] }) {
  if (notifications.length === 0) return null;
  return (
    <section className="notification-history" aria-label="Notification history">
      <div className="notification-history-head">
        <div>
          <h2>Notifications · {notifications.length}</h2>
          <p>Research, interview and attempt updates stay here even if you miss the system notification.</p>
        </div>
      </div>
      <div className="notification-stack">
        {notifications.map((notification) => (
          <article key={notification.id} className={`notification-card tone-${tone(notification.severity)}`}>
            <span className="notification-kind">{notification.kind?.replaceAll('_', ' ')}</span>
            <h3>{notification.title}</h3>
            {notification.body && <p>{notification.body}</p>}
            <time>{time(notification.created_at)}</time>
          </article>
        ))}
      </div>
    </section>
  );
}
