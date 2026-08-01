# Threat Model — SecurePhotoshare

## Overview

This document identifies threats to the SecurePhotoshare application using the STRIDE framework, maps each threat to implemented mitigations, and notes residual risks.

**System Scope:** Web application allowing authenticated users to upload and store photos on AWS infrastructure.

**Trust Boundaries:**
1. Internet → ALB (untrusted → semi-trusted)
2. ALB → Application (semi-trusted → trusted)
3. Application → Database (trusted → trusted)
4. Application → S3 (trusted → trusted)
5. User browser → Application (untrusted → trusted)

---

## Data Flow Diagram

```
[User Browser] ──HTTPS──▶ [WAF] ──▶ [ALB] ──▶ [EC2/Docker App]
                                                     │
                                          ┌──────────┼──────────┐
                                          ▼          ▼          ▼
                                      [RDS MySQL] [S3 Photos] [S3 Quarantine]
                                          ▲
                                          │
                                    [Secrets Manager]
```

---

## STRIDE Analysis

### Spoofing (Identity)

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| Credential brute force | Account takeover | Rate limiting (10/min on login), scrypt hashing | Mitigated |
| Session hijacking | Impersonation | HttpOnly + SameSite cookies, session timeout (30m), session regeneration on login | Mitigated |
| Credential stuffing | Mass compromise | Rate limiting, generic error messages (no user enumeration) | Partially mitigated |

**Residual risk:** No MFA implemented. For a production system, TOTP or WebAuthn would further reduce session hijacking risk.

---

### Tampering (Data Integrity)

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| Image file manipulation (polyglot) | Code execution via uploaded file | Magic byte validation, Pillow verify, EXIF strip (re-encodes image) | Mitigated |
| SQL injection | Data modification | Parameterized queries (PyMySQL %s placeholders) | Mitigated |
| S3 object tampering | Data corruption | Bucket versioning, KMS encryption, bucket policy denies unencrypted uploads | Mitigated |
| CSRF attacks | Unauthorized actions | Flask-WTF CSRF tokens on all state-changing forms | Mitigated |
| Terraform state tampering | Infrastructure compromise | S3 state bucket with versioning, DynamoDB locking | Mitigated |

---

### Repudiation (Audit Trail)

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| User denies upload | Dispute resolution | SHA-256 hash stored per upload, structured audit logs with request IDs | Mitigated |
| Admin denies access | Compliance failure | CloudTrail (multi-region, S3 data events, log file validation) | Mitigated |
| Log tampering | Evidence destruction | CloudTrail log file validation, S3 versioning on log bucket | Mitigated |

---

### Information Disclosure (Confidentiality)

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| Photos exposed publicly | Privacy breach | S3 public access block, no pre-signed URLs to untrusted parties, bucket policy | Mitigated |
| EXIF metadata leaks GPS/device info | Privacy violation | EXIF stripped before storage | Mitigated |
| Database credentials leaked | Full compromise | Secrets Manager (no hardcoded creds), KMS encryption | Mitigated |
| Error messages reveal internals | Reconnaissance | Generic error messages to user, detailed logs server-side only | Mitigated |
| Network sniffing | Credential theft | TLS 1.3 enforced, HSTS header, HTTP→HTTPS redirect | Mitigated |
| S3 data in transit | Data exposure | Bucket policy denies `aws:SecureTransport = false` | Mitigated |

**Residual risk:** No encryption of photos at the application layer (relies on S3 SSE-KMS). A compromised IAM role with KMS decrypt permission could access photos.

---

### Denial of Service (Availability)

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| Volumetric DDoS | Service unavailable | WAF rate limiting (1000 req/5min), ALB scaling | Partially mitigated |
| Large file upload exhaustion | Resource starvation | 5 MB limit (Nginx + app), rate limiting (10 uploads/min) | Mitigated |
| Application-layer DoS | Degraded performance | Gunicorn worker timeout (30s), ASG auto-scaling | Mitigated |
| Database connection exhaustion | Service failure | Connection timeout (5s), read timeout (10s) | Partially mitigated |

**Residual risk:** No CloudFront (would add Shield Standard for DDoS). Single NAT gateway is a single point of failure. No connection pooling on DB.

---

### Elevation of Privilege

| Threat | Impact | Mitigation | Status |
|--------|--------|------------|--------|
| Container escape | Host compromise | Non-root container user, minimal base image (python:slim) | Partially mitigated |
| IAM role over-privilege | Lateral movement | Prefix-scoped S3 access, KMS via-service condition, no wildcard actions | Mitigated |
| RDS access from app tier | Data exfiltration | SG restricts DB access to app SG only, private subnet with no internet route | Mitigated |
| SSM command injection | Instance compromise | No SSH keys, SSM audit trail via CloudTrail, IAM-gated access | Mitigated |

**Residual risk:** EC2 instance has outbound internet access (via NAT) for pulling Docker images. A compromised container could exfiltrate data outbound. Mitigation: VPC endpoints reduce need for NAT; future work would add egress filtering.

---

## Attack Scenarios Considered

### 1. Malicious File Upload
**Attack:** Attacker uploads a PHP webshell disguised as a JPEG.
**Defense chain:** Extension check → MIME check → Magic byte check → Pillow verify → EXIF strip (re-encodes as clean image) → Files stored in S3 (never served directly by the application server).

### 2. Credential Stuffing
**Attack:** Automated login attempts with breached credential lists.
**Defense chain:** Rate limiting (10/min per IP) → Generic error messages (no user enumeration) → Scrypt hashing (expensive to verify) → Structured logging of failed attempts → GuardDuty anomaly detection.

### 3. Insider Threat (AWS Console Access)
**Attack:** Malicious admin accesses photos directly via AWS console.
**Defense chain:** CloudTrail S3 data events → IAM Access Analyzer → Security Hub findings → SNS alerts on suspicious access patterns.

### 4. Supply Chain Attack (Dependency Poisoning)
**Attack:** Malicious package introduced via dependency update.
**Defense chain:** Pinned versions in requirements.txt → Safety scan in CI → Trivy container scan → Minimal base image reduces attack surface.

---

## Accepted Risks

| Risk | Reason | Future Mitigation |
|------|--------|-------------------|
| No MFA | Complexity vs. demo scope | Add TOTP via pyotp |
| No CloudFront | Cost, demo simplicity | Add CF + Shield Standard |
| Single NAT gateway | Cost | Deploy NAT per AZ |
| No connection pooling | Complexity | Add SQLAlchemy with pool |
| No antivirus scan | Cost (Lambda + ClamAV) | Add S3 trigger → scan pipeline |
| Outbound egress unrestricted | Docker pull requirement | Add egress proxy or VPC endpoint for ECR |

---

## Compliance Mapping

| Requirement | Control |
|-------------|---------|
| NIST 800-53 AC-2 | User registration, session management |
| NIST 800-53 AU-2 | CloudTrail, structured application logs |
| NIST 800-53 SC-8 | TLS 1.3, HSTS |
| NIST 800-53 SC-28 | KMS encryption at rest |
| NIST 800-53 SI-3 | File validation, quarantine |
| AWS Well-Architected Security Pillar | IAM, detective controls, encryption, network |
