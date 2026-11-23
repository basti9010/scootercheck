"""Phase 2.1 job ownership unit tests."""
from __future__ import annotations

import unittest

from fastapi import HTTPException

import job_auth as ja


class JobOwnershipTests(unittest.TestCase):
    def test_jwt_owner_can_access_own_job(self) -> None:
        auth = {"auth": "jwt", "userId": "u1", "email": "a@example.com", "role": "user"}
        job = {"ownerPrincipal": "user:u1", "createdByUserId": "u1"}
        self.assertTrue(ja.can_access_job(job, auth))
        self.assertEqual(ja.require_job_access(job, auth), job)

    def test_jwt_user_b_cannot_access_a(self) -> None:
        auth_b = {"auth": "jwt", "userId": "u2", "email": "b@example.com", "role": "user"}
        job = {"ownerPrincipal": "user:u1", "createdByUserId": "u1", "jobId": "secret"}
        self.assertFalse(ja.can_access_job(job, auth_b))
        with self.assertRaises(HTTPException) as ctx:
            ja.require_job_access(job, auth_b)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertEqual(ctx.exception.detail, "job not found")

    def test_unauthenticated_style_open_only_in_dev(self) -> None:
        job = {"ownerPrincipal": "user:u1"}
        self.assertFalse(ja.can_access_job(job, {"auth": "jwt", "userId": "other"}))

    def test_admin_jwt_can_access(self) -> None:
        auth = {"auth": "jwt", "userId": "admin1", "role": "admin"}
        job = {"ownerPrincipal": "user:u1"}
        self.assertTrue(ja.can_access_job(job, auth))

    def test_api_token_not_admin_by_default(self) -> None:
        """Phase 2.2H: shared API_TOKEN must not grant admin unless explicitly enabled."""
        import os

        prev = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
        try:
            auth = {"auth": "api_token", "adminToken": False}
            job = {"ownerPrincipal": "user:u1"}
            self.assertFalse(ja.api_token_grants_admin())
            self.assertFalse(ja.is_admin(auth))
            self.assertFalse(ja.can_access_job(job, auth))
        finally:
            if prev is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev

    def test_api_token_admin_compat_opt_in(self) -> None:
        import os

        prev = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        os.environ["API_TOKEN_GRANTS_ADMIN"] = "1"
        try:
            auth = {"auth": "api_token", "adminToken": False}
            job = {"ownerPrincipal": "user:u1"}
            self.assertTrue(ja.api_token_grants_admin())
            self.assertTrue(ja.is_admin(auth))
            self.assertTrue(ja.can_access_job(job, auth))
        finally:
            if prev is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev

    def test_api_token_admin_disabled_requires_ownership(self) -> None:
        import os

        prev_g = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        prev_t = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ["API_TOKEN_GRANTS_ADMIN"] = "0"
        os.environ["TRUST_API_TOKEN_CLIENT_ID"] = "1"
        try:
            auth = {"auth": "api_token", "clientId": "ios-a", "adminToken": False}
            job_a = {"ownerPrincipal": "apitoken-client:ios-a"}
            job_b = {"ownerPrincipal": "apitoken-client:ios-b"}
            self.assertFalse(ja.is_admin(auth))
            self.assertTrue(ja.can_access_job(job_a, auth))
            self.assertFalse(ja.can_access_job(job_b, auth))
            # Dedicated adminToken still admin
            self.assertTrue(ja.is_admin({"auth": "api_token", "adminToken": True}))
        finally:
            if prev_g is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev_g
            if prev_t is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev_t

    def test_api_token_without_client_id_has_no_owner_principal(self) -> None:
        auth = {"auth": "api_token"}
        self.assertIsNone(ja.resolve_owner_principal(auth))
        fields = ja.ownership_fields_for_new_job(auth)
        self.assertIsNone(fields["ownerPrincipal"])
        self.assertIn("admin-only", fields.get("ownerLegacyNote", ""))

    def test_api_token_client_id_not_trusted_by_default(self) -> None:
        """Phase 2.2H.1: spoofable Client-Id must not own jobs under shared API_TOKEN."""
        import os

        prev = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
        try:
            auth = ja.enrich_auth_with_client_id({"auth": "api_token"}, "ios-device-1")
            fields = ja.ownership_fields_for_new_job(auth)
            self.assertIsNone(fields["ownerPrincipal"])
            self.assertIsNone(ja.resolve_owner_principal({"auth": "api_token", "clientId": "ios-device-1"}))
            # Even matching historical principal is denied without trust flag
            job = {"ownerPrincipal": "apitoken-client:ios-device-1"}
            self.assertFalse(ja.can_access_job(job, {"auth": "api_token", "clientId": "ios-device-1"}))
        finally:
            if prev is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev

    def test_api_token_with_client_id_owns_job_when_trust_enabled(self) -> None:
        import os

        prev = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ["TRUST_API_TOKEN_CLIENT_ID"] = "1"
        try:
            auth = ja.enrich_auth_with_client_id({"auth": "api_token"}, "ios-device-1")
            fields = ja.ownership_fields_for_new_job(auth)
            self.assertEqual(fields["ownerPrincipal"], "apitoken-client:ios-device-1")
            auth_user = {"auth": "api_token", "clientId": "ios-device-1"}
            self.assertEqual(ja.resolve_owner_principal(auth_user), "apitoken-client:ios-device-1")
        finally:
            if prev is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev

    def test_manipulated_client_id_cannot_steal_job(self) -> None:
        import os

        prev_g = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        prev_t = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ["API_TOKEN_GRANTS_ADMIN"] = "0"
        os.environ["TRUST_API_TOKEN_CLIENT_ID"] = "1"
        try:
            job = {"ownerPrincipal": "apitoken-client:real-device"}
            attacker = {"auth": "api_token", "clientId": "attacker-device", "adminToken": False}
            self.assertFalse(ja.can_access_job(job, attacker))
        finally:
            if prev_g is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev_g
            if prev_t is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev_t

    def test_known_victim_client_id_cannot_steal_when_untrusted(self) -> None:
        """Critical: shared token + known foreign Client-Id must not open the job."""
        import os

        prev_g = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        prev_t = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ["API_TOKEN_GRANTS_ADMIN"] = "0"
        os.environ["TRUST_API_TOKEN_CLIENT_ID"] = "0"
        try:
            job = {"ownerPrincipal": "apitoken-client:victim-device"}
            attacker = {"auth": "api_token", "clientId": "victim-device", "adminToken": False}
            self.assertFalse(ja.can_access_job(job, attacker))
        finally:
            if prev_g is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev_g
            if prev_t is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev_t

    def test_jwt_non_admin_cannot_be_treated_as_admin(self) -> None:
        self.assertFalse(ja.is_admin({"auth": "jwt", "userId": "u1", "role": "user"}))

    def test_legacy_job_jwt_email_match(self) -> None:
        job = {"createdBy": "a@example.com", "createdByUserId": None}  # no ownerPrincipal
        auth = {"auth": "jwt", "userId": "u1", "email": "a@example.com", "role": "user"}
        self.assertTrue(ja.can_access_job(job, auth))

    def test_legacy_job_jwt_userid_match(self) -> None:
        job = {"createdByUserId": "u1"}
        auth = {"auth": "jwt", "userId": "u1", "email": "x@y.z", "role": "user"}
        self.assertTrue(ja.can_access_job(job, auth))

    def test_legacy_job_denied_for_stranger(self) -> None:
        job = {"createdBy": "a@example.com", "createdByUserId": "u1"}
        auth = {"auth": "jwt", "userId": "u9", "email": "other@example.com", "role": "user"}
        self.assertFalse(ja.can_access_job(job, auth))

    def test_legacy_job_api_token_without_client_denied_when_admin_disabled(self) -> None:
        import os

        prev = os.environ.get("API_TOKEN_GRANTS_ADMIN")
        os.environ["API_TOKEN_GRANTS_ADMIN"] = "0"
        try:
            job = {"createdBy": "a@example.com", "createdByUserId": "u1"}
            auth = {"auth": "api_token", "adminToken": False}
            self.assertFalse(ja.is_admin(auth))
            self.assertFalse(ja.can_access_job(job, auth))
        finally:
            if prev is None:
                os.environ.pop("API_TOKEN_GRANTS_ADMIN", None)
            else:
                os.environ["API_TOKEN_GRANTS_ADMIN"] = prev

    def test_missing_job_404(self) -> None:
        with self.assertRaises(HTTPException) as ctx:
            ja.require_job_access(None, {"auth": "jwt", "userId": "u1", "role": "user"})
        self.assertEqual(ctx.exception.status_code, 404)

    def test_invalid_client_id_rejected(self) -> None:
        with self.assertRaises(HTTPException):
            ja.enrich_auth_with_client_id({"auth": "api_token"}, "../evil")

    def test_new_jwt_job_fields(self) -> None:
        auth = {"auth": "jwt", "userId": "abc", "email": "a@b.c", "role": "user"}
        fields = ja.ownership_fields_for_new_job(auth)
        self.assertEqual(fields["ownerPrincipal"], "user:abc")
        self.assertEqual(fields["createdByUserId"], "abc")
        self.assertEqual(fields["ownerAuthKind"], "jwt")


if __name__ == "__main__":
    unittest.main()
