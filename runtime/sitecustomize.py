"""Redact sensitive CowAgent startup values before handlers persist them."""

import logging
import re


_original_factory = logging.getLogRecordFactory()
_environment_override = re.compile(
    r"(\[INIT\] override config by environ args: [^=]+=).*"
)
_dictionary_secret = re.compile(
    r"('(?:[^']*(?:api_key|secret|password|token|aes_key|bot_id|app_id|client_id|corp_id)[^']*)':\s*)'[^']*'",
    re.IGNORECASE,
)


def _redact(message: str) -> str:
    message = _environment_override.sub(r"\1<redacted>", message)
    return _dictionary_secret.sub(r"\1'<redacted>'", message)


def _record_factory(*args, **kwargs):
    record = _original_factory(*args, **kwargs)
    try:
        record.msg = _redact(record.getMessage())
        record.args = ()
    except Exception:
        pass
    return record


logging.setLogRecordFactory(_record_factory)
