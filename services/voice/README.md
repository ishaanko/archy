# Archy narration proxy demo

## Live on the archy Vercel project

- Endpoint: `https://tryarchy.vercel.app/api/narrate`. `POST` narrates; `GET` returns `{"configured": true|false}`.
- Code: `sim/api/narrate.mjs` is a thin Vercel function that imports `createHandler` from `server.mjs` here. Scripts, limits and auth live only in `server.mjs`.
- To change what Grok says, edit `narrationCatalog` in `server.mjs`, run `node --test server.test.mjs`, and push to `main`. Vercel redeploys when `sim/` or `services/voice/` changes.
- Secrets are Vercel production env vars marked sensitive: `XAI_API_KEY` and `ARCHY_PROXY_TOKEN`. Get the proxy token from Ishaan privately; never commit either. Preview deployments have no secrets, so narration only works on production.
- In the app: Accessibility, Grok connection, enter the endpoint and the proxy token, save, then enable Grok.
- Check it end to end (charges a small xAI request):

  ```sh
  curl -sS -o /tmp/welcome.mp3 -w '%{http_code} %{content_type}\n' -X POST https://tryarchy.vercel.app/api/narrate \
    -H "Authorization: Bearer $ARCHY_PROXY_TOKEN" -H 'Content-Type: application/json' -d '{"script_id":"welcome"}'
  ```

## Run locally

Requires Node 20 or later. No dependencies. Run `node server.mjs` and test with `node --test server.test.mjs`.

## Connecting an existing host

`createHandler(config)` exports the same authenticated request handler used by
`createServer(config)`, without starting a listener. Import it into your existing
server-side Node route with `apiKey: process.env.XAI_API_KEY` and
`proxyToken: process.env.ARCHY_PROXY_TOKEN`. Keep the incoming request as a raw
Node stream (disable any automatic JSON body parser). The handler accepts paths
`/narrate` and `/health`; if your framework mounts it at `/api/narrate`, normalize
the request path to `/narrate` in the adapter. For Web Request/Response frameworks,
adapt the contract to the native route API rather than passing a parsed body to
the Node-stream handler. Preserve the fixed script allowlist and size limits.

Use the existing site's deployment settings. No new hosting project or root
directory changes are needed. Configure secrets as server-only environment
variables, never public frontend variables. The local `.env.local` is Git-ignored
and must not be uploaded. Generate a separate random app token of at least 24
characters (for example `openssl rand -hex 32`) and enter that token, not the xAI
key, in the app. Deploy, verify health, then test one authenticated narration.
Health confirms configuration only; it does not verify xAI credits or key validity.

The app accepts any HTTPS endpoint whose path ends in `/narrate`, including
`https://EXISTING-SITE/api/narrate`. After deployment, enter this URL and the
proxy token in Accessibility → Grok connection, save and enable Grok. This is
instruction narration, not a realtime microphone conversation.

Without credentials, `GET http://127.0.0.1:8787/health` returns `{"configured":false}`. Live voice is intentionally unconfigured; local narration can remain available in the app.

To enable live voice, set `XAI_API_KEY` on the server and a distinct, randomly generated `ARCHY_PROXY_TOKEN` containing at least 24 characters. Optionally set `PORT` (default 8787). The server binds only to `127.0.0.1`. Never embed the xAI API key in the app or source control. Store the separate proxy token in the app's Keychain; manually configure the development proxy URL and token in settings. The iOS app accepts only HTTPS URLs ending in `/narrate`; put this local service behind your HTTPS development gateway. A physical device needs an appropriately secured reachable proxy, since its loopback address refers to itself. In the app, open Today → Accessibility or Premium → Accessibility, enter the URL and separate service token, save, then explicitly enable “Use Grok for public instructions.” Saving alone does not connect. “Try voice instructions” tests narration; request failures use on-device speech. The app does not record microphone audio or provide live conversation.

`POST /narrate` requires `Authorization: Bearer <ARCHY_PROXY_TOKEN>` and `Content-Type: application/json`. Its JSON body contains exactly one key: `{"script_id":"welcome"}`. Successful responses contain raw MP3 bytes with `Content-Type: audio/mpeg` and `Cache-Control: no-store`. No user text, quiz answers, measurements, or photos are accepted or sent to xAI. Scripts are fixed in `narrationCatalog`; IDs include `welcome`, `add`, `photos.left`, `photos.right`, `exercise.setup/hold/relax/complete`, `balance.setup/hold/relax/complete`, `premium`, `measurements`, `space`, and `measurement.{left|right}.{field}` for the six fixed measurement fields in `server.mjs`. Instruction contents are fixed on the server.

The upstream request is `POST https://api.x.ai/v1/tts` with server-side Bearer authentication and `{text, voice_id:"eve", language:"en", speed:0.85}`. Requests are limited to 2 KB, upstream audio to 2 MB, and upstream requests to 15 seconds. Redirects are refused. Errors are sanitized; payloads and credentials are never logged. Tests inject fetch and make no charged upstream calls.

This is a local demo, not a public service. Public deployment needs TLS, per-user authentication and authorization, rate limits, abuse prevention, billing and spending controls, and operational review. A shared app token alone is insufficient for public deployment.

API contract verified against [xAI Text to Speech documentation](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech). Live xAI synthesis has not been exercised without credentials.
