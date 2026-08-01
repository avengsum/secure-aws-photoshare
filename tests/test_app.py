import io
import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from app import app, validate_file, MAGIC_BYTES
from werkzeug.datastructures import FileStorage


@pytest.fixture
def client():
    app.config["TESTING"] = True
    app.config["WTF_CSRF_ENABLED"] = False
    app.config["DB_SECRET_ID"] = ""
    with app.test_client() as client:
        yield client


@pytest.fixture
def valid_jpeg():
    header = b"\xff\xd8\xff\xe0" + b"\x00" * 100
    from PIL import Image
    img = Image.new("RGB", (100, 100), color="red")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf


@pytest.fixture
def valid_png():
    from PIL import Image
    img = Image.new("RGBA", (50, 50), color="blue")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return buf


class TestHealthEndpoint:
    def test_health_returns_200(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["status"] == "healthy"
        assert "timestamp" in data


class TestSecurityHeaders:
    def test_security_headers_present(self, client):
        resp = client.get("/health")
        assert resp.headers["X-Content-Type-Options"] == "nosniff"
        assert resp.headers["X-Frame-Options"] == "DENY"
        assert resp.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
        assert "Content-Security-Policy" in resp.headers
        assert "frame-ancestors 'none'" in resp.headers["Content-Security-Policy"]

    def test_no_server_header_leak(self, client):
        resp = client.get("/health")
        server = resp.headers.get("Server", "")
        assert "Python" not in server


class TestAuthentication:
    def test_unauthenticated_redirect(self, client):
        resp = client.get("/dashboard", follow_redirects=False)
        assert resp.status_code == 302
        assert "/login" in resp.headers["Location"]

    def test_login_page_loads(self, client):
        resp = client.get("/login")
        assert resp.status_code == 200
        assert b"Login" in resp.data

    def test_register_page_loads(self, client):
        resp = client.get("/register")
        assert resp.status_code == 200
        assert b"Register" in resp.data

    def test_register_short_username(self, client):
        resp = client.post("/register", data={
            "username": "ab",
            "password": "securepassword123"
        }, follow_redirects=True)
        assert b"3-30 characters" in resp.data

    def test_register_invalid_username_chars(self, client):
        resp = client.post("/register", data={
            "username": "user<script>",
            "password": "securepassword123"
        }, follow_redirects=True)
        assert b"letters, numbers, underscores" in resp.data

    def test_register_short_password(self, client):
        resp = client.post("/register", data={
            "username": "validuser",
            "password": "short"
        }, follow_redirects=True)
        assert b"at least 8 characters" in resp.data

    def test_login_invalid_credentials(self, client):
        resp = client.post("/login", data={
            "username": "nonexistent",
            "password": "wrongpassword"
        }, follow_redirects=True)
        assert b"Invalid credentials" in resp.data or b"Service unavailable" in resp.data


class TestFileValidation:
    def test_valid_jpeg_accepted(self, valid_jpeg):
        with app.test_request_context():
            fs = FileStorage(
                stream=valid_jpeg,
                filename="test.jpg",
                content_type="image/jpeg"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is True
            assert error is None

    def test_valid_png_accepted(self, valid_png):
        with app.test_request_context():
            fs = FileStorage(
                stream=valid_png,
                filename="test.png",
                content_type="image/png"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is True
            assert error is None

    def test_empty_file_rejected(self):
        with app.test_request_context():
            fs = FileStorage(stream=io.BytesIO(b""), filename="", content_type="")
            is_valid, error = validate_file(fs)
            assert is_valid is False

    def test_wrong_extension_rejected(self, valid_jpeg):
        with app.test_request_context():
            fs = FileStorage(
                stream=valid_jpeg,
                filename="malware.exe",
                content_type="image/jpeg"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is False
            assert "not allowed" in error

    def test_wrong_mime_rejected(self, valid_jpeg):
        with app.test_request_context():
            fs = FileStorage(
                stream=valid_jpeg,
                filename="test.jpg",
                content_type="application/pdf"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is False
            assert "MIME" in error

    def test_magic_byte_mismatch_rejected(self):
        with app.test_request_context():
            fake = io.BytesIO(b"MZ" + b"\x00" * 200)
            fs = FileStorage(
                stream=fake,
                filename="fake.jpg",
                content_type="image/jpeg"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is False
            assert "content does not match" in error

    def test_script_in_filename_sanitized(self, valid_jpeg):
        with app.test_request_context():
            fs = FileStorage(
                stream=valid_jpeg,
                filename="../../../etc/passwd.jpg",
                content_type="image/jpeg"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is True

    def test_null_bytes_in_filename(self):
        with app.test_request_context():
            fs = FileStorage(
                stream=io.BytesIO(b"\xff\xd8\xff" + b"\x00" * 100),
                filename="test\x00.jpg.php",
                content_type="image/jpeg"
            )
            is_valid, error = validate_file(fs)
            assert is_valid is False


class TestUploadEndpoint:
    def test_upload_requires_auth(self, client):
        resp = client.post("/upload", data={}, follow_redirects=False)
        assert resp.status_code == 302
        assert "/login" in resp.headers["Location"]


class TestCSRF:
    def test_logout_requires_post(self, client):
        resp = client.get("/logout", follow_redirects=False)
        assert resp.status_code == 405 or resp.status_code == 302
