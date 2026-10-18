// Vercel function for Grok instruction narration used by the iOS app.
// POST /api/narrate with `Authorization: Bearer <ARCHY_PROXY_TOKEN>` and {"script_id": "..."} returns audio/mpeg.
// GET /api/narrate returns {"configured": bool}. The contract, script catalog and limits live in services/voice/server.mjs.
import { createHandler } from '../../services/voice/server.mjs';

let handler;

export default function narrate(req, res) {
  handler ??= createHandler({
    apiKey: process.env.XAI_API_KEY ?? '',
    proxyToken: process.env.ARCHY_PROXY_TOKEN ?? '',
  });
  // The shared handler routes on /narrate and /health; Vercel mounts this file at /api/narrate.
  req.url = req.method === 'GET' ? '/health' : '/narrate';
  return handler(req, res);
}
