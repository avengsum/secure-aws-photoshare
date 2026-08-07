# Secure PhotoShare Threat Model

## 1. System Overview

Secure PhotoShare is a Flask application that allows authenticated users to upload and view their own images.

The application runs as a non-root Docker container on EC2 instances in private subnets. Internet traffic passes through AWS WAF and an Application Load Balancer, then through Nginx to Gunicorn and Flask.

The application uses:

- RDS MySQL for users and upload metadata
- Private S3 buckets for accepted and rejected files
- KMS for encryption
- Secrets Manager for database and Flask session secrets
- GitHub Actions, ECR, OIDC, and SSM for deployment
- Terraform for AWS infrastructure

## 2. Components

| Component | Responsibility |
|---|---|
| User browser | Sends credentials, forms, and image uploads |
| WAF and ALB | Public entry point, filtering, routing, and health checks |
| Nginx and Docker application | Serves the Flask application on EC2 |
| RDS MySQL | Stores users and upload ownership metadata |
| S3 and KMS | Stores and encrypts photos and quarantined files |
| Secrets Manager | Stores database and session secrets |
| GitHub Actions and ECR | Builds, scans, stores, and releases images |
| Terraform | Creates and manages AWS infrastructure |

## 3. Data Flow and Trust Boundaries

```text
Browser → WAF → ALB → Nginx → Flask container → RDS MySQL
                                      ├──→ S3 photo bucket
                                      ├──→ S3 quarantine bucket
                                      └──→ Secrets Manager / KMS

Developer → GitHub → GitHub Actions → OIDC role → ECR and SSM → EC2
```

**TB-01: Browser → Application**

Requests, credentials, form values, and uploaded files are untrusted.

**TB-02: Application → AWS data services**

The application uses an EC2 IAM role to access only required S3 prefixes, secrets, KMS, and ECR resources.

**TB-03: Application → RDS**

Database access is private and restricted by security groups. User input must never become executable SQL.

**TB-04: GitHub Actions → AWS**

GitHub receives temporary AWS credentials through OIDC. The role trust policy restricts access to the repository, branch, and deployment environment.

## 4. STRIDE Threat Analysis

### S — Spoofing

**TH-01: Attacker uses stolen or guessed credentials**

An attacker may attempt credential stuffing or brute-force login to access another user's photos.

**Affected components:** Registration, login, and session handling

**Boundary:** TB-01

**Impact:** Account takeover and unauthorized photo access

**Controls:**

- Passwords are stored using Werkzeug `scrypt` hashing.
- Login is limited to 10 requests per minute per IP.
- Registration is limited to 5 requests per hour per IP.
- Invalid credentials use a generic error message.
- Sessions are HttpOnly, SameSite=Lax, regenerated after login, and expire after 30 minutes.

**Residual risk:** MFA and breached-password detection are not implemented.

### T — Tampering

**TH-02: Malicious or malformed file is uploaded**

An attacker may upload a disguised file, corrupted image, or file containing unwanted metadata.

**Affected components:** Upload endpoint and S3

**Boundary:** TB-01 and TB-02

**Impact:** Privacy exposure, unsafe processing, or storage abuse

**Controls:**

- Maximum upload size is 5 MB.
- Filename, extension, MIME type, and magic bytes are checked.
- Pillow verifies the image before storage.
- Images are re-encoded to remove EXIF metadata.
- Invalid files are written to a separate encrypted quarantine bucket.
- S3 requires encrypted transport and KMS encryption.

**Residual risk:** Quarantine is not antivirus or malware scanning. A production system should add a malware-scanning pipeline.

**TH-03: User input changes database behavior**

An attacker may attempt SQL injection to modify users or upload ownership records.

**Controls:** PyMySQL queries use parameterized values, RDS is private, and the database security group allows access only from the EC2 application security group.

### R — Repudiation

**TH-04: User or developer denies an action**

A user may deny uploading a file, or a developer may deny making a deployment or security-sensitive change.

**Affected components:** Application, AWS services, and GitHub repository

**Impact:** Difficult incident investigation and weak accountability

**Controls:**

- Application logs include request IDs, login events, upload events, rejection reasons, and file hashes.
- ALB and WAF access logs are enabled.
- CloudTrail records AWS API activity and S3 data events.
- VPC Flow Logs and CloudWatch logs support investigation.
- Git history, pull requests, reviews, and workflow history provide development audit evidence.

**Required operational control:** Protect the `main` branch and require reviews for workflow, Terraform, IAM, and application changes.

### I — Information Disclosure

**TH-05: Private photos or secrets are exposed**

An attacker may access an S3 object, database credential, Flask secret, or session cookie.

**Affected components:** S3, RDS, Secrets Manager, KMS, and browser sessions

**Boundary:** TB-01 and TB-02

**Impact:** Privacy breach, account takeover, or AWS data access

**Controls:**

- S3 public access is blocked.
- Photos and RDS are encrypted with KMS.
- Secrets are not stored in source code or Docker images.
- The EC2 IAM role is scoped to required resources and prefixes.
- Dashboard queries restrict results to the authenticated user's ID.
- Images are served through one-hour presigned URLs rather than public objects.
- The container runs as a non-root user.

**Residual risks:** A leaked presigned URL works until expiry. The current HTTP-only fallback does not provide transport confidentiality and is not suitable for public production use.

### D — Denial of Service

**TH-06: Excess traffic or expensive requests exhaust the application**

An attacker may send repeated login, upload, or web requests to consume application, database, or network capacity.

**Affected components:** WAF, ALB, EC2, RDS, and S3

**Impact:** Slow service or application unavailability

**Controls:**

- AWS WAF managed rules and IP rate limiting are enabled.
- Flask applies global, authentication, registration, and upload limits.
- Uploads are limited to 5 MB.
- Gunicorn has worker and request time limits.
- ALB health checks and the Auto Scaling Group replace unhealthy instances.
- Deployment stops if targets do not become healthy.

**Residual risk:** The design has one NAT gateway and does not provide full volumetric DDoS protection or application-level database connection pooling.

### E — Elevation of Privilege

**TH-07: Compromised application gains broader AWS or host access**

An attacker who compromises the application may attempt to access the EC2 host, instance metadata, other S3 data, secrets, or deployment capabilities.

**Affected components:** Docker, EC2 IAM role, IMDS, SSM, and AWS services

**Impact:** Lateral movement, data theft, or infrastructure compromise

**Controls:**

- The container runs as non-root with a minimal Alpine image.
- IMDSv2 is required and metadata tags are disabled.
- EC2 instances are private and SSH is not exposed.
- SSM provides audited, IAM-controlled administration.
- The EC2 role uses scoped S3, Secrets Manager, KMS, and ECR permissions.
- RDS accepts traffic only from the application security group.
- GitHub deploys through OIDC temporary credentials, not long-lived AWS keys.

**Residual risk:** A fully compromised application can use the permissions of the EC2 role. Outbound EC2 access through NAT should be restricted further for higher-sensitivity workloads.

## 5. Risk Priorities

| Priority | Threat | Action |
|---|---|---|
| High | TH-05 information disclosure | Enable HTTPS with ACM and set `SESSION_COOKIE_SECURE=true`. |
| High | TH-04 CI/CD repudiation and tampering | Enforce protected `main`, required CI checks, and pull-request review. |
| High | TH-02 malicious upload | Add malware scanning before accepting files. |
| Medium | TH-07 privilege escalation | Review IAM permissions and restrict outbound traffic. |
| Medium | TH-06 availability | Consider NAT per AZ, connection pooling, and stronger edge protection. |

This model describes the current Secure PhotoShare implementation and should be reviewed when authentication, upload processing, IAM permissions, or deployment workflows change.
