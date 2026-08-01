# SecurePhotoshare — AWS Security Engineering Project

A security-hardened photo sharing application deployed on AWS, demonstrating defense-in-depth across infrastructure, application, and CI/CD layers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud (VPC)                             │
│                                                                     │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────────────────┐ │
│  │  WAFv2   │───▶│     ALB      │───▶│   Private Subnets (App)    │ │
│  │ 5 Rules  │    │  TLS 1.3     │    │                            │ │
│  └──────────┘    │  HTTPS Only  │    │  ┌──────┐    ┌──────┐     │ │
│                  └──────────────┘    │  │EC2+  │    │EC2+  │     │ │
│                                      │  │Docker│    │Docker│     │ │
│  ┌──────────────────────────┐        │  └──┬───┘    └──┬───┘     │ │
│  │   Public Subnets (ALB)   │        └─────┼──────────┼──────────┘ │
│  └──────────────────────────┘              │          │            │
│                                            ▼          ▼            │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Private Subnets (Data)                          │   │
│  │   ┌────────────┐     ┌────────────┐     ┌──────────────┐   │   │
│  │   │  RDS MySQL │     │  S3 Photos │     │S3 Quarantine │   │   │
│  │   │  Encrypted │     │ KMS + SSE  │     │  Rejected    │   │   │
│  │   └────────────┘     └────────────┘     └──────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────── Monitoring ────────────────────────────┐  │
│  │ CloudTrail │ GuardDuty │ Security Hub │ Inspector │ Config    │  │
│  │ WAF Logs   │ Flow Logs │ IAM Analyzer │ Alarms   │ SNS       │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Security Controls Implemented

### Application Layer
| Control | Implementation |
|---------|---------------|
| Authentication | Scrypt password hashing, session management |
| CSRF Protection | Flask-WTF token on all state-changing forms |
| Input Validation | Extension + MIME + magic bytes + Pillow verify |
| EXIF Stripping | Metadata removed before storage (privacy) |
| Security Headers | CSP, X-Frame-Options, HSTS, Referrer-Policy |
| Rate Limiting | Per-IP limits on auth (10/min) and uploads (10/min) |
| Quarantine | Invalid uploads isolated with rejection metadata |
| Audit Logging | Structured logs with request IDs for every action |
| SQL Injection | Parameterized queries via PyMySQL |
| XSS | Jinja2 auto-escaping + CSP |

### Infrastructure Layer
| Control | Implementation |
|---------|---------------|
| Encryption at Rest | KMS CMK with auto-rotation (S3, RDS, EBS) |
| Encryption in Transit | TLS 1.3 on ALB, bucket policy denies HTTP |
| Network Isolation | 3-tier VPC, SG-to-SG refs, no public DB |
| IAM Least Privilege | Prefix-scoped S3, KMS via-service condition |
| Secrets Management | Secrets Manager, no hardcoded credentials |
| WAF | Rate limiting, SQLi, IP reputation, common exploits |
| SSH-less Access | SSM Session Manager, no SSH keys |

### Detection & Monitoring
| Service | Purpose |
|---------|---------|
| CloudTrail | API audit trail + S3 data events |
| GuardDuty | Threat detection with S3 protection |
| Security Hub | Centralized findings, Foundational Best Practices |
| Inspector | CVE scanning on EC2 and containers |
| AWS Config | 8 compliance rules (encryption, public access, MFA) |
| IAM Access Analyzer | External access detection |
| VPC Flow Logs | Network traffic analysis |
| CloudWatch Alarms | CPU, 5xx, unhealthy targets, RDS metrics |

### CI/CD Security
| Stage | Tools |
|-------|-------|
| SAST | Bandit (Python security linter) |
| Dependency Scan | Safety (known vulnerabilities) |
| Container Scan | Trivy (CVE scan on Docker image) |
| IaC Scan | tfsec + Checkov (Terraform misconfigurations) |
| Supply Chain | Pinned dependencies, minimal base image |
| Deployment | OIDC auth (no long-lived keys), SSM deploy |

## Project Structure

```
├── app/                    # Application code
│   ├── app.py              # Flask application with security controls
│   ├── config.py           # Configuration (env-based, no secrets)
│   ├── Dockerfile          # Multi-stage, non-root, health-checked
│   ├── docker-compose.yml  # Local development stack
│   ├── nginx.conf          # Reverse proxy config
│   ├── schema.sql          # Database schema
│   ├── requirements.txt    # Pinned dependencies
│   └── templates/          # Jinja2 templates (auto-escaped)
├── terraform/              # Infrastructure as Code
│   ├── modules/
│   │   ├── network/        # VPC, subnets, endpoints, SGs
│   │   ├── storage/        # S3, RDS, KMS
│   │   ├── security/       # IAM roles and policies
│   │   ├── compute/        # ALB, ASG, Launch Template
│   │   └── monitoring/     # All detection services
│   └── *.tf                # Root module config
├── bootstrap/              # Terraform state bucket setup
├── tests/                  # pytest test suite
├── .github/workflows/      # CI/CD pipelines
│   ├── ci.yml              # Test + security scan on every PR
│   └── deploy.yml          # Build → ECR → deploy on merge
├── docs/
│   └── THREAT_MODEL.md     # STRIDE-based threat analysis
└── README.md
```

## Quick Start (Local Development)

```bash
# Build and run locally
cd app/
docker compose up --build

# Run tests
pip install -r app/requirements.txt pytest
pytest tests/ -v

# Run security scans locally
pip install bandit safety
bandit -r app/ --severity-level medium
safety check -r app/requirements.txt
```

## Deployment

The CI/CD pipeline handles deployment automatically on merge to `main`:

1. **CI Pipeline** (every push/PR): lint → test → bandit → safety → docker build → trivy → tfsec → checkov
2. **CD Pipeline** (merge to main): build image → push to ECR → rolling deploy via SSM → health check

### Prerequisites
- AWS account with OIDC identity provider for GitHub Actions
- ECR repository created
- Terraform state bucket (use `bootstrap/`)
- Secrets configured in GitHub Actions

### Manual Terraform Deployment
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars  # Fill in values
terraform init
terraform plan
terraform apply
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Flask over Django | Minimal attack surface, explicit security controls |
| Gunicorn over built-in server | Production-grade WSGI, proper signal handling |
| Scrypt over bcrypt | Modern KDF, memory-hard, built into Werkzeug |
| Quarantine bucket | Preserves evidence for incident response |
| EXIF stripping | Privacy by default — GPS/device data removed |
| VPC endpoints | AWS API calls never traverse public internet |
| Single KMS key | Simplified rotation and audit trail |
| SSM over SSH | No key management, full audit trail, IAM-based access |

## What This Project Demonstrates

- **Threat modeling** before implementation (see docs/THREAT_MODEL.md)
- **Defense in depth** — overlapping controls at every layer
- **Shift-left security** — scanning in CI before deployment
- **Least privilege** — minimal IAM, network isolation, non-root container
- **Secure SDLC** — from design to deployment to monitoring
- **Incident readiness** — audit trails, quarantine, alerting

---

Built as a security engineering portfolio project demonstrating end-to-end secure system design on AWS.
