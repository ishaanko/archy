// Audition tool: renders one sample sentence in every xAI TTS voice to ~/Downloads/archy-voices/<voice>.mp3.
// Usage: XAI_API_KEY=... node samples.mjs   (the key is only sent to api.x.ai and is never printed)
import { mkdir, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { TTS_SPEED } from './server.mjs';

const apiKey = process.env.XAI_API_KEY;
if (!apiKey) {
  console.error('Set XAI_API_KEY to render voice samples, for example: XAI_API_KEY=... node samples.mjs');
  process.exit(1);
}

const sample = "Hi, I'm your coach. Sit comfortably, take a breath, and gently lift your arch. Nice and easy. Hold there, and breathe.";
const headers = { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' };

const listed = await fetch('https://api.x.ai/v1/tts/voices', { headers });
if (!listed.ok) {
  console.error(`Could not list voices (HTTP ${listed.status}).`);
  process.exit(1);
}
const voices = (await listed.json()).voices.map(voice => voice.voice_id);

const outDir = join(homedir(), 'Downloads', 'archy-voices');
await mkdir(outDir, { recursive: true });
for (const voice of voices) {
  const response = await fetch('https://api.x.ai/v1/tts', {
    method: 'POST', headers,
    body: JSON.stringify({ text: sample, voice_id: voice, language: 'en', speed: TTS_SPEED }),
  });
  if (!response.ok) {
    console.error(`${voice}: failed (HTTP ${response.status})`);
    continue;
  }
  await writeFile(join(outDir, `${voice}.mp3`), Buffer.from(await response.arrayBuffer()));
  console.log(`${voice}: ${join(outDir, `${voice}.mp3`)}`);
}
