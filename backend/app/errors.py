"""Structured auth API errors for iOS taxonomy (status + code + detail)."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

# Stable codes — keep in sync with iOS AuthErrorCode (see research/p0-auth).
INVALID_CREDENTIALS = "invalid_credentials"
NOT_AUTHENTICATED = "not_authenticated"
TOKEN_INVALID = "token_invalid"
TOKEN_EXPIRED = "token_expired"
USER_UNKNOWN = "user_unknown"
FORBIDDEN = "forbidden"
ACCOUNT_NOT_ACTIVE = "account_not_active"
EMAIL_TAKEN = "email_taken"
DOMAIN_NOT_ALLOWED = "domain_not_allowed"
REGISTRATION_LOCKED = "registration_locked"
VALIDATION_ERROR = "validation_error"
BAD_REQUEST = "bad_request"
NOT_FOUND = "not_found"
SERVER_ERROR = "server_error"


class APIError(HTTPException):
    """HTTPException that also emits a stable machine-readable `code` field."""

    def __init__(
        self,
        status_code: int,
        detail: str,
        code: str,
        headers: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=detail, headers=headers)
        self.code = code


def api_error_response(exc: APIError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "code": exc.code},
        headers=dict(exc.headers) if exc.headers else None,
    )


async def api_error_handler(_: Request, exc: APIError) -> JSONResponse:
    return api_error_response(exc)
