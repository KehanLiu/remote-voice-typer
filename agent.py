import platform
import time
from typing import Literal

import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel


app = FastAPI(title="Voice Input Agent")


def _is_wsl() -> bool:
    return "microsoft" in platform.release().lower()


if platform.system() != "Windows" or _is_wsl():
    raise RuntimeError(
        "agent.py must run on native Windows (not WSL/Linux). "
        "Run this project with Windows Python/PowerShell."
    )

import pyautogui


class Payload(BaseModel):
    action: Literal["type", "newline", "backspace", "enter"] = "type"
    text: str = ""
    mode: Literal["normal", "code"] = "normal"


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/type")
def type_text(payload: Payload) -> dict:
    # Brief delay so user can switch focus to target window.
    time.sleep(0.2)

    if payload.action == "newline":
        pyautogui.press("enter")
    elif payload.action == "backspace":
        pyautogui.press("backspace")
    elif payload.action == "enter":
        pyautogui.press("enter")
    else:
        suffix = " " if payload.mode == "normal" else ""
        pyautogui.write(payload.text + suffix, interval=0.01)

    return {"ok": True}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765)
