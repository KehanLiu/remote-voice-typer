# Voice Input (iPhone -> OpenAI Transcribe -> Windows Typing)

## Files
- `server.py`: FastAPI backend for static page + `/transcribe`
- `agent.py`: Windows local typing agent (`/type`) (must run on native Windows)
- `index.html`: iPhone Safari recording page

## Setup
1. Install dependencies with `uv`:
   ```powershell
   uv sync
   ```
2. Set env vars:
   ```powershell
   $env:OPENAI_API_KEY="your_key"
   # optional
   $env:TRANSCRIBE_MODEL="gpt-4o-mini-transcribe"
   $env:WINDOWS_AGENT_URL="http://127.0.0.1:8765/type"
   # recommended for remote use: protect /transcribe
   $env:VOICE_INPUT_TOKEN="a-long-random-secret"
   # recommended for remote use: ngrok basic auth
   $env:NGROK_BASIC_AUTH="myuser:mystrongpassword"
   ```
3. Optional: create a `.env` file in the project root. `server.py` will load it automatically.
4. Install `ngrok` (needed for HTTPS on iPhone Safari):
   ```powershell
   winget install -e --id Ngrok.Ngrok
   ```
5. Add your ngrok authtoken (one-time):
   ```powershell
   ngrok config add-authtoken <YOUR_TOKEN>
   ```

## Where To Run
- `agent.py` must run on native Windows (PowerShell/CMD), not WSL.
- `server.py` in this project setup should also run on native Windows.
- Recommended: run both `agent.py` and `server.py` from PowerShell on the same machine.

## Run (Same LAN, iPhone)
1. In PowerShell terminal #1, run the typing agent:
   ```powershell
   uv run python agent.py
   ```
2. In PowerShell terminal #2, run the backend:
   ```powershell
   $env:OPENAI_API_KEY="your_key"
   # optional
   $env:TRANSCRIBE_MODEL="gpt-4o-mini-transcribe"
   $env:WINDOWS_AGENT_URL="http://127.0.0.1:8765/type"
   # recommended for remote use
   $env:VOICE_INPUT_TOKEN="a-long-random-secret"
   uv run uvicorn server:app --host 0.0.0.0 --port 8000
   ```
3. In PowerShell terminal #3, create an HTTPS tunnel:
   ```powershell
   ngrok http 8000
   ```
4. Open the `https://...` forwarding URL shown by ngrok on iPhone Safari.
5. If token protection is enabled:
- Enter the same token into `Access Token (if enabled)` on the page.
- The token is saved in browser local storage on that iPhone.

## One-Click Start (Windows)
If you prefer one click instead of three terminals:
1. Ensure `.env` contains at least:
   - `OPENAI_API_KEY=...`
   - optional: `VOICE_INPUT_TOKEN=...`
   - recommended for remote use: `NGROK_BASIC_AUTH=myuser:mystrongpassword`
2. Double-click [start_voice_input.bat](c:/Users/Kehan/projects/voice_input/start_voice_input.bat)
3. It will automatically start:
   - `agent.py`
   - `server.py` (`uvicorn`)
   - `ngrok http 8000`
4. It prints the HTTPS URL, copies it to clipboard, and writes it to:
   - `ngrok_url.txt`
5. Keep that window open. Press `Ctrl+C` there to stop all services.

Launcher logs are written to:
- `logs/agent.log`
- `logs/backend.log`
- `logs/ngrok.log`

## Optional Local URL Check
- On a device in the same LAN, this URL should load the page:
   ```
   http://<windows-lan-ip>:8000/
   ```
- On iPhone Safari, microphone capture is usually blocked on that HTTP LAN URL.
- For iPhone recording, use the HTTPS ngrok URL.

## Notes
- Keep API key only on backend.
- iPhone Safari requires HTTPS/secure context for microphone access.
- Command words supported in this version: `newline`, `backspace`, `send`.
- If you run backend and agent on the same Windows machine, keep `WINDOWS_AGENT_URL` as `http://127.0.0.1:8765/type`.
- For remote use, set `VOICE_INPUT_TOKEN` to require `X-Voice-Token` on `/transcribe`.
- For remote use, also set `NGROK_BASIC_AUTH` so ngrok asks username/password before loading the page.
- Mic permission is requested once per page session and reused for later recordings.

## Troubleshooting
- If iPhone shows `Microphone needs a secure context` or `getUserMedia` errors:
  - Use the ngrok `https://...` URL, not `http://<windows-lan-ip>:8000/`.
- If ngrok says `version too old`:
  ```powershell
  ngrok update
  ngrok version
  ```
- If backend logs `Audio file might be corrupted or unsupported`:
  - Hard refresh the iPhone page so the latest `index.html` is loaded:
    `https://<ngrok-url>/?v=4`
- If the page shows `401 Unauthorized`:
  - Check `VOICE_INPUT_TOKEN` on server and the Access Token field on iPhone match exactly.
