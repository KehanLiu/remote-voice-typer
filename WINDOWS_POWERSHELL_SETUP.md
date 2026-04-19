# Windows PowerShell Setup (Python + uv + venv)

## 1) Install Python
```powershell
winget install -e --id Python.Python.3.12
```

## 2) Install uv
```powershell
winget install -e --id Astral-sh.uv
```

## 3) Restart PowerShell and verify
```powershell
python --version
uv --version
```

## 4) Go to this project folder
```powershell
cd C:\path\to\voice_input
```

## 5) Create virtual environment with uv
```powershell
uv venv
```

## 6) Activate virtual environment
```powershell
.\.venv\Scripts\Activate.ps1
```

## 7) Install project dependencies
```powershell
uv sync
```

## 8) Install ngrok (for iPhone HTTPS access)
```powershell
winget install -e --id Ngrok.Ngrok
```

## 9) Add ngrok authtoken (one-time)
Get your token from: `https://dashboard.ngrok.com/get-started/your-authtoken`
```powershell
ngrok config add-authtoken <YOUR_TOKEN>
```

## 10) Run the app commands (three terminals)
Terminal #1:
```powershell
uv run python agent.py
```
Terminal #2:
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
Terminal #3:
```powershell
ngrok http 8000
```

## 11) Open on iPhone Safari
- Open the ngrok `https://...` forwarding URL.
- If `VOICE_INPUT_TOKEN` is set, enter the same token in `Access Token (if enabled)`.
- `http://<windows-lan-ip>:8000/` can load the page on LAN, but iPhone mic usually requires HTTPS.
- Mic permission should be requested only once per page session.

## 12) Optional one-click launcher
After setup is complete, you can use one click:
- Double-click [start_voice_input.bat](c:/Users/Kehan/projects/voice_input/start_voice_input.bat)
- It starts agent, backend, and ngrok automatically.
- It prints and copies the ngrok HTTPS URL.
- Keep that window open; press `Ctrl+C` to stop everything.
- To enable ngrok login prompt in one-click mode, set one of these in `.env`:
  - `NGROK_BASIC_AUTH=myuser:mystrongpassword`
  - or both `NGROK_BASIC_AUTH_USER=myuser` and `NGROK_BASIC_AUTH_PASS=mystrongpassword`

## If activation is blocked
Run once:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## If ngrok is too old
```powershell
ngrok update
ngrok version
```

## If page shows 401 Unauthorized
- Check `VOICE_INPUT_TOKEN` in backend terminal #2 and iPhone page token field match exactly.
