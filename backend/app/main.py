from __future__ import annotations

import secrets
import string
import uuid
from datetime import datetime, timezone
from typing import Annotated, Any, Optional

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import ExpiredSignatureError, InvalidTokenError

from .db import get_db, init_db
from .errors import (
    ACCOUNT_NOT_ACTIVE,
    BAD_REQUEST,
    DOMAIN_NOT_ALLOWED,
    EMAIL_TAKEN,
    FORBIDDEN,
    INVALID_CREDENTIALS,
    NOT_AUTHENTICATED,
    NOT_FOUND,
    REGISTRATION_LOCKED,
    TOKEN_EXPIRED,
    TOKEN_INVALID,
    USER_UNKNOWN,
    APIError,
    api_error_handler,
)
from .schemas import (
    AdminResetPasswordOut,
    AdminResetPasswordRequest,
    AdminUserUpdateRequest,
    AuthResponse,
    ChangePasswordRequest,
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
app.add_exception_handler(APIError, api_error_handler)
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
    # Fail closed before DB/admin seed if production secrets are unset/weak.
    settings.assert_secure_configuration()
    init_db()
    seed_admin()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "scootercheck-auth"}


def current_user(
    creds: Annotated[Optional[HTTPAuthorizationCredentials], Depends(bearer)],
) -> UserOut:
    if creds is None or not creds.credentials:
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "Nicht angemeldet",
            NOT_AUTHENTICATED,
        )
    try:
        payload = decode_access_token(creds.credentials)
    except ExpiredSignatureError as exc:
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "Token abgelaufen",
            TOKEN_EXPIRED,
        ) from exc
    except InvalidTokenError as exc:
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "Token ungültig",
            TOKEN_INVALID,
        ) from exc
    user = fetch_user_by_id(str(payload.get("sub", "")))
    if user is None:
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "Benutzer unbekannt",
            USER_UNKNOWN,
        )
    return user


def require_active(user: Annotated[UserOut, Depends(current_user)]) -> UserOut:
    if user.status != "active":
        raise APIError(
            status.HTTP_403_FORBIDDEN,
            f"Konto nicht freigeschaltet (Status: {user.status})",
            ACCOUNT_NOT_ACTIVE,
        )
    return user


def require_admin(user: Annotated[UserOut, Depends(require_active)]) -> UserOut:
    if user.role != "admin":
        raise APIError(status.HTTP_403_FORBIDDEN, "Nur Admin", FORBIDDEN)
    return user


def normalize_domain(raw: str) -> str:
    d = raw.strip().lower()
    if d.startswith("@"):
        d = d[1:]
    d = d.strip(".")
    if not d or "." not in d or " " in d or "@" in d:
        raise APIError(400, "Ungültige Domain (z. B. polizei.bayern.de)", BAD_REQUEST)
    return d


def email_domain(email: str) -> str:
    parts = email.strip().lower().split("@", 1)
    if len(parts) != 2 or not parts[1]:
        raise APIError(400, "Ungültige E-Mail", BAD_REQUEST)
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
        raise APIError(
            status.HTTP_403_FORBIDDEN,
            "Registrierung gesperrt: noch keine E-Mail-Domains freigegeben",
            REGISTRATION_LOCKED,
        )
    if not is_domain_allowed(domain):
        raise APIError(
            status.HTTP_403_FORBIDDEN,
            f"Domain @{domain} ist nicht freigegeben",
            DOMAIN_NOT_ALLOWED,
        )


@app.post("/auth/register", response_model=AuthResponse)
def register(body: RegisterRequest) -> AuthResponse:
    email = str(body.email).strip().lower()
    if fetch_user_by_email(email):
        raise APIError(
            status.HTTP_409_CONFLICT,
            "E-Mail bereits registriert",
            EMAIL_TAKEN,
        )
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
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "E-Mail oder Passwort falsch",
            INVALID_CREDENTIALS,
        )
    user = row_to_user(row)
    token = create_access_token(
        user_id=user.id, email=user.email, role=user.role, status=user.status
    )
    return AuthResponse(access_token=token, user=user)


@app.get("/auth/me", response_model=UserOut)
def me(user: Annotated[UserOut, Depends(current_user)]) -> UserOut:
    return user


@app.post("/auth/change-password", response_model=MessageOut)
def change_password(
    body: ChangePasswordRequest,
    user: Annotated[UserOut, Depends(current_user)],
) -> MessageOut:
    row = fetch_user_by_email(user.email)
    if row is None or not verify_password(body.current_password, row["password_hash"]):
        raise APIError(
            status.HTTP_401_UNAUTHORIZED,
            "Aktuelles Passwort falsch",
            INVALID_CREDENTIALS,
        )
    if body.current_password == body.new_password:
        raise APIError(400, "Neues Passwort muss sich unterscheiden", BAD_REQUEST)
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            "UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
            (hash_password(body.new_password), now, user.id),
        )
    return MessageOut(message="Passwort geändert")


def _temp_password(n: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits
    alphabet = alphabet.replace("O", "").replace("0", "").replace("l", "").replace("I", "")
    return "".join(secrets.choice(alphabet) for _ in range(n))


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


@app.post("/admin/users/{user_id}/enable", response_model=UserOut)
def enable_user(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> UserOut:
    """Unlock / reactivate a disabled or rejected user."""
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            """
            UPDATE users
            SET status = 'active', approved_at = COALESCE(approved_at, ?),
                approved_by = COALESCE(approved_by, ?), updated_at = ?
            WHERE id = ?
            """,
            (now, admin.id, now, user_id),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return user


def _admin_count(conn: Any) -> int:
    row = conn.execute(
        "SELECT COUNT(*) AS c FROM users WHERE role = 'admin' AND status = 'active'"
    ).fetchone()
    return int(row["c"])


@app.patch("/admin/users/{user_id}", response_model=UserOut)
def update_user(
    user_id: str,
    body: AdminUserUpdateRequest,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> UserOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")

    new_role = body.role if body.role is not None else target.role
    new_status = body.status if body.status is not None else target.status
    new_name = body.display_name if body.display_name is not None else target.display_name
    if body.display_name is not None:
        cleaned = body.display_name.strip()
        new_name = cleaned or None
    new_email = str(body.email).strip().lower() if body.email is not None else target.email

    if target.id == admin.id and (new_role != "admin" or new_status != "active"):
        raise HTTPException(
            status_code=400,
            detail="Eigenes Admin-Konto kann nicht herabgestuft oder gesperrt werden",
        )

    if new_email != target.email:
        if fetch_user_by_email(new_email):
            raise HTTPException(status_code=409, detail="E-Mail bereits vergeben")
        assert_email_allowed_for_registration(new_email)

    now = utc_now()
    with get_db() as conn:
        if target.role == "admin" and target.status == "active" and (
            new_role != "admin" or new_status != "active"
        ):
            if _admin_count(conn) <= 1:
                raise HTTPException(status_code=400, detail="Letzter aktiver Admin kann nicht entfernt werden")

        conn.execute(
            """
            UPDATE users
            SET email = ?, display_name = ?, role = ?, status = ?,
                approved_at = CASE
                    WHEN ? = 'active' AND status != 'active' THEN ?
                    WHEN ? != 'active' THEN NULL
                    ELSE approved_at
                END,
                approved_by = CASE
                    WHEN ? = 'active' AND status != 'active' THEN ?
                    WHEN ? != 'active' THEN NULL
                    ELSE approved_by
                END,
                updated_at = ?
            WHERE id = ?
            """,
            (
                new_email,
                new_name,
                new_role,
                new_status,
                new_status,
                now,
                new_status,
                new_status,
                admin.id,
                new_status,
                now,
                user_id,
            ),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return user


@app.delete("/admin/users/{user_id}", response_model=MessageOut)
def delete_user(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
) -> MessageOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    if target.id == admin.id:
        raise HTTPException(status_code=400, detail="Eigenes Konto kann nicht gelöscht werden")
    with get_db() as conn:
        if target.role == "admin" and target.status == "active" and _admin_count(conn) <= 1:
            raise HTTPException(status_code=400, detail="Letzter aktiver Admin kann nicht gelöscht werden")
        conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
    return MessageOut(message=f"Benutzer {target.email} gelöscht")


@app.post("/admin/users/{user_id}/reset-password", response_model=AdminResetPasswordOut)
def reset_password(
    user_id: str,
    admin: Annotated[UserOut, Depends(require_admin)],
    body: AdminResetPasswordRequest = AdminResetPasswordRequest(),
) -> AdminResetPasswordOut:
    target = fetch_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Benutzer nicht gefunden")
    requested = (body.new_password or None)
    temp = requested or _temp_password()
    now = utc_now()
    with get_db() as conn:
        conn.execute(
            "UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
            (hash_password(temp), now, user_id),
        )
    user = fetch_user_by_id(user_id)
    assert user is not None
    return AdminResetPasswordOut(
        message=f"Passwort für {user.email} zurückgesetzt (durch {admin.email})",
        temporary_password=None if requested else temp,
        user=user,
    )


@app.post("/admin/users/{user_id}/make-admin", response_model=UserOut)
def make_admin(
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
            SET role = 'admin', status = 'active',
                approved_at = COALESCE(approved_at, ?),
                approved_by = COALESCE(approved_by, ?),
                updated_at = ?
            WHERE id = ?
            """,
            (now, admin.id, now, user_id),
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
