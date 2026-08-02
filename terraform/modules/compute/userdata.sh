#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y docker nginx
systemctl enable docker
systemctl start docker

useradd --system --shell /usr/sbin/nologin photoshare

mkdir -p /opt/photoshare

# All Auto Scaling instances retrieve the same session-signing secret.
FLASK_SECRET_KEY=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${flask_session_secret_arn} \
  --query SecretString \
  --output text)

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

# Login to ECR and pull application image
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker pull ${ecr_registry}/${ecr_repository}:latest

# Run application container
docker run -d \
  --name photoshare \
  --restart unless-stopped \
  -p 8000:8000 \
  --env-file /opt/photoshare/.env \
  --read-only \
  --tmpfs /tmp \
  --memory=512m \
  --cpus=1 \
  ${ecr_registry}/${ecr_repository}:latest

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
