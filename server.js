const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 3000;

// ── In-memory signal store ──
let signals = {};      // key: symbol_timeframe
let clients = new Set(); // connected dashboard browsers

// ── HTTP Server (receives POSTs from MT5 EA) ──
const httpServer = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check
  if (req.method === 'GET') {
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
          // Keep-alive from EA — just acknowledge
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

  res.writeHead(405);
  res.end();
});

// ── WebSocket Server (pushes to dashboard browsers) ──
const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`[WS] Client connected — total: ${clients.size}`);

  // Send all current signals to newly connected dashboard
  const current = Object.values(signals);
  if (current.length > 0) {
    current.forEach(sig => {
      ws.send(JSON.stringify(sig));
    });
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
    if (client.readyState === 1) { // OPEN
      client.send(msg);
    }
  });
}

// ── Start ──
httpServer.listen(PORT, () => {
  console.log('╔════════════════════════════════════════╗');
  console.log('║  BFA VOLATILITY SERVER                 ║');
  console.log('║  Separate from Boom/Crash              ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 MT5 EA posts to: https://your-render-url.onrender.com`);
  console.log(`🔌 Dashboard connects via: wss://your-render-url.onrender.com`);
});
