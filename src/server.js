import { createApp, version } from './app.js';

const port = Number(process.env.PORT) || 8080;
const app = createApp();

const server = app.listen(port, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'listening', port, version }));
});

// Docker sends SIGTERM on `docker stop`; closing cleanly lets in-flight
// requests finish and keeps deploys/rollbacks from leaving half-served calls.
function shutdown(signal) {
  console.log(JSON.stringify({ level: 'info', msg: 'shutting down', signal }));
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
