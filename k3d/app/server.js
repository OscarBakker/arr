/**
 * Simple Todo API — in-memory store, no DB.
 * Used by the backup CronJob via GET /api/export.
 */
const http = require('http');

// Log as soon as this file runs (so you see it in kubectl logs when the pod starts)
console.error('TODO APP: server.js loaded');

const PORT = process.env.PORT || 3000;
const todos = [];
let nextId = 1;

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (ch) => { body += ch; });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function send(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function log(msg) {
  console.error('[' + new Date().toISOString() + '] ' + msg);
}

function router(req, res) {
  const url = new URL(req.url || '/', `http://localhost:${PORT}`);
  const path = url.pathname;
  const method = req.method;
  log(method + ' ' + path);

  // Health for Kubernetes
  if (path === '/health' && method === 'GET') {
    send(res, 200, { ok: true });
    return;
  }

  // Export all todos (used by backup CronJob)
  if (path === '/api/export' && method === 'GET') {
    send(res, 200, { todos, exportedAt: new Date().toISOString() });
    return;
  }

  // List todos
  if (path === '/api/todos' && method === 'GET') {
    send(res, 200, todos);
    return;
  }

  // Add todo
  if (path === '/api/todos' && method === 'POST') {
    parseBody(req).then((body) => {
      const text = body.text || body.title || '';
      const todo = { id: nextId++, text, done: false, createdAt: new Date().toISOString() };
      todos.push(todo);
      log('Added todo: ' + text);
      send(res, 201, todo);
    }).catch(() => send(res, 400, { error: 'Invalid JSON' }));
    return;
  }

  // Toggle done
  if (path.startsWith('/api/todos/') && method === 'PATCH') {
    const id = parseInt(path.split('/').pop(), 10);
    const todo = todos.find((t) => t.id === id);
    if (!todo) {
      send(res, 404, { error: 'Not found' });
      return;
    }
    parseBody(req).then((body) => {
      if (body.done !== undefined) todo.done = !!body.done;
      if (body.text !== undefined) todo.text = body.text;
      send(res, 200, todo);
    }).catch(() => send(res, 400, { error: 'Invalid JSON' }));
    return;
  }

  // Delete todo
  if (path.startsWith('/api/todos/') && method === 'DELETE') {
    const id = parseInt(path.split('/').pop(), 10);
    const idx = todos.findIndex((t) => t.id === id);
    if (idx === -1) {
      send(res, 404, { error: 'Not found' });
      return;
    }
    todos.splice(idx, 1);
    send(res, 204, null);
    return;
  }

  // Simple HTML UI
  if (path === '/' || path === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Todo</title></head>
<body>
  <h1>Todo</h1>
  <form id="add">
    <input id="input" placeholder="New todo" />
    <button type="submit">Add</button>
  </form>
  <ul id="list"></ul>
  <p><button id="export">Export JSON</button></p>
  <pre id="out"></pre>
  <script>
    const list = document.getElementById('list');
    const out = document.getElementById('out');
    function load() {
      fetch('/api/todos').then(r => r.json()).then(data => {
        list.innerHTML = data.map(t => '<li data-id="' + t.id + '"><input type="checkbox" ' + (t.done ? 'checked' : '') + ' /> ' + t.text + ' <button class="del">Delete</button></li>').join('');
        list.querySelectorAll('.del').forEach(btn => btn.addEventListener('click', function() {
          fetch('/api/todos/' + this.closest('li').dataset.id, { method: 'DELETE' }).then(load);
        }));
        list.querySelectorAll('input[type=checkbox]').forEach(cb => cb.addEventListener('change', function() {
          fetch('/api/todos/' + this.closest('li').dataset.id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ done: this.checked }) }).then(load);
        }));
      });
    }
    document.getElementById('add').addEventListener('submit', function(e) {
      e.preventDefault();
      const input = document.getElementById('input');
      fetch('/api/todos', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text: input.value }) }).then(() => { input.value = ''; load(); });
    });
    document.getElementById('export').addEventListener('click', function() {
      fetch('/api/export').then(r => r.json()).then(d => { out.textContent = JSON.stringify(d, null, 2); });
    });
    load();
  </script>
</body>
</html>
    `);
    return;
  }

  send(res, 404, { error: 'Not found' });
}

const server = http.createServer(router);
server.listen(PORT, '0.0.0.0', () => {
  console.error('TODO APP: listening on port ' + PORT);
});
