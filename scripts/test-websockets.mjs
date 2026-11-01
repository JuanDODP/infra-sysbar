// Prueba de WebSockets entre instancias (NLB -> ALB -> 3 EC2 + Redis).
// Conecta 9 clientes (el ALB los reparte entre las 3 EC2), el cliente #1 emite
// 'enviar_orden_caja' y se comprueba que TODOS reciben 'nueva_orden_recibida'.
// Si Redis no funcionara, solo recibirían los clientes del mismo servidor que el emisor.
//
// Uso:
//   cd scripts && npm install
//   node test-websockets.mjs https://tu-subdominio.duckdns.org
import { io } from 'socket.io-client';

const URL = process.argv[2];
if (!URL) {
  console.error('Uso: node test-websockets.mjs https://tu-subdominio.duckdns.org');
  process.exit(1);
}
const TOTAL = 9;
const clients = [];
const received = new Set();

const connectOne = (i) =>
  new Promise((resolve, reject) => {
    // Sin cookies ni polling: cada conexión cae en una instancia al azar
    const s = io(URL, { transports: ['websocket'], forceNew: true, timeout: 10000 });
    s.on('connect', () => resolve(s));
    s.on('connect_error', (e) => reject(new Error(`cliente ${i}: ${e.message}`)));
    s.on('nueva_orden_recibida', () => received.add(i));
  });

try {
  for (let i = 1; i <= TOTAL; i++) clients.push(await connectOne(i));
  console.log(`✅ ${TOTAL} clientes conectados por wss a ${URL}`);

  clients[0].emit('enviar_orden_caja', { prueba: true, ts: Date.now() });
  await new Promise((r) => setTimeout(r, 3000));

  console.log(`📨 Recibieron el evento: ${received.size}/${TOTAL}`);
  if (received.size === TOTAL) {
    console.log('✅ OK: los eventos llegan a los clientes de todas las instancias (Redis funciona).');
  } else {
    console.log('❌ Algunos clientes no recibieron el evento: revisa la conexión a Redis (logs del contenedor).');
    process.exitCode = 1;
  }
} catch (e) {
  console.error('❌ Error de conexión:', e.message);
  process.exitCode = 1;
} finally {
  clients.forEach((c) => c.close());
}
