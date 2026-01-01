PostgreSQL + Terraform + Infisical Migration Outline

  High-level roadmap for migrating to declarative database management with centralized secrets.

  ---
  Current State (What We Just Built)

  Ansible
    ↓
  PostgreSQL Container (tower-pc)
    ↓
  Manual database/user creation
    ↓
  K8s Secrets (manually created)
    ↓
  Applications

  Limitations:
  - Databases hard-coded in host_vars/tower-pc.yml
  - Secrets managed manually or via Ansible vault
  - No self-service for new projects
  - Credential rotation requires Ansible re-run + k8s secret updates

  ---
  Target State

  ┌──────────────┐
  │ Ansible      │ → Deploys PostgreSQL infrastructure (one-time)
  └──────────────┘

  ┌──────────────┐
  │ Terraform    │ → Manages databases/users (declarative, per-project)
  └──────┬───────┘
         ↓
  ┌──────────────────────────────────────┐
  │ PostgreSQL (tower-pc)                │
  │ - coaching DB                        │
  │ - resume DB                          │
  │ - blog DB                            │
  └──────────────────────────────────────┘
         ↓
  ┌──────────────┐
  │ Infisical    │ → Central secret store
  └──────┬───────┘
         ↓
  ┌──────────────────────────────────────┐
  │ Kubernetes (Infisical Operator)      │
  │ - Auto-syncs secrets to namespaces   │
  └──────┬───────────────────────────────┘
         ↓
  ┌──────────────┐
  │ Applications │ → Consume secrets automatically
  └──────────────┘

  Benefits:
  - ✅ Infrastructure-as-code for databases
  - ✅ Centralized secret management
  - ✅ Self-service database provisioning
  - ✅ Easy credential rotation
  - ✅ Environment parity (dev/staging/prod)

  ---
  Components Overview

  1. Infrastructure Layer (Already Done ✅)

  What: PostgreSQL container on tower-pc
  Managed by: Ansible
  Files:
  - ansible/roles/postgresql-server/
  - ansible/playbooks/setup-postgresql.yml
  - k8s-manifests/postgresql/service.yaml

  Status: Complete - no changes needed

  ---
  2. Database Provisioning Layer (New 📦)

  What: Logical databases, users, grants
  Managed by: Terraform
  Files to create:
  terraform/postgresql/
  ├── main.tf                          # Providers (postgresql, infisical)
  ├── variables.tf                     # Input variables
  ├── terraform.tfvars                 # Secrets (gitignored)
  ├── apps.tf                          # Database definitions
  ├── modules/
  │   └── app-database/
  │       ├── main.tf                  # Reusable module
  │       ├── variables.tf
  │       └── outputs.tf
  └── backend.tf                       # State storage (S3/local)

  Dependencies:
  - Terraform >= 1.6
  - PostgreSQL provider (cyrilgdn/postgresql)
  - Infisical provider (infisical/infisical)
  - PostgreSQL root credentials (from Ansible vault)

  ---
  3. Secret Management Layer (New 📦)

  What: Centralized secret storage and distribution
  Managed by: Infisical + Kubernetes operator
  Components:

  Infisical Setup:
  - Create project workspace
  - Generate universal auth credentials
  - Define secret paths (e.g., /blog, /coaching)

  Kubernetes:
  k8s-manifests/infisical/
  ├── namespace.yaml                   # infisical-system namespace
  ├── operator.yaml                    # Infisical operator deployment
  └── auth-secret.yaml.example         # Universal auth credentials template

  Dependencies:
  - Infisical account (self-hosted or cloud)
  - Infisical Kubernetes operator
  - Universal auth configured in Infisical

  ---
  4. Application Layer (Updated 🔄)

  What: Apps consume secrets from Infisical
  Changes needed:
  - Add InfisicalSecret resource per namespace
  - Update deployments to reference auto-synced secrets
  - Remove manual secret creation

  Example per app:
  k8s-manifests/blog/
  ├── infisical-secret-sync.yaml       # NEW: Syncs from Infisical
  ├── deployment.yaml                  # UPDATED: Reference synced secret
  └── service.yaml                     # UNCHANGED

  ---
  Migration Phases

  Phase 0: Prerequisites (Before Starting)

  Decisions to make:
  - Infisical hosting: Cloud vs self-hosted
  - Terraform state storage: S3, Terraform Cloud, or local
  - Secret rotation policy
  - Environment strategy (single DB for all envs vs separate)

  Setup required:
  - Infisical account/deployment
  - Terraform installed on workstation
  - Infisical CLI installed (infisical command)

  ---
  Phase 1: Infisical Foundation (1-2 hours)

  Goal: Get Infisical working with Kubernetes

  Steps:
  1. Deploy Infisical (if self-hosting) or sign up for cloud
  2. Create project workspace in Infisical
  3. Generate universal auth credentials
  4. Install Infisical operator in Kubernetes
  5. Test secret sync with dummy secret

  Deliverables:
  - Infisical operator running in infisical-system namespace
  - Test secret successfully synced to k8s

  Validation:
  # Create test secret in Infisical
  infisical secrets set TEST_SECRET=hello --path=/test

  # Sync to k8s
  kubectl apply -f test-secret-sync.yaml

  # Verify
  kubectl get secret test-secret -n test

  ---
  Phase 2: Terraform Setup (1-2 hours)

  Goal: Terraform can manage PostgreSQL and write to Infisical

  Steps:
  1. Create Terraform directory structure
  2. Configure providers (postgresql, infisical)
  3. Create reusable app-database module
  4. Test with one database (e.g., create test-db)

  Deliverables:
  - terraform/postgresql/ structure
  - Working module that creates DB + user + Infisical secret
  - Terraform state storage configured

  Validation:
  cd terraform/postgresql
  terraform init
  terraform plan
  terraform apply

  # Check database exists
  ssh tower-pc "docker exec postgresql psql -U postgres -l | grep test"

  # Check secret in Infisical
  infisical secrets get DATABASE_URL --path=/test

  ---
  Phase 3: Migrate First Application (2-3 hours)

  Goal: Prove end-to-end flow with one real app

  Steps:
  1. Choose simplest app (e.g., coaching)
  2. Define database in Terraform
  3. Apply Terraform (creates DB, writes to Infisical)
  4. Create InfisicalSecret resource in app namespace
  5. Update app deployment to use synced secret
  6. Test deployment

  Deliverables:
  - One app fully migrated to new pattern
  - Documentation of any issues/lessons learned

  Rollback plan:
  - Keep old manual secrets in place initially
  - Switch deployment back to old secret if issues

  ---
  Phase 4: Migrate Remaining Applications (Incremental)

  Goal: Migrate all apps one-by-one

  Steps:
  1. For each app:
    - Add Terraform module block
    - Apply Terraform
    - Create Infisical sync manifest
    - Update deployment
    - Test and verify
  2. Remove old manual secrets after validation

  Deliverables:
  - All apps using Terraform-managed databases
  - All secrets from Infisical

  ---
  Phase 5: Cleanup & Automation (1 hour)

  Goal: Remove legacy code, add automation

  Steps:
  1. Remove database/user definitions from host_vars/tower-pc.yml
  2. Update Ansible role to skip database/user creation
  3. Create scripts/new-project.sh automation
  4. Document new developer workflow

  Deliverables:
  - Clean separation: Ansible = infra, Terraform = databases
  - Self-service script for new projects
  - Updated README/documentation

  ---
  File Structure (Final)

  lab-iac/
  ├── ansible/
  │   ├── roles/
  │   │   └── postgresql-server/         # UNCHANGED: Infrastructure only
  │   └── playbooks/
  │       └── setup-postgresql.yml       # UPDATED: No database provisioning
  │
  ├── terraform/
  │   └── postgresql/                    # NEW: Database management
  │       ├── main.tf
  │       ├── variables.tf
  │       ├── apps.tf                    # All databases defined here
  │       ├── modules/app-database/
  │       └── terraform.tfvars           # Gitignored secrets
  │
  ├── k8s-manifests/
  │   ├── infisical/                     # NEW: Infisical operator
  │   │   ├── namespace.yaml
  │   │   └── operator.yaml
  │   ├── postgresql/                    # UNCHANGED
  │   │   └── service.yaml
  │   └── [each-app]/
  │       ├── infisical-secret-sync.yaml # NEW: Per-app secret sync
  │       └── deployment.yaml            # UPDATED: Reference synced secrets
  │
  ├── scripts/
  │   ├── install-postgresql.sh          # UNCHANGED: Ansible wrapper
  │   └── new-project.sh                 # NEW: Automate new app setup
  │
  └── docs/
      └── terraform-infisical-migration.md  # NEW: This document

  ---
  Decision Points

  Infisical Hosting

  Cloud (app.infisical.com):
  - ✅ Easier setup
  - ✅ Managed backups
  - ❌ External dependency
  - ❌ Monthly cost

  Self-hosted:
  - ✅ Full control
  - ✅ No recurring cost
  - ❌ Need to manage deployment
  - ❌ Need to manage backups

  Recommendation: Start with cloud, migrate to self-hosted later if needed

  ---
  Terraform State Storage

  Options:
  1. Local - Simple but not team-friendly
  2. S3 + DynamoDB - Industry standard, requires AWS
  3. Terraform Cloud - Managed, free tier available
  4. GitLab/GitHub - If using GitLab's Terraform state backend

  Recommendation: Terraform Cloud free tier or S3 if you have AWS

  ---
  Environment Strategy

  Option A: Separate PostgreSQL per environment
  - Dev PostgreSQL on one machine
  - Prod PostgreSQL on tower-pc
  - ✅ Complete isolation
  - ❌ More infrastructure

  Option B: Shared PostgreSQL, separate databases
  - All environments on tower-pc
  - blog-dev, blog-staging, blog-prod databases
  - ✅ Simpler infrastructure
  - ❌ No compute isolation

  Recommendation: Option B for homelab, Option A for production

  ---
  Risks & Mitigations

  Risk: Terraform state corruption

  Mitigation:
  - Use remote state with locking
  - Regular state backups
  - Never manually modify databases

  Risk: Infisical downtime breaks deployments

  Mitigation:
  - K8s secrets persist even if Infisical is down
  - Only new deployments affected
  - Keep Infisical operator highly available

  Risk: Learning curve for team

  Mitigation:
  - Comprehensive documentation
  - Automation scripts hide complexity
  - Gradual rollout (one app at a time)

  ---
  Effort Estimate

  | Phase                        | Time        | Complexity |
  |------------------------------|-------------|------------|
  | Phase 0: Prerequisites       | 30 min      | Low        |
  | Phase 1: Infisical setup     | 1-2 hours   | Medium     |
  | Phase 2: Terraform setup     | 1-2 hours   | Medium     |
  | Phase 3: First app migration | 2-3 hours   | High       |
  | Phase 4: Per additional app  | 30 min each | Low        |
  | Phase 5: Cleanup             | 1 hour      | Low        |

  Total for 3 apps: ~8-10 hours

  ---
  Quick Reference: Before vs After

  Adding a New Database

  Before (Current):
  # 1. Edit host_vars
  vim ansible/inventory/host_vars/tower-pc.yml
  # Add database definition

  # 2. Re-run Ansible
  ansible-playbook playbooks/setup-postgresql.yml --ask-vault-pass

  # 3. Manually create k8s secret
  kubectl create secret generic blog-db -n blog \
    --from-literal=DATABASE_URL=postgresql://...

  # 4. Deploy app
  kubectl apply -f blog/

  After (Target):
  # 1. Add to Terraform
  echo 'module "blog_db" { ... }' >> terraform/postgresql/apps.tf

  # 2. Apply
  terraform apply

  # 3. Deploy app (secret auto-synced)
  kubectl apply -f blog/

  ---
  Next Steps (When Ready)

  1. Review this outline - Make sure approach fits your needs
  2. Choose Infisical hosting - Cloud or self-hosted
  3. Set up Infisical test environment - Learn the tool
  4. Prototype with Terraform - Test PostgreSQL provider locally
  5. Schedule migration window - Pick a low-traffic time
  6. Execute Phase 1 - Get Infisical + K8s working
  7. Iterate through remaining phases

  ---
  Additional Resources

  Terraform Providers:
  - PostgreSQL: https://registry.terraform.io/providers/cyrilgdn/postgresql
  - Infisical: https://registry.terraform.io/providers/infisical/infisical

  Infisical:
  - Kubernetes operator: https://infisical.com/docs/integrations/platforms/kubernetes
  - Self-hosting: https://infisical.com/docs/self-hosting/overview

  Alternatives to consider:
  - Vault by HashiCorp - More mature, steeper learning curve
  - External Secrets Operator - Works with multiple secret backends
  - Sealed Secrets - GitOps-friendly, but no central management