"""Add streaming chat replies without modifying the CowAgent image."""

import time


def install():
    from common import i18n
    from common.log import logger
    from bridge.reply import Reply, ReplyType
    from bridge.context import ContextType
    from config import conf
    from models.chatgpt.chat_gpt_bot import ChatGPTBot

    if getattr(ChatGPTBot, "_cow_streaming_patch_installed", False):
        return

    original_reply = ChatGPTBot.reply

    def emit(callback, event_type, data=None):
        try:
            callback({"type": event_type, "data": data or {}})
        except Exception as exc:
            logger.warning("[StreamingPatch] channel event failed: %s", exc)

    def stream_reply(self, query, context, callback):
        session_id = context["session_id"]
        session = self.sessions.session_query(query, session_id)
        api_key = context.get("openai_api_key")
        selected_model = context.get("gpt_model")
        call_args = self.args.copy()
        if selected_model:
            call_args["model"] = selected_model
        timeout = call_args.pop("request_timeout", None) or call_args.pop("timeout", None)

        started_at = time.monotonic()
        first_token_at = None
        content = ""
        last_error = None

        for attempt in range(2):
            emit(callback, "turn_start")
            attempt_content = ""
            try:
                chunks = self._http_client.chat_completions(
                    api_key=api_key or None,
                    timeout=timeout,
                    messages=session.messages,
                    stream=True,
                    **call_args,
                )
                for chunk in chunks:
                    error = chunk.get("error") if isinstance(chunk, dict) else None
                    if error:
                        if isinstance(error, dict):
                            error = error.get("message") or str(error)
                        raise RuntimeError(str(error))

                    choices = chunk.get("choices") or []
                    if not choices:
                        continue
                    choice = choices[0]
                    delta = choice.get("delta") or choice.get("message") or {}
                    piece = delta.get("content") or ""
                    if not isinstance(piece, str) or not piece:
                        continue

                    if first_token_at is None:
                        first_token_at = time.monotonic()
                    attempt_content += piece
                    emit(callback, "message_update", {"delta": piece})

                if attempt_content:
                    content = attempt_content
                    break
                last_error = RuntimeError("stream completed without text content")
            except Exception as exc:
                last_error = exc
                if attempt_content:
                    content = attempt_content + "\n\n[响应中断，请重试]"
                    emit(callback, "message_update", {"delta": "\n\n[响应中断，请重试]"})
                    break

            if attempt == 0:
                logger.warning("[StreamingPatch] empty/failed stream, retrying once: %s", last_error)
                time.sleep(1)

        emit(callback, "message_end", {"tool_calls": []})

        if not content:
            self.sessions.clear_session(session_id)
            logger.error("[StreamingPatch] stream failed: %s", last_error)
            message = i18n.t("模型暂时没有返回内容，请重试", "The model returned no content. Please try again.")
            return Reply(ReplyType.ERROR, message)

        self.sessions.session_reply(content, session_id)
        finished_at = time.monotonic()
        first_token_ms = int(((first_token_at or finished_at) - started_at) * 1000)
        total_ms = int((finished_at - started_at) * 1000)
        logger.info(
            "[StreamingPatch] reply complete: first_token_ms=%s, total_ms=%s, chars=%s",
            first_token_ms,
            total_ms,
            len(content),
        )
        return Reply(ReplyType.TEXT, content)

    def patched_reply(self, query, context=None):
        callback = context.get("on_event") if context is not None else None
        clear_commands = conf().get("clear_memory_commands", ["#清除记忆"])
        is_management_command = query in clear_commands or query in ("#清除所有", "#更新配置")
        if (
            context is not None
            and context.type == ContextType.TEXT
            and callable(callback)
            and not is_management_command
        ):
            logger.info("[StreamingPatch] streaming query enabled")
            return stream_reply(self, query, context, callback)
        return original_reply(self, query, context)

    ChatGPTBot.reply = patched_reply
    ChatGPTBot._cow_streaming_patch_installed = True
    logger.info("[StreamingPatch] installed")
