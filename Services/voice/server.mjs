import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const measurements = {
  fullLength: 'Measure from the back of your heel to the tip of your longest toe.',
  truncatedLength: 'Measure from the back of your heel to the center of the ball behind your big toe.',
  dorsumHeight: 'Find half of your full foot length. At that point, measure vertically from the supporting surface to the top of your foot.',
  width: 'Measure across the widest part of your forefoot, between the first and fifth metatarsal heads.',
  seatedNavicular: 'Sit with knees bent about ninety degrees and feet flat. Find and mark the bony bump on the inner midfoot, below and forward of the inner ankle. Measure vertically from the floor to that mark.',
  standingNavicular: 'Stand relaxed with weight evenly shared. Keep the same marked navicular landmark and measure from the floor to the mark. Ask a helper to read the ruler without shifting your weight.',
};
export const narrationCatalog = Object.freeze({
  welcome: 'Welcome to Archy. Let us take this one gentle step at a time.',
  add: 'You are in the plus tab. Choose manual measurements for guided ruler measurements and calculated results. Or choose guided photos for inner side, top and rear views of each foot. Photos remain on your iPhone until you explicitly choose to share an insole request.',
  ...Object.fromEntries(['left', 'right'].map(side => [`photos.${side}`, `Photographing your ${side} foot. For the inner side view, frame the inside of your foot at floor level, including heel and toes. For the top view, photograph straight down with the heel and longest toe visible. For the rear view, frame the heel from behind with the camera level and ankle visible. Ask a helper if needed. Then switch feet for the other three photos. Photos are saved locally; scan analysis is not connected.`])),
  ...Object.fromEntries(['left', 'right'].flatMap(side => Object.entries(measurements).map(([field, text]) => [`measurement.${side}.${field}`, `${side} foot. ${text} Keep the ruler straight and avoid compressing the skin. Enter your measurement in the units selected on screen.`]))),
  'exercise.setup': 'Sit comfortably with your bare foot flat and knee above your ankle. Gently draw the base of your big toe toward your heel to lift the arch. Keep both planted and your toes long. Do not curl your toes. Breathe, then release. Stop if it hurts.',
  'exercise.hold': 'Hold gently. Keep toes long and breathe.',
  'exercise.relax': 'Relax your foot completely.',
  'exercise.complete': 'Practice complete. Check how your feet feel.',
  'balance.setup': 'Stand beside a solid counter on a stable floor. Keep fingertip support. Place one foot in front of the other, heel toward toe. Keep your eyes open on a fixed point. Stop if you feel pain, dizziness or unsteadiness. Choose the seated lesson if standing balance feels unsafe.',
  'balance.hold': 'Hold with fingertip support. Look at one point and breathe.',
  'balance.relax': 'Rest in a comfortable stance and keep your support. Follow the leading foot shown for the next hold.',
  'balance.complete': 'Practice complete. Stay supported as you finish.',
  premium: 'Explore the movement studio for short-foot and supported balance lessons. AstroFit lets you prepare an insole quote request. Space Insole explores a future concept for your selected gravity environment. Requests stay local until you choose to share. Billing and checkout are not available. Accessibility is always included.',
  measurements: 'Follow the measurement guide and enter your results when ready.',
  space: 'SpaceLab lets you explore foot geometry and gravity environments. Gravity does not predict a change in your measured arch. You can explore a Space Insole design request or read the research.',
});

const MAX_BODY = 2048;
const MAX_AUDIO = 2 * 1024 * 1024;
const json = (res, status, value) => {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(value));
};
const tokenMatches = (header, token) => {
  const actual = Buffer.from(header ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
};

export function createServer({ apiKey = '', proxyToken = '', fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  if (apiKey && proxyToken.length < 24) throw new Error('ARCHY_PROXY_TOKEN must contain at least 24 characters when XAI_API_KEY is configured.');
  const configured = Boolean(apiKey && proxyToken.length >= 24);
  const server = http.createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') return json(res, 200, { configured });
    if (req.method !== 'POST' || req.url !== '/narrate') return json(res, 404, { error: 'Not found' });
    if (!proxyToken || !tokenMatches(req.headers.authorization, proxyToken)) return json(res, 401, { error: 'Unauthorized' });
    if (!configured) return json(res, 503, { error: 'Narration is not configured' });
    if (req.headers['content-type']?.split(';')[0].trim().toLowerCase() !== 'application/json') return json(res, 415, { error: 'Expected application/json' });
    let body;
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY) { json(res, 413, { error: 'Request too large' }); return; }
        chunks.push(chunk);
      }
      body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch { return json(res, 400, { error: 'Invalid request' }); }
    if (!body || Array.isArray(body) || typeof body !== 'object' || Object.keys(body).length !== 1 || typeof body.script_id !== 'string' || !Object.hasOwn(narrationCatalog, body.script_id)) {
      return json(res, 400, { error: 'Unknown script or invalid request' });
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const onClose = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', onClose);
    try {
      const upstream = await fetchImpl('https://api.x.ai/v1/tts', {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({ text: narrationCatalog[body.script_id], voice_id: 'eve', language: 'en', speed: 0.85 }),
      });
      if (!upstream.ok || !upstream.body || upstream.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'audio/mpeg') {
        await upstream.body?.cancel();
        return json(res, 502, { error: 'Narration service unavailable' });
      }
      const reader = upstream.body.getReader();
      const chunks = [];
      let size = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_AUDIO) { await reader.cancel(); throw new Error('Audio limit'); }
        chunks.push(Buffer.from(value));
      }
      if (!size) throw new Error('Empty audio');
      res.writeHead(200, { 'content-type': 'audio/mpeg', 'cache-control': 'no-store', 'content-length': size });
      res.end(Buffer.concat(chunks));
    } catch { if (!res.destroyed) json(res, 502, { error: 'Narration service unavailable' }); }
    finally { clearTimeout(timer); res.off('close', onClose); }
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  createServer({ apiKey: process.env.XAI_API_KEY, proxyToken: process.env.ARCHY_PROXY_TOKEN }).listen(port, '127.0.0.1', () => {
    console.log(`Archy narration proxy listening on 127.0.0.1:${port}`);
  });
}
