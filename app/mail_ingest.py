from __future__ import annotations

import sys
import uuid
from email import policy
from email.parser import BytesParser
from email.utils import parsedate_to_datetime
from pathlib import Path
from datetime import datetime, timezone

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.db import get_conn, init_db


def extract_text(msg):
    text_parts = []
    html_parts = []

    if msg.is_multipart():
        for part in msg.walk():
            content_type = (part.get_content_type() or "").lower()
            if content_type not in ("text/plain", "text/html"):
                continue
            try:
                payload = part.get_payload(decode=True) or b""
                charset = part.get_content_charset() or "utf-8"
                decoded = payload.decode(charset, errors="replace")
            except Exception:
                decoded = ""
            if content_type == "text/plain":
                text_parts.append(decoded)
            elif content_type == "text/html":
                html_parts.append(decoded)
    else:
        content_type = (msg.get_content_type() or "").lower()
        try:
            payload = msg.get_payload(decode=True) or b""
            charset = msg.get_content_charset() or "utf-8"
            decoded = payload.decode(charset, errors="replace")
        except Exception:
            decoded = ""
        if content_type == "text/html":
            html_parts.append(decoded)
        else:
            text_parts.append(decoded)

    return "\n".join(text_parts).strip(), "\n".join(html_parts).strip()


def normalize_recipient(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    if "<" in text and ">" in text:
        text = text.split("<", 1)[1].split(">", 1)[0].strip()
    return text.lower()


def build_clean_raw(raw_bytes: bytes) -> str:
    clean_msg = BytesParser(policy=policy.default).parsebytes(raw_bytes)
    for header in ("Delivered-To", "X-Original-To", "Return-Path"):
        while header in clean_msg:
            del clean_msg[header]
    return clean_msg.as_string()


def main() -> int:
    init_db()
    raw = sys.stdin.buffer.read()
    if not raw:
        return 0

    msg = BytesParser(policy=policy.default).parsebytes(raw)

    to_addr = ""
    if len(sys.argv) > 1:
        to_addr = normalize_recipient(sys.argv[1])
    if not to_addr:
        to_addr = normalize_recipient(msg.get("X-Original-To") or "")
    if not to_addr:
        to_addr = normalize_recipient(msg.get("Delivered-To") or "")
    if not to_addr:
        to_addr = normalize_recipient(msg.get("To") or "")

    from_addr = str(msg.get("From") or "").strip()
    subject = str(msg.get("Subject") or "").strip()
    text_body, html_body = extract_text(msg)

    date_header = str(msg.get("Date") or "").strip()
    created_at = datetime.now(timezone.utc).isoformat()
    if date_header:
        try:
            dt = parsedate_to_datetime(date_header)
            if dt is not None:
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                created_at = dt.isoformat()
        except Exception:
            pass

    clean_raw = build_clean_raw(raw)

    conn = get_conn()
    try:
        conn.execute(
            """
            INSERT INTO mails (id, address, source, subject, text, html, raw, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(uuid.uuid4()),
                to_addr,
                from_addr,
                subject,
                text_body,
                html_body,
                clean_raw,
                created_at,
            ),
        )
        conn.commit()
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"mail_ingest failed: {exc}", file=sys.stderr)
        raise
