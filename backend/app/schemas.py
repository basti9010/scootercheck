from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field

UserStatus = Literal["pending", "active", "rejected", "disabled"]
UserRole = Literal["user", "admin"]


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: Optional[str] = Field(default=None, max_length=80)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class AdminResetPasswordRequest(BaseModel):
    """If new_password is omitted, a temporary password is generated."""
    new_password: Optional[str] = Field(default=None, min_length=8, max_length=128)


class UserOut(BaseModel):
    id: str
    email: EmailStr
    display_name: Optional[str] = None
    role: UserRole
    status: UserStatus
    created_at: str
    updated_at: str
    approved_at: Optional[str] = None


class AdminResetPasswordOut(BaseModel):
    message: str
    temporary_password: Optional[str] = None
    user: UserOut


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class MessageOut(BaseModel):
    message: str


class UsersListOut(BaseModel):
    users: list[UserOut]


class DomainIn(BaseModel):
    domain: str = Field(min_length=3, max_length=253)


class DomainOut(BaseModel):
    domain: str
    created_at: str
    created_by: Optional[str] = None


class DomainsListOut(BaseModel):
    domains: list[DomainOut]
