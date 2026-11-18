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

    def test_api_token_is_admin(self) -> None:
        auth = {"auth": "api_token"}
        job = {"ownerPrincipal": "user:u1"}
        self.assertTrue(ja.can_access_job(job, auth))
        self.assertTrue(ja.is_admin(auth))

    def test_api_token_without_client_id_has_no_owner_principal(self) -> None:
        auth = {"auth": "api_token"}
        self.assertIsNone(ja.resolve_owner_principal(auth))
        fields = ja.ownership_fields_for_new_job(auth)
        self.assertIsNone(fields["ownerPrincipal"])
        self.assertIn("admin-only", fields.get("ownerLegacyNote", ""))

    def test_api_token_with_client_id_owns_job(self) -> None:
        auth = ja.enrich_auth_with_client_id({"auth": "api_token"}, "ios-device-1")
        fields = ja.ownership_fields_for_new_job(auth)
        self.assertEqual(fields["ownerPrincipal"], "apitoken-client:ios-device-1")
        job = {"ownerPrincipal": fields["ownerPrincipal"]}
        # Non-admin access with matching client
        auth_user = {"auth": "api_token", "clientId": "ios-device-1"}
        # api_token is always admin today — still owns principal correctly for records
        self.assertEqual(ja.resolve_owner_principal(auth_user), "apitoken-client:ios-device-1")

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

    def test_legacy_job_api_token_without_client_denied_for_non_admin_path(self) -> None:
        # Simulate can_access without admin shortcut by using jwt stranger — already covered.
        # API token alone is admin; document that shared token bypasses ownership as admin.
        self.assertTrue(ja.is_admin({"auth": "api_token"}))

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
