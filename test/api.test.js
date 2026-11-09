import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';

// Boot the real app on a random free port and hit it over HTTP, exactly the
// way the deploy script's health check will. No test-only dependencies.
let server;
let baseUrl;

before(async () => {
  const app = createApp();
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

test('GET /health reports ok and a version', async () => {
  const res = await fetch(`${baseUrl}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(typeof body.version, 'string');
  assert.ok(body.version.length > 0);
  assert.equal(typeof body.uptimeSeconds, 'number');
});

test('GET /departures lists every departure with seats left', async () => {
  const res = await fetch(`${baseUrl}/departures`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.count, 5);
  assert.equal(body.departures.length, 5);
  assert.ok(body.departures.every((d) => d.seatsLeft === d.seatsTotal - d.seatsBooked));
});

test('GET /departures?tour= filters to one tour', async () => {
  const res = await fetch(`${baseUrl}/departures?tour=sunset-harbour-cruise`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.count, 2);
  assert.ok(body.departures.every((d) => d.tourId === 'sunset-harbour-cruise'));
});

test('GET /departures/:id shows a sold-out departure', async () => {
  const res = await fetch(`${baseUrl}/departures/dep-102`);
  assert.equal(res.status, 200);
  const departure = await res.json();
  assert.equal(departure.seatsLeft, 0);
  assert.equal(departure.soldOut, true);
});

test('GET /departures/:id returns JSON 404 for an unknown departure', async () => {
  const res = await fetch(`${baseUrl}/departures/dep-999`);
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.match(body.error, /not found/);
});

test('unknown routes return JSON 404, not HTML', async () => {
  const res = await fetch(`${baseUrl}/nope`);
  assert.equal(res.status, 404);
  assert.match(res.headers.get('content-type'), /application\/json/);
});
