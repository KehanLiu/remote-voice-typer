# Voice Input (iPhone -> OpenAI Transcribe -> Windows Typing)

## Files
- `server.py`: FastAPI backend for static page + `/transcribe`
- `agent.py`: Windows local typing agent (`/type`) (must run on native Windows)
- `index.html`: iPhone Safari recording page

## Windows Setup
This project is meant to run on native Windows PowerShell or CMD, not WSL.

1. Install Python:
   ```powershell
   winget install -e --id Python.Python.3.12
   ```
2. Install `uv`:
   ```powershell
   winget install -e --id astral-sh.uv
   ```
   If `winget` says `No package found matching input criteria`, try:
   ```powershell
   winget search uv
   winget install --id astral-sh.uv
   ```
3. Restart PowerShell and verify:
   ```powershell
   python --version
   uv --version
   ```
4. Go to this project folder:
   ```powershell
   cd C:\Users\<you>\projects\remote-voice-typer
   ```
5. Install project dependencies:
   ```powershell
   uv sync
   ```
   `uv sync` will create `.venv` automatically if needed, so you usually do not need to run `uv venv` first.
6. Install `ngrok`:
   ```powershell
   winget install -e --id Ngrok.Ngrok
   ```
7. Update `ngrok` and verify the version:
   ```powershell
   ngrok update
   ngrok version
   ```
   Use a current `ngrok` version. `ngrok` can reject old agents with `ERR_NGROK_121`. In one failure seen on April 21, 2026, `ngrok` `3.3.1` was rejected and that account required at least `3.20.0`.
8. Add your `ngrok` authtoken:
   Get your token from `https://dashboard.ngrok.com/get-started/your-authtoken`
   ```powershell
   ngrok config add-authtoken <YOUR_TOKEN>
   ```
9. Optional: activate the virtual environment:
   ```powershell
   .\.venv\Scripts\Activate.ps1
   ```
   You only need activation if you want to run `python` or `uvicorn` directly without `uv run`.
10. Optional: create a `.env` file in the project root. `server.py` will load it automatically.

## One-Click Start (Windows)
This is the default way to run the project after setup.

1. Ensure `.env` contains at least:
   - `OPENAI_API_KEY=...`
   - optional: `VOICE_INPUT_TOKEN=...`
   - recommended for remote use: `NGROK_BASIC_AUTH=myuser:mystrongpassword`
2. Double-click `start_voice_input.bat`.
3. It will automatically start:
   - `agent.py`
   - `server.py` via `uvicorn`
   - `ngrok http 8000`
4. It prints the HTTPS URL, copies it to clipboard, and writes it to `ngrok_url.txt`.
5. Keep that window open. Press `Ctrl+C` there to stop services started by the launcher.

Launcher logs are written to:
- `logs/agent.out.log`
- `logs/agent.err.log`
- `logs/backend.out.log`
- `logs/backend.err.log`
- `logs/ngrok.out.log`
- `logs/ngrok.err.log`

If the launcher says `ngrok is too old for this account`, run:
```powershell
ngrok update
ngrok version
```

## Optional Local URL Check
- On a device in the same LAN, this URL should load the page:
  ```
  http://<windows-lan-ip>:8000/
  ```
- On iPhone Safari, microphone capture is usually blocked on that HTTP LAN URL.
- For iPhone recording, use the HTTPS `ngrok` URL.

## Notes
- Keep API key only on the backend.
- iPhone Safari requires HTTPS or another secure context for microphone access.
- Command words supported in this version: `newline`, `backspace`, `send`.
- If you run backend and agent on the same Windows machine, keep `WINDOWS_AGENT_URL` as `http://127.0.0.1:8765/type`.
- For remote use, set `VOICE_INPUT_TOKEN` to require `X-Voice-Token` on `/transcribe`.
- For remote use, also set `NGROK_BASIC_AUTH` so `ngrok` asks for username and password before loading the page.
- Mic permission is requested once per page session and reused for later recordings.

## Troubleshooting
- If PowerShell blocks `.venv` activation:
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```
- If `ngrok` says `version too old` or `ERR_NGROK_121`:
  ```powershell
  ngrok update
  ngrok version
  ```
- If iPhone shows `Microphone needs a secure context` or `getUserMedia` errors:
  - Use the `ngrok` `https://...` URL, not `http://<windows-lan-ip>:8000/`.
- If backend logs `Audio file might be corrupted or unsupported`:
  - Hard refresh the iPhone page so the latest `index.html` is loaded:
    `https://<ngrok-url>/?v=4`
- If the page shows `401 Unauthorized`:
  - Check `VOICE_INPUT_TOKEN` on the server and the Access Token field on iPhone match exactly.

## Run (Same LAN, iPhone)
Use this if you want the manual three-terminal flow instead of the one-click launcher.

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
   # recommended for remote use
   $env:NGROK_BASIC_AUTH="myuser:mystrongpassword"
   uv run uvicorn server:app --host 0.0.0.0 --port 8000
   ```
3. In PowerShell terminal #3, create an HTTPS tunnel:
   ```powershell
   ngrok http 8000
   ```
4. Open the `https://...` forwarding URL shown by `ngrok` on iPhone Safari.
5. If token protection is enabled:
   - Enter the same token into `Access Token (if enabled)` on the page.
   - The token is saved in browser local storage on that iPhone.
