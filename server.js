const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 8000;
const ROOT = path.join(__dirname, 'build', 'web');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2'
};

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (!fs.existsSync(ROOT)) {
    send(res, 500, 'Flutter web build not found. Run `flutter build web` first.');
    return;
  }

  const requestPath = decodeURIComponent(req.url.split('?')[0]);
  const normalized = path.normalize(requestPath).replace(/^([/\\]*\.\.[/\\])+/, '');
  let filePath = path.join(ROOT, normalized === '/' ? 'index.html' : normalized);

  if (!filePath.startsWith(ROOT)) {
    send(res, 403, 'Forbidden');
    return;
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      filePath = path.join(ROOT, 'index.html');
    }

    fs.stat(filePath, (fallbackErr, fallbackStat) => {
      if (fallbackErr || !fallbackStat.isFile()) {
        send(res, 404, 'Not found');
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      fs.createReadStream(filePath).pipe(res);
    });
  });
});

server.listen(PORT, () => {
  console.log(`Snow Cube prototype running at http://localhost:${PORT}/`);
});
