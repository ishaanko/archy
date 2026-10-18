import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer, narrationCatalog } from './server.mjs';

const proxyToken = 'test-proxy-token-at-least-24-characters';
async function withServer(config, fn) {
  const server = createServer(config);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { await fn(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}
const post = (url, body, token = proxyToken) => fetch(`${url}/narrate`, {
  method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
});
test('health reveals only configuration state', async () => {
  await withServer({}, async url => assert.deepEqual(await (await fetch(`${url}/health`)).json(), { configured: false }));
  assert.throws(() => createServer({ apiKey: 'secret' }), /ARCHY_PROXY_TOKEN/);
});
test('unauthorized and invalid script requests never call upstream', async () => {
  await withServer({ apiKey: 'secret', proxyToken, fetchImpl: () => assert.fail('Unexpected upstream request') }, async url => {
    assert.equal((await post(url, { script_id: 'welcome' }, 'wrong')).status, 401);
    for (const body of [{ script_id: 'unknown' }, { script_id: 'welcome', text: 'private' }, { script_id: '__proto__' }, null]) {
      assert.equal((await post(url, body)).status, 400);
    }
    assert.equal((await post(url, { script_id: 'a'.repeat(2100) })).status, 413);
  });
});
test('successful audio uses fixed upstream contract', async () => {
  await withServer({ apiKey: 'secret', proxyToken, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.x.ai/v1/tts');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.authorization, 'Bearer secret');
    assert.deepEqual(JSON.parse(options.body), { text: narrationCatalog.welcome, voice_id: 'eve', language: 'en', speed: 0.85 });
    return new Response(new Uint8Array([73, 68, 51]), { headers: { 'content-type': 'audio/mpeg' } });
  } }, async url => {
    const response = await post(url, { script_id: 'welcome' });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'audio/mpeg');
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([73, 68, 51]));
  });
});
test('upstream failures and oversized audio return sanitized errors', async () => {
  for (const fetchImpl of [
    async () => { throw new Error('secret internal detail'); },
    async () => new Response('secret internal detail', { status: 429 }),
    async () => new Response(new Uint8Array(2 * 1024 * 1024 + 1), { headers: { 'content-type': 'audio/mpeg' } }),
  ]) {
    await withServer({ apiKey: 'secret', proxyToken, fetchImpl }, async url => {
      const response = await post(url, { script_id: 'welcome' });
      assert.equal(response.status, 502);
      assert.deepEqual(await response.json(), { error: 'Narration service unavailable' });
    });
  }
});
