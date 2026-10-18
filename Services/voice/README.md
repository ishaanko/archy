# Archy narration proxy demo

Requires Node 20 or later. No dependencies. Run `node server.mjs` and test with `node --test server.test.mjs`.

Without credentials, `GET http://127.0.0.1:8787/health` returns `{"configured":false}`. Live voice is intentionally unconfigured; local narration can remain available in the app.

To enable live voice, set `XAI_API_KEY` on the server and a distinct, randomly generated `ARCHY_PROXY_TOKEN` containing at least 24 characters. Optionally set `PORT` (default 8787). The server binds only to `127.0.0.1`. Never embed the xAI API key in the app or source control. Store the separate proxy token in the app's Keychain; manually configure the development proxy URL and token in settings. The iOS app accepts only HTTPS URLs ending in `/narrate`; put this local service behind your HTTPS development gateway. A physical device needs an appropriately secured reachable proxy, since its loopback address refers to itself. In the app, open Today → Accessibility or Premium → Accessibility, enter the URL and separate service token, save, then explicitly enable “Use Grok for public instructions.” Saving alone does not connect. “Try voice instructions” tests narration; request failures use on-device speech. The app does not record microphone audio or provide live conversation.

`POST /narrate` requires `Authorization: Bearer <ARCHY_PROXY_TOKEN>` and `Content-Type: application/json`. Its JSON body contains exactly one key: `{"script_id":"welcome"}`. Successful responses contain raw MP3 bytes with `Content-Type: audio/mpeg` and `Cache-Control: no-store`. No user text, quiz answers, measurements, or photos are accepted or sent to xAI. Scripts are fixed in `narrationCatalog`; IDs include `welcome`, `add`, `photos.left`, `photos.right`, `exercise.setup/hold/relax/complete`, `balance.setup/hold/relax/complete`, `premium`, `measurements`, `space`, and `measurement.{left|right}.{field}` for the six fixed measurement fields in `server.mjs`. Instruction contents are fixed on the server.

The upstream request is `POST https://api.x.ai/v1/tts` with server-side Bearer authentication and `{text, voice_id:"eve", language:"en", speed:0.85}`. Requests are limited to 2 KB, upstream audio to 2 MB, and upstream requests to 15 seconds. Redirects are refused. Errors are sanitized; payloads and credentials are never logged. Tests inject fetch and make no charged upstream calls.

This is a local demo, not a public service. Public deployment needs TLS, per-user authentication and authorization, rate limits, abuse prevention, billing and spending controls, and operational review. A shared app token alone is insufficient for public deployment.

API contract verified against [xAI Text to Speech documentation](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech). Live xAI synthesis has not been exercised without credentials.
