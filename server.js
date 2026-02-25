const http = require('http');
const { WebSocketServer } = require('ws');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;

// ── Load dashboard HTML from file ──
const DASHBOARD_PATH = path.join(__dirname, 'dashboard.html');
let DASHBOARD_HTML = '';
try {
  DASHBOARD_HTML = fs.readFileSync(DASHBOARD_PATH, 'utf8');
  console.log('✅ Dashboard HTML loaded (' + DASHBOARD_HTML.length + ' bytes)');
} catch(e) {
  console.error('❌ Could not load dashboard.html:', e.message);
  DASHBOARD_HTML = '<h1>Dashboard not found</h1>';
}

// ── In-memory signal store ──
let signals = {};
let clients = new Set();

// ── HTTP Server ──
const httpServer = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Serve dashboard at GET /
  if (req.method === 'GET' && (req.url === '/' || req.url === '/dashboard')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(DASHBOARD_HTML);
    return;
  }

  // Health check JSON at GET /status
  if (req.method === 'GET' && req.url === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'online',
      service: 'BFA Volatility Monitor',
      active_signals: Object.keys(signals).length,
      connected_clients: clients.size,
      uptime: Math.floor(process.uptime()),
      timestamp: Math.floor(Date.now() / 1000)
    }));
    return;
  }

  if (req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);

        if (data.type === 'heartbeat') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok', type: 'heartbeat' }));
          broadcast({ type: 'heartbeat', timestamp: data.timestamp, active_signals: Object.keys(signals).length });
          return;
        }

        if (data.type === 'signal') {
          const key = `${data.symbol}_${data.timeframe}`;
          signals[key] = { ...data, received_at: Date.now() };
          console.log(`[SIGNAL] ${data.symbol} ${data.timeframe} → ${data.trade_type}`);
          broadcast(data);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok', key }));
          return;
        }

        if (data.type === 'remove_signal') {
          const key = `${data.symbol}_${data.timeframe}`;
          delete signals[key];
          console.log(`[REMOVE] ${data.symbol} ${data.timeframe}`);
          broadcast(data);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok', removed: key }));
          return;
        }

        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'error', message: 'Unknown type' }));

      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'error', message: 'Invalid JSON' }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end();
});

// ── WebSocket Server ──
const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`[WS] Client connected — total: ${clients.size}`);

  // Send all cached signals to new dashboard client
  const current = Object.values(signals);
  if (current.length > 0) {
    current.forEach(sig => ws.send(JSON.stringify(sig)));
    console.log(`[WS] Sent ${current.length} cached signals to new client`);
  }

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`[WS] Client disconnected — total: ${clients.size}`);
  });

  ws.on('error', () => clients.delete(ws));
});

function broadcast(data) {
  const msg = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === 1) client.send(msg);
  });
}

// ── Start ──
httpServer.listen(PORT, () => {
  console.log('╔════════════════════════════════════════╗');
  console.log('║  BFA VOLATILITY SERVER                 ║');
  console.log('║  Dashboard served at /                 ║');
  console.log('║  Health check at /status               ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`🚀 Running on port ${PORT}`);
  console.log(`🌐 Open: https://your-render-url.onrender.com`);
});
