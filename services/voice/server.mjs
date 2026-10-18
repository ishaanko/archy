import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const measurements = {
  fullLength: 'Measure from the back of your heel to the tip of your longest toe.',
  truncatedLength: 'Measure from the back of your heel to the ball of your foot, just behind your big toe.',
  dorsumHeight: "First, find the halfway point of your foot's length. Right there, measure straight up from the floor to the top of your foot.",
  width: 'Measure across the widest part of your forefoot, from the bony bump on the inside to the bump on the outside.',
  seatedNavicular: "Sit with your knees bent about ninety degrees and your feet flat. Find the bony bump on the inner side of your midfoot, just below and ahead of your ankle bone, and mark it. Then measure straight up from the floor to the mark.",
  standingNavicular: "Now stand up, relaxed, with your weight shared evenly. Keep the same mark, and measure from the floor to it. It helps to have someone else read the ruler, so you don't shift your weight.",
};
// Bump `VoiceCache.version` in ios/Archy/Settings/GuidanceVoice.swift whenever a line, TTS_VOICE or TTS_SPEED changes,
// so installed apps drop their saved audio.
export const narrationCatalog = Object.freeze({
  welcome: "Hi, welcome to Archy. We'll take this one easy step at a time.",
  'onboarding.welcome': "Hi, welcome to Archy. We'll check your arch and design an insole just for you. Tap Get started whenever you're ready.",
  'onboarding.goal': 'So, what brings you here? Tap whichever one fits you best.',
  'onboarding.background': "Tell us a little about your feet. Pick left, right, or both. Then let us know if a clinician has ever given you a diagnosis.",
  'onboarding.pain': 'Any pain today? Slide the scale from one to ten, or tap no pain. You can also skip this one.',
  'onboarding.done': "You're all set. Tap Scan your feet to begin.",
  add: "This is the plus tab. Choose manual measurements if you'd like to use a ruler and get calculated results, or guided photos to capture the inside, top and back of each foot. Your photos stay on your iPhone unless you choose to share an insole request.",
  ...Object.fromEntries(['left', 'right'].map(side => [`photos.${side}`, `Let's photograph your ${side} foot. For the inside view, get down at floor level and frame your whole foot from the inner side, heel to toes. For the top view, point the camera straight down so your heel and longest toe are both in the shot. For the back view, frame your heel from behind, with the camera level and your ankle in view. A helper can make this easier. Then switch feet and repeat. Your photos stay on your phone, and scan analysis isn't connected yet.`])),
  ...Object.fromEntries(['left', 'right'].flatMap(side => Object.entries(measurements).map(([field, text]) => [`measurement.${side}.${field}`, `${side} foot. ${text} Keep the ruler straight, and try not to press into your skin. Then enter the number in the units on screen.`]))),
  'exercise.setup': "Sit comfortably with your bare foot flat on the floor and your knee right above your ankle. Gently draw the base of your big toe back toward your heel, so your arch lifts. Keep your toes long and relaxed, and don't curl them. Breathe, then let go. If anything hurts, stop.",
  'exercise.hold': 'Hold gently. Keep your toes long, and breathe.',
  'exercise.relax': 'And relax. Let your foot go completely.',
  'exercise.complete': 'Nice work. Take a moment to notice how your feet feel.',
  'balance.setup': "Stand next to a solid counter on a stable floor, and keep your fingertips on it for support. Put one foot directly in front of the other, heel to toe, and look at a spot ahead of you. If you feel any pain, dizziness or unsteadiness, stop. The seated lesson is always there if standing doesn't feel safe.",
  'balance.hold': 'Hold there, with your fingertips on the counter. Keep your eyes on one spot, and breathe.',
  'balance.relax': 'Rest for a moment, and keep your hand on the counter. For the next hold, switch to the front foot shown on screen.',
  'balance.complete': 'Nice work. Stay supported while you finish up.',
  'heelraise.setup': "Stand facing a solid counter, with your hands resting on it and your feet about hip-width apart. Rise slowly onto the balls of your feet, pause, then lower slowly. Keep your weight over your big toes. If you feel unsteady or anything hurts, stop.",
  'heelraise.rise': 'Rise up onto the balls of your feet, and pause.',
  'heelraise.lower': 'And lower slowly.',
  'heelraise.complete': 'Nice work. Give your calves a little shake.',
  'toeyoga.setup': "Sit with your bare foot flat on the floor. Lift just your big toe, and keep the four small toes down. Then switch: lower it, and lift only the four small toes. Go gently, and stop if anything hurts or cramps.",
  'toeyoga.big': 'Lift your big toe. Keep the small toes down.',
  'toeyoga.small': 'Now the four small toes. Keep your big toe down.',
  'toeyoga.complete': 'Nice work. Take a moment to notice how your feet feel.',
  premium: "Here you can explore the movement studio, with short foot and supported balance lessons. AstroFit helps you prepare an insole quote request. And Space Insole is a future concept for the gravity environment you pick. Requests stay on your phone until you choose to share them. Billing and checkout aren't available yet, and accessibility is always included.",
  measurements: "Follow the measurement guide, and enter your results when you're ready.",
  space: "SpaceLab is where you can explore foot shape and gravity environments. Gravity doesn't predict any change in your measured arch. From here you can explore a Space Insole design request, or read the research.",
});

// xAI TTS voice and pace. `ara` is documented as warm and friendly; 1.0 is the natural pace (the API range is 0.7 to 1.5).
// Run `node samples.mjs` to audition every voice.
export const TTS_VOICE = 'ara';
export const TTS_SPEED = 1.0;

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

export function createHandler({ apiKey = '', proxyToken = '', fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  if (apiKey && proxyToken.length < 24) throw new Error('ARCHY_PROXY_TOKEN must contain at least 24 characters when XAI_API_KEY is configured.');
  const configured = Boolean(apiKey && proxyToken.length >= 24);
  return async (req, res) => {
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
        body: JSON.stringify({ text: narrationCatalog[body.script_id], voice_id: TTS_VOICE, language: 'en', speed: TTS_SPEED }),
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
  };
}

export function createServer(config = {}) {
  const server = http.createServer(createHandler(config));
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
