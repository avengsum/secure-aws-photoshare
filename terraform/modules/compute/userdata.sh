#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y docker nginx
systemctl enable docker
systemctl start docker

# SSM is the controlled deployment channel. Fail bootstrap if the agent is
# missing instead of creating an instance that cannot be managed securely.
if ! systemctl cat amazon-ssm-agent.service >/dev/null 2>&1; then
  echo "amazon-ssm-agent.service is missing from the AMI" >&2
  exit 1
fi
systemctl enable --now amazon-ssm-agent.service

useradd --system --shell /usr/sbin/nologin photoshare

mkdir -p /opt/photoshare
rm -f /opt/photoshare/bootstrap-ready

# All Auto Scaling instances retrieve the same session-signing secret.
FLASK_SECRET_KEY=""
for attempt in $(seq 1 30); do
  FLASK_SECRET_KEY=$(aws secretsmanager get-secret-value \
    --region ${aws_region} \
    --secret-id ${flask_session_secret_arn} \
    --query SecretString \
    --output text 2>/dev/null || true)
  if [ -n "$FLASK_SECRET_KEY" ] && [ "$FLASK_SECRET_KEY" != "None" ]; then
    break
  fi
  sleep 10
done

if [ -z "$FLASK_SECRET_KEY" ] || [ "$FLASK_SECRET_KEY" = "None" ]; then
  echo "Unable to retrieve the Flask session secret after 5 minutes" >&2
  exit 1
fi

cat > /opt/photoshare/.env <<ENVFILE
FLASK_ENV=production
SESSION_COOKIE_SECURE=false
SECRET_KEY=$FLASK_SECRET_KEY
S3_BUCKET=${photo_bucket_name}
S3_QUARANTINE_BUCKET=${quarantine_bucket_name}
KMS_KEY_ID=${kms_key_arn}
AWS_REGION=${aws_region}
DB_SECRET_ID=${secret_arn}
ENVFILE

chmod 600 /opt/photoshare/.env

# Configure Nginx as reverse proxy
cat > /etc/nginx/conf.d/photoshare.conf <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 5m;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
        proxy_connect_timeout 5s;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf
systemctl enable nginx
systemctl restart nginx

# The CD workflow deploys a specific immutable ECR image after bootstrap.
# This marker prevents CD from racing user-data initialization.
touch /opt/photoshare/bootstrap-ready
chmod 600 /opt/photoshare/bootstrap-ready
