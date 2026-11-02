// Prueba de carga para comprobar el Auto Scaling Group (k6: https://k6.io).
//
// La política "requests" intenta mantener ~1000 peticiones/min por instancia
// (scaling_requests_per_target). Para llegar a 10 instancias hace falta una carga
// sostenida mayor a 10 × 1000 / 60 ≈ 167 peticiones por segundo.
//
// Uso:
//   brew install k6
//   k6 run -e URL=https://tu-subdominio.duckdns.org/api/health scripts/load-test.js
//   (opcional) -e RATE=300 -e HOLD=30m  para cambiar la tasa y la duración
//
// Detener en cualquier momento: Ctrl+C (la carga se corta al instante).
import http from 'k6/http';
import { check } from 'k6';

const URL = __ENV.URL;
if (!URL) throw new Error('Falta URL: k6 run -e URL=https://tu-subdominio.duckdns.org/api/health scripts/load-test.js');

const RATE = Number(__ENV.RATE || 300); // peticiones por segundo en la meseta
const HOLD = __ENV.HOLD || '30m';       // cuánto se sostiene la carga

export const options = {
  scenarios: {
    escalar_al_maximo: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 400,
      stages: [
        { target: RATE, duration: '5m' }, // subida gradual
        { target: RATE, duration: HOLD }, // meseta: aquí el ASG crece
        { target: 0, duration: '2m' },    // bajada
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],       // menos de 5 % de errores
    http_req_duration: ['p(95)<2000'],    // 95 % de respuestas en menos de 2 s
  },
};

export default function () {
  const res = http.get(URL, { tags: { name: 'health' } });
  check(res, { 'status 200': (r) => r.status === 200 });
}
