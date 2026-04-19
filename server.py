import logging
import os
import tempfile
from typing import Literal

import requests
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from openai import OpenAI
from dotenv import load_dotenv

logging.getLogger("dotenv.main").setLevel(logging.ERROR)
load_dotenv()
logger = logging.getLogger(__name__)


OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
AGENT_URL = os.environ.get("WINDOWS_AGENT_URL", "http://127.0.0.1:8765/type")
TRANSCRIBE_MODEL = os.environ.get("TRANSCRIBE_MODEL", "gpt-4o-mini-transcribe")
VOICE_INPUT_TOKEN = os.environ.get("VOICE_INPUT_TOKEN", "").strip()

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY is required")

client = OpenAI(api_key=OPENAI_API_KEY)
app = FastAPI(title="Voice Input Server")

# Keep this permissive for local LAN testing from iPhone Safari.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def apply_mode_postprocess(text: str, mode: Literal["normal", "code"]) -> str:
    text = text.strip()
    if mode == "normal":
        return text
    # code mode: avoid adding spacing/punctuation changes
    return text


def apply_command(text: str) -> dict | None:
    command_map = {
        "newline": {"action": "newline"},
        "backspace": {"action": "backspace"},
        "send": {"action": "enter"},
    }
    normalized = text.strip()
    return command_map.get(normalized)


@app.get("/")
def index() -> FileResponse:
    return FileResponse("index.html")


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "model": TRANSCRIBE_MODEL,
        "agent_url": AGENT_URL,
        "token_required": bool(VOICE_INPUT_TOKEN),
    }


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    mode: Literal["normal", "code"] = Form("normal"),
    x_voice_token: str | None = Header(default=None),
) -> dict:
    if VOICE_INPUT_TOKEN and x_voice_token != VOICE_INPUT_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized: missing or invalid X-Voice-Token")

    suffix = ".webm"
    if file.filename and "." in file.filename:
        suffix = f".{file.filename.rsplit('.', 1)[-1]}"

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(await file.read())
            temp_path = tmp.name

        with open(temp_path, "rb") as audio_file:
            transcript = client.audio.transcriptions.create(
                model=TRANSCRIBE_MODEL,
                file=audio_file,
            )

        raw_text = (transcript.text or "").strip()
        text = apply_mode_postprocess(raw_text, mode=mode)
        cmd = apply_command(text)

        if cmd:
            payload = {"mode": mode, **cmd}
        else:
            payload = {"mode": mode, "action": "type", "text": text}

        if text:
            try:
                requests.post(AGENT_URL, json=payload, timeout=2)
            except requests.RequestException:
                # Keep transcription response successful even when local agent is offline.
                pass

        return {"text": text, "mode": mode, "command": cmd}
    except Exception as exc:
        logger.exception("Transcription failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        if temp_path:
            try:
                os.remove(temp_path)
            except OSError:
                pass
