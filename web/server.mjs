import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { join, normalize, resolve } from 'node:path';

const root = resolve('dist');
const port = Number(process.env.PORT ?? 3000);

const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml; charset=utf-8'],
  ['.wasm', 'application/wasm'],
]);

function safePath(pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  const relative = normalize(decoded).replace(/^(\.\.[/\\])+/, '').replace(/^[/\\]+/, '');
  const candidate = resolve(root, relative);
  return candidate.startsWith(root) ? candidate : null;
}

function sendFile(res, filePath, contentType) {
  res.writeHead(200, {
    'Content-Type': contentType,
    'Cache-Control': filePath.endsWith('apple-app-site-association')
      ? 'public, max-age=300'
      : 'public, max-age=31536000, immutable',
  });
  createReadStream(filePath).pipe(res);
}

createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  if (url.pathname === '/.well-known/apple-app-site-association') {
    return sendFile(res, join(root, '.well-known/apple-app-site-association'), 'application/json; charset=utf-8');
  }

  const filePath = safePath(url.pathname);
  if (filePath && existsSync(filePath) && statSync(filePath).isFile()) {
    const ext = filePath.slice(filePath.lastIndexOf('.'));
    return sendFile(res, filePath, contentTypes.get(ext) ?? 'application/octet-stream');
  }

  return sendFile(res, join(root, 'index.html'), 'text/html; charset=utf-8');
}).listen(port, () => {
  console.log(`Capture web serving ${root} on ${port}`);
});
