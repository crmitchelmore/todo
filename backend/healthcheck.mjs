const port = process.env.BACKEND_PORT ?? '6060';

try {
  const response = await fetch(`http://127.0.0.1:${port}/api/health`);
  process.exit(response.ok ? 0 : 1);
} catch {
  process.exit(1);
}
