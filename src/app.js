import express from 'express';
import { listDepartures, findDeparture } from './departures.js';

// APP_VERSION is baked into the image at build time (see Dockerfile ARG).
// The pipeline sets it to the git commit SHA, so /health tells you exactly
// which commit is running - that is how we prove a deploy or rollback worked.
export const version = process.env.APP_VERSION || 'dev';

const startedAt = Date.now();

export function createApp() {
  const app = express();
  app.disable('x-powered-by');

  app.get('/', (_req, res) => {
    res.json({
      service: 'tidewater-departures-api',
      version,
      endpoints: ['/health', '/departures', '/departures?tour=<tour-id>', '/departures/:id'],
    });
  });

  // Health check: used by Docker HEALTHCHECK, the deploy script and the
  // rollback script. Must be cheap and must not depend on anything external.
  app.get('/health', (_req, res) => {
    res.json({
      status: 'ok',
      version,
      uptimeSeconds: Math.round((Date.now() - startedAt) / 1000),
      timestamp: new Date().toISOString(),
    });
  });

  // Optional ?tour=<tour-id> narrows the list to one tour's departures.
  app.get('/departures', (req, res) => {
    const departures = listDepartures({ tour: req.query.tour });
    res.json({ count: departures.length, departures });
  });

  app.get('/departures/:id', (req, res) => {
    const departure = findDeparture(req.params.id);
    if (!departure) {
      return res.status(404).json({ error: `departure '${req.params.id}' not found` });
    }
    return res.json(departure);
  });

  // JSON 404 for anything else, so clients never get an HTML error page.
  app.use((req, res) => {
    res.status(404).json({ error: `no route for ${req.method} ${req.path}` });
  });

  return app;
}
