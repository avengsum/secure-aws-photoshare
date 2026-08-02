import os
import re
import uuid
import logging
import hashlib
from datetime import datetime
from functools import wraps
from io import BytesIO

import boto3
import pymysql
from PIL import Image
from flask import (
    Flask, render_template, request, redirect, url_for,
    flash, session, abort, jsonify, has_request_context
)
from flask_wtf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename

from config import Config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(request_id)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)


class RequestIdFilter(logging.Filter):
    def filter(self, record):
        if has_request_context():
            record.request_id = getattr(request, "request_id", "-")
        else:
            record.request_id = "-"
        return True


# Apply the request-id default to every handler, including boto3 and Gunicorn
# records that do not originate from the application logger.
for handler in logging.getLogger().handlers:
    handler.addFilter(RequestIdFilter())


logger = logging.getLogger(__name__)
logger.addFilter(RequestIdFilter())

app = Flask(__name__)
app.config.from_object(Config)

csrf = CSRFProtect(app)
limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=["200 per hour"],
    storage_uri="memory://",
)


MAGIC_BYTES = {
    "image/jpeg": [b"\xff\xd8\xff"],
    "image/png": [b"\x89PNG\r\n\x1a\n"],
    "image/gif": [b"GIF87a", b"GIF89a"],
    "image/webp": [b"RIFF"],
}

FILENAME_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.\-]{0,119}$")


@app.before_request
def assign_request_id():
    request.request_id = uuid.uuid4().hex[:12]


@app.after_request
def set_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "0"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "script-src 'self'; "
        "img-src 'self' data: https:; "
        "frame-ancestors 'none';"
    )
    if app.config["SESSION_COOKIE_SECURE"]:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


def get_db_connection():
    """Get database connection using Secrets Manager credentials."""
    secret_id = app.config["DB_SECRET_ID"]
    if not secret_id:
        return None

    from config import get_secret
    creds = get_secret(secret_id)
    if not creds:
        return None

    return pymysql.connect(
        host=creds["host"],
        user=creds["username"],
        password=creds["password"],
        database=creds.get("dbname", "photoshare"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
        read_timeout=10,
    )


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            flash("Please log in to continue.", "warning")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


def validate_file(file_storage):
    """Validate uploaded file. Returns (is_valid, error_message)."""
    if not file_storage or file_storage.filename == "":
        return False, "No file selected"

    filename = secure_filename(file_storage.filename)
    if not filename:
        return False, "Invalid filename"

    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext not in app.config["ALLOWED_EXTENSIONS"]:
        return False, f"File type .{ext} not allowed"

    header = file_storage.read(12)
    file_storage.seek(0)

    mime_type = file_storage.content_type
    if mime_type not in app.config["ALLOWED_MIME_TYPES"]:
        return False, "MIME type not allowed"

    valid_magic = False
    for allowed_mime, signatures in MAGIC_BYTES.items():
        if mime_type == allowed_mime:
            for sig in signatures:
                if header.startswith(sig):
                    valid_magic = True
                    break
    if not valid_magic:
        return False, "File content does not match declared type"

    try:
        img = Image.open(file_storage)
        img.verify()
        file_storage.seek(0)
    except Exception:
        return False, "File is not a valid image"

    return True, None


def strip_exif(file_storage):
    """Remove EXIF metadata from image for privacy."""
    img = Image.open(file_storage)
    data = list(img.getdata())
    clean_img = Image.new(img.mode, img.size)
    clean_img.putdata(data)

    buf = BytesIO()
    fmt = img.format or "JPEG"
    clean_img.save(buf, format=fmt)
    buf.seek(0)
    return buf, fmt


def upload_to_s3(file_data, filename, content_type):
    """Upload file to S3 with server-side encryption."""
    s3 = boto3.client("s3", region_name=app.config["AWS_REGION"])
    key = f"uploads/{datetime.utcnow().strftime('%Y/%m/%d')}/{uuid.uuid4().hex}_{filename}"

    s3.put_object(
        Bucket=app.config["S3_BUCKET"],
        Key=key,
        Body=file_data,
        ContentType=content_type,
        ServerSideEncryption="aws:kms",
        SSEKMSKeyId=app.config["KMS_KEY_ID"],
        Metadata={"original-filename": filename},
    )
    return key


def quarantine_file(file_data, filename, reason):
    """Move rejected file to quarantine bucket with metadata."""
    s3 = boto3.client("s3", region_name=app.config["AWS_REGION"])
    key = f"rejected/{datetime.utcnow().strftime('%Y/%m/%d')}/{uuid.uuid4().hex}_{filename}"

    s3.put_object(
        Bucket=app.config["S3_QUARANTINE_BUCKET"],
        Key=key,
        Body=file_data,
        ServerSideEncryption="aws:kms",
        SSEKMSKeyId=app.config["KMS_KEY_ID"],
        Metadata={
            "original-filename": filename,
            "rejection-reason": reason,
            "rejected-at": datetime.utcnow().isoformat(),
        },
    )
    logger.warning("File quarantined: %s reason=%s", filename, reason)


def record_upload(user_id, s3_key, filename, file_hash):
    """Record upload metadata in database."""
    conn = get_db_connection()
    if not conn:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO uploads (user_id, s3_key, original_filename, sha256_hash, uploaded_at) "
                "VALUES (%s, %s, %s, %s, %s)",
                (user_id, s3_key, filename, file_hash, datetime.utcnow()),
            )
        conn.commit()
    except pymysql.Error as e:
        logger.error("Database write failed: %s", e)
    finally:
        conn.close()


@app.route("/")
def index():
    if "user_id" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/register", methods=["GET", "POST"])
@limiter.limit("5 per hour")
def register():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if not username or len(username) < 3 or len(username) > 30:
            flash("Username must be 3-30 characters.", "error")
            return render_template("register.html")

        if not re.match(r"^[a-zA-Z0-9_]+$", username):
            flash("Username: letters, numbers, underscores only.", "error")
            return render_template("register.html")

        if len(password) < 8:
            flash("Password must be at least 8 characters.", "error")
            return render_template("register.html")

        conn = get_db_connection()
        if not conn:
            flash("Service unavailable.", "error")
            return render_template("register.html")

        try:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE username = %s", (username,))
                if cur.fetchone():
                    flash("Username already taken.", "error")
                    return render_template("register.html")

                pw_hash = generate_password_hash(password, method="scrypt")
                cur.execute(
                    "INSERT INTO users (username, password_hash, created_at) VALUES (%s, %s, %s)",
                    (username, pw_hash, datetime.utcnow()),
                )
            conn.commit()
            flash("Account created. Please log in.", "success")
            return redirect(url_for("login"))
        except pymysql.Error as e:
            logger.error("Registration failed: %s", e)
            flash("Registration failed.", "error")
        finally:
            conn.close()

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
@limiter.limit("10 per minute")
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        conn = get_db_connection()
        if not conn:
            flash("Service unavailable.", "error")
            return render_template("login.html")

        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT id, password_hash FROM users WHERE username = %s", (username,)
                )
                user = cur.fetchone()

            if user and check_password_hash(user["password_hash"], password):
                session.clear()
                session.permanent = True
                session["user_id"] = user["id"]
                session["username"] = username
                logger.info("Login success: user=%s", username)
                return redirect(url_for("dashboard"))

            logger.warning("Login failed: user=%s ip=%s", username, request.remote_addr)
            flash("Invalid credentials.", "error")
        except pymysql.Error as e:
            logger.error("Login query failed: %s", e)
            flash("Service unavailable.", "error")
        finally:
            conn.close()

    return render_template("login.html")


@app.route("/logout", methods=["POST"])
@login_required
def logout():
    session.clear()
    flash("Logged out.", "success")
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_required
def dashboard():
    uploads = []
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT s3_key, original_filename, uploaded_at FROM uploads "
                    "WHERE user_id = %s ORDER BY uploaded_at DESC LIMIT 20",
                    (session["user_id"],),
                )
                uploads = cur.fetchall()
        except pymysql.Error as e:
            logger.error("Database error in dashboard: %s", e)
        finally:
            conn.close()

    if uploads:
        s3 = boto3.client("s3", region_name=app.config["AWS_REGION"])

        for upload in uploads:
            try:
                upload["presigned_url"] = s3.generate_presigned_url("get_object", Params={
                    "Bucket": app.config["S3_BUCKET"],
                    "Key": upload["s3_key"]
                },
                ExpiresIn=3600  )

            except Exception as e:
                logger.error("Failed to generate presigned URL for %s: %s", upload["s3_key"],e)
                upload["presigned_url"] = None

    return render_template("dashboard.html", uploads=uploads)
                             
            


@app.route("/upload", methods=["POST"])
@login_required
@limiter.limit(Config.UPLOAD_RATE_LIMIT)
def upload():
    file = request.files.get("photo")

    is_valid, error = validate_file(file)
    if not is_valid:
        file_data = file.read() if file else b""
        filename = secure_filename(file.filename) if file else "unknown"
        if file_data:
            quarantine_file(file_data, filename, error)
        flash(f"Upload rejected: {error}", "error")
        logger.warning(
            "Upload rejected: user=%s file=%s reason=%s",
            session.get("username"), filename, error,
        )
        return redirect(url_for("dashboard"))

    filename = secure_filename(file.filename)
    clean_data, fmt = strip_exif(file)
    file_bytes = clean_data.read()
    file_hash = hashlib.sha256(file_bytes).hexdigest()
    clean_data.seek(0)

    try:
        s3_key = upload_to_s3(clean_data, filename, file.content_type)
        record_upload(session["user_id"], s3_key, filename, file_hash)
        logger.info(
            "Upload success: user=%s file=%s hash=%s",
            session.get("username"), filename, file_hash[:16],
        )
        flash("Photo uploaded successfully.", "success")
    except Exception as e:
        logger.error("Upload failed: %s", e)
        flash("Upload failed. Please try again.", "error")

    return redirect(url_for("dashboard"))


@app.route("/health")
@csrf.exempt
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
