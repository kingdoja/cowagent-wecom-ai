"""Smoke-test the local CowAgent streaming adapter against the configured relay."""

import sys
import time


sys.path.insert(0, "/app")

from config import load_config


load_config()

from bridge.context import Context, ContextType
from bridge.reply import ReplyType
from cowagent_streaming_patch import install
from models.chatgpt.chat_gpt_bot import ChatGPTBot


install()

started_at = time.monotonic()
first_update_at = None
update_count = 0


def on_event(event):
    global first_update_at, update_count
    if event.get("type") == "message_update":
        update_count += 1
        if first_update_at is None:
            first_update_at = time.monotonic()


query = "用中文分五点说明如何提高工作效率，每点一句话，总字数控制在200字以内。"
context = Context(ContextType.TEXT, query)
context["session_id"] = "cowagent-streaming-smoke-test"
context["on_event"] = on_event

reply = ChatGPTBot().reply(query, context)
finished_at = time.monotonic()

if reply.type != ReplyType.TEXT or not str(reply.content).strip():
    raise SystemExit("Streaming smoke test failed: no text reply")
if first_update_at is None or update_count < 2:
    raise SystemExit(
        f"Streaming smoke test failed: expected multiple updates, got {update_count}"
    )

print(
    "Streaming smoke test passed: "
    f"first_token={first_update_at - started_at:.2f}s, "
    f"total={finished_at - started_at:.2f}s, "
    f"updates={update_count}, chars={len(str(reply.content))}"
)
