# Infrastructure Exercises

Three self-contained infrastructure exercises using Terraform and Kubernetes.

---

## Exercise 1 — Terraform VPC Module (`exercise1-vpc-module/`)

A reusable Terraform module that provisions:

- A **VPC** with DNS support and hostnames enabled
- **4 subnets** across 2 AZs — 2 public (internet-facing) + 2 private
- An **Internet Gateway** + route tables
- An **S3 Gateway VPC Endpoint** — all S3 API calls from within the VPC stay on the AWS backbone network (free, no data-transfer cost)

### Structure

```
exercise1-vpc-module/
├── modules/vpc/          # Reusable module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── example/              # Example root module that calls the vpc module
    ├── main.tf
    ├── variables.tf
    └── providers.tf
```

### Run terraform plan (example)

```bash
cd exercise1-vpc-module/example
terraform init
terraform plan
```

> No real AWS credentials needed to validate syntax (`terraform validate`).  
> A `terraform plan` requires valid AWS credentials but will not deploy anything.

---

## Exercise 2 — S3 Backup Bucket (`exercise2-s3-backup/`)

An S3 bucket configured for a **180-day backup retention policy** with best practices for security and cost.

| Concern | Implementation |
|---------|---------------|
| **Encryption** | Customer-managed KMS key with automatic annual rotation |
| **Access control** | All public access blocked; bucket policy enforces KMS encryption and TLS |
| **Cross-account upload** | Bucket policy grants `arn:aws:iam::123456789012:role/backup_uploader` write access |
| **Retention (cost optimised)** | STANDARD → STANDARD_IA (day 30) → GLACIER (day 90) → Expire (day 180) |
| **Versioning** | Enabled; non-current versions purged after 7 days |
| **Audit** | S3 server access logging to a dedicated log bucket |

```bash
cd exercise2-s3-backup
terraform init
terraform plan
```

---

## Exercise 3 — hello-world on minikube (`exercise3-k8s/`)

A pre-built Go REST service deployed on a local minikube cluster, accessible at `http://localhost:8080/hello-world`.

```bash
cd exercise3-k8s
chmod +x deploy.sh
./deploy.sh
```

See [exercise3-k8s/README.md](exercise3-k8s/README.md) for full documentation.

---

## Repository layout

```
infra-exercises/
├── README.md                  ← You are here
├── .gitignore
├── exercise1-vpc-module/
├── exercise2-s3-backup/
└── exercise3-k8s/
```
