import os
import json
import boto3
from botocore.exceptions import ClientError


def get_secret(secret_id):
    """Retrieve secret from AWS Secrets Manager."""
    client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
    try:
        response = client.get_secret_value(SecretId=secret_id)
        return json.loads(response["SecretString"])
    except ClientError:
        return None


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", os.urandom(32).hex())
    WTF_CSRF_ENABLED = True
    MAX_CONTENT_LENGTH = 5 * 1024 * 1024  # 5 MB

    S3_BUCKET = os.getenv("S3_BUCKET", "")
    S3_QUARANTINE_BUCKET = os.getenv("S3_QUARANTINE_BUCKET", "")
    KMS_KEY_ID = os.getenv("KMS_KEY_ID", "")
    AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

    DB_SECRET_ID = os.getenv("DB_SECRET_ID", "")

    # Validate required environment variables in production to fail fast
    if os.getenv("FLASK_ENV") == "production":
        _required_vars = ["S3_BUCKET", "S3_QUARANTINE_BUCKET", "KMS_KEY_ID", "DB_SECRET_ID"]
        _missing = [var for var in _required_vars if not os.getenv(var)]
        if _missing:
            raise RuntimeError(f"Missing required production environment variables: {', '.join(_missing)}")

    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    # The current ALB deployment uses HTTP. Set this to true only when the
    # public endpoint is HTTPS, otherwise browsers will not send the session
    # cookie and Flask-WTF will report a missing CSRF session token.
    SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "false").lower() == "true"
    PERMANENT_SESSION_LIFETIME = 1800  # 30 minutes

    ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "gif", "webp"}
    ALLOWED_MIME_TYPES = {
        "image/jpeg", "image/png", "image/gif", "image/webp"
    }

    UPLOAD_RATE_LIMIT = "10 per minute"
