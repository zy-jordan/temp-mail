from __future__ import annotations

import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from app.config import settings
from app.db import get_conn, init_db

_STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI(title="temp-mail")


class NewAddressRequest(BaseModel):
    enablePrefix: bool = True
    name: str
    domain: str


def check_admin(x_admin_auth: str | None) -> None:
    if x_admin_auth != settings.admin_password:
        raise HTTPException(status_code=401, detail="unauthorized")


@app.on_event("startup")
def startup() -> None:
    init_db()


@app.get("/")
def root():
    return FileResponse(_STATIC_DIR / "index.html")


@app.get("/health")
def health():
    return {"ok": True, "db_path": str(settings.db_path), "domain": settings.domain}


@app.post("/admin/new_address")
def new_address(
    body: NewAddressRequest,
    x_admin_auth: str | None = Header(default=None),
):
    check_admin(x_admin_auth)

    local_part = body.name.strip().lower()
    domain = body.domain.strip().lower()
    if not local_part or not domain:
        raise HTTPException(status_code=400, detail="invalid address")

    address = f"{local_part}@{domain}"
    address_id = str(uuid.uuid4())
    created_at = datetime.now(timezone.utc).isoformat()

    conn = get_conn()
    try:
        conn.execute(
            """
            INSERT OR IGNORE INTO addresses (id, address, local_part, domain, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (address_id, address, local_part, domain, created_at),
        )
        conn.commit()

        row = conn.execute(
            "SELECT id, address FROM addresses WHERE address = ?",
            (address,),
        ).fetchone()
    finally:
        conn.close()

    return {
        "address": row["address"],
        "address_id": row["id"],
        "id": row["id"],
    }


@app.get("/admin/addresses")
def list_addresses(
    x_admin_auth: str | None = Header(default=None),
):
    check_admin(x_admin_auth)

    conn = get_conn()
    try:
        rows = conn.execute(
            "SELECT id, address, local_part, domain, created_at FROM addresses ORDER BY created_at DESC"
        ).fetchall()
    finally:
        conn.close()

    return {
        "results": [
            {
                "id": r["id"],
                "address": r["address"],
                "localPart": r["local_part"],
                "domain": r["domain"],
                "createdAt": r["created_at"],
            }
            for r in rows
        ]
    }


@app.get("/admin/mails")
def list_mails(
    address: str | None = Query(default=None),
    limit: int = Query(default=20),
    offset: int = Query(default=0),
    x_admin_auth: str | None = Header(default=None),
):
    check_admin(x_admin_auth)

    limit = max(1, min(limit, 100))
    offset = max(0, offset)

    conn = get_conn()
    try:
        if address:
            rows = conn.execute(
                """
                SELECT id, address, source, subject, text, html, raw, created_at
                FROM mails
                WHERE address = ?
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                (address.lower(), limit, offset),
            ).fetchall()
        else:
            rows = conn.execute(
                """
                SELECT id, address, source, subject, text, html, raw, created_at
                FROM mails
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                (limit, offset),
            ).fetchall()
    finally:
        conn.close()

    return {
        "results": [
            {
                "id": r["id"],
                "address": r["address"],
                "source": r["source"],
                "subject": r["subject"],
                "text": r["text"],
                "html": r["html"],
                "raw": r["raw"],
                "createdAt": r["created_at"],
            }
            for r in rows
        ]
    }


@app.get("/admin/mails/{mail_id}")
def get_mail(
    mail_id: str,
    x_admin_auth: str | None = Header(default=None),
):
    check_admin(x_admin_auth)

    conn = get_conn()
    try:
        row = conn.execute(
            """
            SELECT id, address, source, subject, text, html, raw, created_at
            FROM mails
            WHERE id = ?
            """,
            (mail_id,),
        ).fetchone()
    finally:
        conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="not found")

    return {
        "id": row["id"],
        "address": row["address"],
        "source": row["source"],
        "subject": row["subject"],
        "text": row["text"],
        "html": row["html"],
        "raw": row["raw"],
        "createdAt": row["created_at"],
    }


app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")
