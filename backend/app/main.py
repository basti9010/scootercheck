from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated, Any, Optional

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError

from .db import get_db, init_db
from .schemas import (
    AuthResponse,
    DomainIn,
    DomainOut,
    DomainsListOut,
    LoginRequest,
    MessageOut,
    RegisterRequest,
    UserOut,
    UsersListOut,
)
from .security import create_access_token, decode_access_token, hash_password, verify_password
from .settings import settings

app = FastAPI(title=settings.app_name, version="1.0.0")
bearer = HTTPBearer(auto_error=False)

origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if origins == ["*"] else origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def row_to_user(row: Any) -> UserOut:
    return UserOut(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        role=row["role"],
        status=row["status"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        approved_at=row["approved_at"],
    )


def fetch_user_by_id(user_id: str) -> Optional[UserOut]:
    with get_db() as conn:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return row_to_user(row) if row else None


def fetch_user_by_email(email: str) -> Optional[Any]:
    with get_db() as conn:
        return conn.execute(
            "SELECT * FROM users WHERE email = ? COLLATE NOCASE",
            (email.strip(),),
        ).fetchone()


def seed_admin() -> None:
    email = settings.admin_email.strip().lower()
    existing = fetch_user_by_email(email)
    if existing:
        with get_db() as conn:
            conn.execute(
                """
                UPDATE users
                SET role = 'admin', status = 'active', updated_at = ?
                WHERE id = ?
                """,
                (utc_now(), existing["id"]),
            )
        return

    now = utc_now()
    with get_db() as conn:
        conn.execute(
            """
            INSERT INTO users (
                id, email, password_hash, display_name, role, status,
                created_at, updated_at, approved_at, approved_by
            ) VALUES (?, ?, ?, ?, 'admin', 'active', ?, ?, ?, ?)
            """,
            (
                str(uuid.uuid4()),
                email,
                hash_password(settings.admin_password),
                settings.admin_name,
                now,
                now,
                now,
                "seed",
            ),
        )


@app.on_event("startup")
def on_startup() -> None:
    init_db()
    seed_admin()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "scootercheck-auth"}


def current_user(
    creds: Annotated[Optional[HTTPAuthorizationCredentials], Depends(bearer)],
) -> UserOut:
    if creds is None or not creds.credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Nicht angemeldet")
    try:
        payload = decode_access_token(creds.credentials)
    except InvalidTokenError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token ungültig") from exc
    user = fetch_user_by_id(str(payload.get("sub", "")))
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Benutzer unbekannt")
    return user


def require_active(user: Annotated[UserOut, Depends(current_user)]) -> UserOut:
    if user.status != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Konto nicht freigeschaltet (Status: {user.status})",
        )
    return user


def require_admin(user: Annotated[UserOut, Depends(require_active)]) -> UserOut:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Nur Admin")
    return user


def normalize_domain(raw: str) -> str:
    d = raw.strip().lower()
    if d.startswith("@"):
        d = d[1:]
    d = d.strip(".")
    if not d or "." not in d or " " in d or "@" in d:
        raise HTTPException(status_code=400, detail="Ungültige Domain (z. B. polizei.bayern.de)")
    return d


def email_domain(email: str) -> str:
    parts = email.strip().lower().split("@", 1)
    if len(parts) != 2 or not parts[1]:
        raise HTTPException(status_code=400, detail="Ungültige E-Mail")
    return parts[1]


def is_domain_allowed(domain: str) -> bool:
    with get_db() as conn:
        row = conn.execute(
            "SELECT 1 FROM allowed_domains WHERE domain = ? COLLATE NOCASE",
            (domain,),
        ).fetchone()
    return row is not None


def assert_email_allowed_for_registration(email: str) -> None:
    """Admin-Seed-E-Mail immer erlaubt; sonst nur freigegebene Domains."""
    if email.strip().lower() == settings.admin_email.strip().lower():
        return
    domain = email_domain(email)
    with get_db() as conn:
        count = conn.execute("SELECT COUNT(*) AS c FROM allowed_domains").fetchone()["c"]
    if count == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Registrierung gesperrt: noch keine E-Mail-Domains freigegeben",
        )
    if not is_domain_allowed(domain):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Domain @{domain} ist nicht freigegeben",
        )


@app.post("/auth/register", response_model=AuthResponse)
def register(body: RegisterRequest) -> AuthResponse:
    email = str(body.email).strip().lower()
    if fetch_user_by_email(email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="E-Mail bereits registriert")
    assert_email_allowed_for_registration(email)

    now = utc_now()
    user_id = str(uuid.uuid4())
    name = (body.display_name or "").strip() or None
    with get_db() as conn:
        conn.execute(
            """
            INSERT INTO users (
                id, email, password_hash, display_name, role, status,
                created_at, updated_at, approved_at, approved_by
            ) VALUES (?, ?, ?, ?, 'user', 'pending', ?, ?, NULL, NULL)
            """,
            (user_id, email, hash_password(body.password), name, now, now),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    token = create_access_token(
        user_id=user.id, email=user.email, role=user.role, status=user.status
    )
    return AuthResponse(access_token=token, user=user)


@app.post("/auth/login", response_model=AuthResponse)
def login(body: LoginRequest) -> AuthResponse:
    row = fetch_user_by_email(str(body.email))
    if row is None or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="E-Mail oder Passwort falsch")
    user = row_to_user(row)
    token = create_access_token(
        user_id=user.id, email=user.email, role=user.role, status=user.status
    )
    return AuthResponse(access_token=token, user=user)


@app.get("/auth/me", response_model=UserOut)
def me(user: Annotated[UserOut, Depends(current_user)]) -> UserOut:
    return user


@app.get("/admin/users", response_model=UsersListOut)
def list_users(
    _: Annotated[UserOut, Depends(require_admin)],
    status_filter: Optional[str] = None,
) -> UsersListOut:
    with get_db() as conn:
        if status_filter:
            rows = conn.execute(
                "SELECT * FROM users WHERE status = ? ORDER BY created_at DESC",
                (status_filter,),
            ).fetchall()
        else:
            rows = conn.execute("SELECT * FROM users ORDER BY created_at DESC").fetchall()
    return UsersListOut(users=[row_to_user(r) for r in rows])


@app.post("/admin/users/{user_id}/approve", response_model=UserOut)
def approve_user(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> UserOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            """
            UPDATE users
            SET status = 'active', approved_at = ?, approved_by = ?, updated_at = ?
            WHERE id = ?
            """,
            (now, admin.id, now, user_id),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return user


@app.post("/admin/users/{user_id}/reject", response_model=UserOut)
def reject_user(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> UserOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    if target.role == "admin":
        raise HTTPException(status_code=400, detail="Admin kann nicht abgelehnt werden")
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            """
            UPDATE users
            SET status = 'rejected', updated_at = ?, approved_at = NULL, approved_by = ?
            WHERE id = ?
            """,
            (now, admin.id, user_id),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return user


@app.post("/admin/users/{user_id}/disable", response_model=UserOut)
def disable_user(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> UserOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    if target.id == admin.id:
        raise HTTPException(status_code=400, detail="Eigenes Admin-Konto nicht deaktivierbar")
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            "UPDATE users SET status = 'disabled', updated_at = ? WHERE id = ?",
            (now, user_id),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return user


@app.get("/session/check", response_model=MessageOut)
def session_check(_: Annotated[UserOut, Depends(require_active)]) -> MessageOut:
    return MessageOut(message="ok")


@app.get("/admin/domains", response_model=DomainsListOut)
def list_domains(_: Annotated[UserOut, Depends(require_admin)]) -> DomainsListOut:
    with get_db() as conn:
        rows = conn.execute(
            "SELECT domain, created_at, created_by FROM allowed_domains ORDER BY domain COLLATE NOCASE"
        ).fetchall()
    return DomainsListOut(
        domains=[
            DomainOut(domain=r["domain"], created_at=r["created_at"], created_by=r["created_by"])
            for r in rows
        ]
    )


@app.post("/admin/domains", response_model=DomainOut)
def add_domain(
    body: DomainIn,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> DomainOut:
    domain = normalize_domain(body.domain)
    now = utc_now()
    with get_db() as conn:
        existing = conn.execute(
            "SELECT domain FROM allowed_domains WHERE domain = ? COLLATE NOCASE",
            (domain,),
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Domain bereits freigegeben")
        conn.execute(
            "INSERT INTO allowed_domains (domain, created_at, created_by) VALUES (?, ?, ?)",
            (domain, now, admin.id),
        )
    return DomainOut(domain=domain, created_at=now, created_by=admin.id)


@app.delete("/admin/domains/{domain}", response_model=MessageOut)
def remove_domain(
    domain: str,
    _: Annotated[UserOut, Depends(require_admin)],
) -> MessageOut:
    cleaned = normalize_domain(domain)
    with get_db() as conn:
        cur = conn.execute(
            "DELETE FROM allowed_domains WHERE domain = ? COLLATE NOCASE",
            (cleaned,),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Domain nicht gefunden")
    return MessageOut(message=f"@{cleaned} entfernt")
