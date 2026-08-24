# PawPal CI/CD

## Overview

PawPal uses **GitHub Actions** to automate continuous integration tasks and provides the foundation for a future fully automated deployment pipeline.

The project separates the pipeline into two concepts:

- **Continuous Integration (CI)** — validates application changes.
- **Continuous Deployment/Delivery (CD)** — deploys validated changes to the Azure environment.

The CI portion is implemented through GitHub Actions. The deployment infrastructure and configuration are automated with Terraform and Ansible, but the complete Azure deployment is not currently triggered automatically by GitHub Actions.

This distinction is intentional so the repository accurately represents what has been implemented.

---

# Pipeline Architecture

```text
Developer
    │
    │ git push
    ▼
GitHub Repository
    │
    ▼
GitHub Actions
    │
    ├──────────── CI ────────────┐
    │                            │
    │                     Install dependencies
    │                            │
    │                         Tests
    │                            │
    │                        ESLint
    │                            │
    │                     Docker build
    │                            │
    │                            ▼
    │                     CI validation
    │
    └──────────── CD ────────────┐
                                 │
                          Future automation
                                 │
                         ┌───────┴────────┐
                         │                │
                    Terraform         Ansible
                         │                │
                         ▼                ▼
                    Azure VM          Configure VM
                                          │
                                          ▼
                                        Docker
                                          │
                                          ▼
                                        PawPal
```

---

# Repository Workflows

GitHub Actions workflows are stored in:

```text
.github/
└── workflows/
    ├── ci.yml
    └── deploy.yml
```

Each YAML file defines a separate GitHub Actions workflow.

---

# Continuous Integration

The CI workflow validates changes pushed to the repository.

The purpose of CI is to catch problems before application changes progress further through the deployment process.

The general workflow is:

```text
git push
    │
    ▼
GitHub Actions
    │
    ▼
Checkout repository
    │
    ▼
Set up Node.js
    │
    ▼
Install dependencies
    │
    ├── npm test
    │
    ├── npm run lint
    │
    └── Docker build
    │
    ▼
CI result
```

If one of the required steps fails, the workflow fails.

---

# Why CI Is Used

Without CI, validation depends on the developer remembering to manually run every check before pushing code.

```text
Developer
   │
   ├── Maybe run tests
   ├── Maybe run linting
   └── Maybe test Docker build
```

With CI:

```text
Developer
   │
   ▼
git push
   │
   ▼
GitHub Actions
   │
   ├── Tests
   ├── Linting
   └── Build validation
```

The same checks can run consistently for repository changes.

---

# Dependency Installation

The CI pipeline installs Node.js dependencies before testing the application.

For a project containing a committed `package-lock.json`, CI can use:

```bash
npm ci
```

rather than:

```bash
npm install
```

`npm ci` installs dependencies according to the lock file and is designed for automated environments.

Conceptually:

```text
package.json
     +
package-lock.json
     │
     ▼
   npm ci
     │
     ▼
node_modules
```

This helps keep dependency installation reproducible.

---

# Automated Tests

The project defines a test command through `package.json`.

The CI workflow can execute:

```bash
npm test
```

If a test fails, the GitHub Actions job should fail.

```text
npm test
   │
   ├── PASS ──► Continue pipeline
   │
   └── FAIL ──► Stop / mark workflow failed
```

Automated tests help prevent known application behaviour from being broken by future changes.

---

# ESLint

ESLint is used to perform static analysis on the JavaScript code.

The CI workflow runs:

```bash
npm run lint
```

Linting helps identify issues such as:

- Invalid syntax
- Incorrect code patterns
- Unused variables
- Style inconsistencies
- Potential programming mistakes

The general flow is:

```text
Source Code
    │
    ▼
ESLint
    │
    ├── No errors ──► Continue
    │
    └── Errors ─────► Workflow fails
```

During development, ESLint configuration and existing lint errors had to be corrected before it could become a useful CI check.

---

# Docker Build Validation

PawPal is deployed as a Docker container, so validating that the Docker image can be built is an important part of CI.

A Docker build can be tested using:

```bash
docker build -t pawpal .
```

The CI pipeline can therefore detect problems such as:

- Invalid Dockerfile instructions
- Missing files
- Dependency installation failures
- Application build failures

before deployment.

```text
Repository
    │
    ▼
Dockerfile
    │
    ▼
docker build
    │
    ├── Success ──► Image can be deployed
    │
    └── Failure ──► CI fails
```

---

# GitHub Container Registry

The PawPal Docker image is published to **GitHub Container Registry (GHCR)**.

The image used by the deployment is:

```text
ghcr.io/pand3/pawpal:latest
```

The container lifecycle is:

```text
Application source
       │
       ▼
Docker build
       │
       ▼
Docker image
       │
       ▼
GitHub Container Registry
       │
       ▼
Azure VM
       │
       ▼
Docker pull
       │
       ▼
PawPal container
```

Using a registry means the application source does not need to be manually copied onto the Azure server.

---

# Continuous Deployment Design

The intended CD architecture is:

```text
Successful CI
      │
      ▼
Deployment workflow
      │
      ├── Authenticate to Azure
      │
      ├── Run Terraform
      │
      ├── Configure server
      │
      └── Deploy container
      │
      ▼
PawPal running in Azure
```

The repository contains a deployment workflow as the foundation for this process.

However, full Azure deployment from GitHub Actions was not completed.

---

# Azure Authentication Challenge

To allow GitHub Actions to provision Azure infrastructure, the workflow needs a secure method of authenticating with Azure.

A preferred approach is **OpenID Connect (OIDC)**.

The intended architecture is:

```text
GitHub Actions
      │
      │ OIDC token
      ▼
Microsoft Entra ID
      │
      ▼
Short-lived Azure credentials
      │
      ▼
Terraform
      │
      ▼
Azure
```

This avoids storing a long-lived Azure client secret in GitHub.

---

# Attempted Application Registration

An application registration was attempted with the Azure CLI:

```bash
az ad app create --display-name "pawpal-github-actions"
```

The command returned an insufficient privileges error.

The Azure subscription account had an `Owner` role at the subscription scope, but subscription RBAC permissions and Microsoft Entra directory permissions are separate.

Conceptually:

```text
Azure Subscription
      │
      └── Owner role ✓

Microsoft Entra ID
      │
      └── App registration permission ✕
```

Being an Azure subscription Owner therefore did not automatically grant permission to create the required Microsoft Entra application registration.

---

# Why OIDC Was Not Completed

Because the current account did not have permission to create the required application registration, the OIDC trust relationship between GitHub and Azure could not be completed.

Rather than adding insecure credentials or pretending the deployment was fully automated, the project documents this as a current limitation.

The existing project still demonstrates:

- GitHub Actions CI
- Docker image creation
- GitHub Container Registry
- Terraform infrastructure
- Ansible configuration
- Azure deployment
- Tailscale administration

The remaining work is connecting these components into a fully automated CD workflow.

---

# Current Deployment Flow

The current practical workflow is:

```text
Developer
    │
    │ git push
    ▼
GitHub
    │
    ▼
GitHub Actions CI
    │
    ├── Test
    ├── Lint
    └── Validate/build
         │
         ▼
      Docker image
         │
         ▼
        GHCR


Developer
    │
    ├── terraform apply
    │
    ▼
Azure Infrastructure
    │
    ▼
Tailscale
    │
    ▼
ansible-playbook
    │
    ▼
Docker pulls image
    │
    ▼
PawPal
```

Infrastructure and server configuration are automated as code, but the final deployment steps are currently initiated manually.

---

# Intended Future CD Flow

With GitHub-to-Azure OIDC configured, the workflow could become:

```text
Developer
    │
    ▼
git push
    │
    ▼
GitHub Actions
    │
    ▼
CI
    │
    ├── npm ci
    ├── npm test
    ├── npm run lint
    └── docker build
    │
    ▼
Publish image to GHCR
    │
    ▼
Authenticate to Azure using OIDC
    │
    ▼
Terraform
    │
    ▼
Azure Infrastructure
    │
    ▼
Ansible
    │
    ▼
Docker
    │
    ▼
PawPal
```

This would provide an end-to-end automated deployment pipeline.

---

# CI/CD Security

CI/CD systems can access infrastructure and therefore require careful credential management.

Sensitive values should never be written directly into workflow files.

For example, this should not be committed:

```yaml
password: my-real-password
```

Secrets should instead be supplied through GitHub's secret management or, preferably for Azure authentication, avoided through OIDC where possible.

Example secret reference:

```yaml
${{ secrets.SECRET_NAME }}
```

---

# Why OIDC Is Preferred

Traditional service-principal authentication can require storing values such as:

```text
Client ID
Client Secret
Tenant ID
Subscription ID
```

The client secret is a long-lived credential that must be protected and rotated.

OIDC changes the model:

```text
GitHub Actions
      │
      │ proves workflow identity
      ▼
Microsoft Entra ID
      │
      │ issues temporary credentials
      ▼
Azure
```

Benefits include:

- No long-lived Azure client secret in GitHub
- Short-lived authentication
- Trust can be restricted to a repository or branch
- Reduced secret-management overhead

---

# Workflow Failure Behaviour

A CI pipeline should fail when a required validation step fails.

For example:

```text
npm ci
   │
   ├── success
   ▼
npm test
   │
   ├── success
   ▼
npm run lint
   │
   ├── success
   ▼
Docker build
   │
   ├── success
   ▼
CI PASSED
```

If linting fails:

```text
npm ci
   │
   ▼
npm test
   │
   ▼
npm run lint
   │
   ✕
CI FAILED
```

The failed workflow provides feedback before deployment.

---

# Local Validation Before Push

The same core checks can be run locally before pushing.

```bash
npm ci
npm test
npm run lint
docker build -t pawpal .
```

This allows problems to be found locally before waiting for GitHub Actions.

The remote CI workflow still remains useful because it provides an independent and repeatable validation environment.

---

# Infrastructure Validation

Terraform can also be incorporated into CI without immediately changing Azure resources.

Useful validation commands include:

```bash
terraform fmt -check
```

```bash
terraform init -backend=false
```

```bash
terraform validate
```

This allows GitHub Actions to check the Terraform configuration even when Azure deployment credentials are unavailable.

A future pull-request workflow could perform:

```text
Pull Request
    │
    ├── Application tests
    ├── ESLint
    ├── Docker build
    ├── terraform fmt -check
    └── terraform validate
```

---

# Ansible Validation

Ansible playbooks can also be checked without deploying to the Azure VM.

The project used:

```bash
ansible-playbook   -i azure-inventory.ini   azure-playbook.yml   --syntax-check
```

A successful result confirms that Ansible can parse the playbook.

This does not guarantee that every remote task will succeed, but it catches YAML and playbook syntax problems before deployment.

---

# Pipeline Layers

The complete DevOps project can be viewed as four automation layers.

```text
Layer 1 — Application Validation
GitHub Actions
├── Tests
└── Linting

Layer 2 — Application Packaging
Docker
└── GHCR

Layer 3 — Infrastructure
Terraform
└── Azure

Layer 4 — Configuration / Deployment
Ansible
└── Docker container
```

Each layer has a clearly defined responsibility.

---

# CI/CD Troubleshooting

## Existing CI Workflow

The repository already contained:

```text
.github/workflows/ci.yml
```

Rather than replacing it unnecessarily, the existing workflow was retained and a separate deployment workflow was introduced.

This keeps CI and deployment responsibilities easier to understand.

---

## Incorrect Git Path

While adding `deploy.yml`, Git initially returned:

```text
fatal: pathspec '.github/workflows/deploy.yml' did not match any files
```

The shell was already inside:

```text
.github/workflows/
```

so using the full repository-relative path caused Git to look for:

```text
.github/workflows/.github/workflows/deploy.yml
```

From that directory, the correct command was:

```bash
git add deploy.yml
```

Alternatively, from the repository root:

```bash
git add .github/workflows/deploy.yml
```

This reinforced that Git paths are interpreted relative to the current working directory.

---

## Azure OIDC Permission Failure

### Problem

Creating the Microsoft Entra application required for GitHub Actions authentication failed with:

```text
Insufficient privileges to complete the operation.
```

### Investigation

The Azure subscription role was checked:

```bash
az role assignment list   --assignee "$(az account show --query user.name -o tsv)"   --scope "/subscriptions/<SUBSCRIPTION_ID>"   --query "[].{Role:roleDefinitionName,Scope:scope}"   -o table
```

The account had:

```text
Owner
```

at subscription scope.

### Lesson

Azure subscription RBAC and Microsoft Entra directory permissions are different permission systems.

An Azure subscription Owner may still be unable to create application registrations.

---

# CI/CD Status

The current project status can be summarised as:

| Capability | Status |
|---|---|
| GitHub source control | Implemented |
| Automated dependency installation | Implemented |
| Automated tests | Implemented |
| Automated linting | Implemented |
| Docker image build | Implemented |
| GitHub Container Registry | Implemented |
| Terraform infrastructure definition | Implemented |
| Ansible server configuration | Implemented |
| Tailscale private deployment access | Implemented |
| GitHub Actions deployment workflow foundation | Implemented |
| GitHub Actions → Azure OIDC | Not completed |
| Fully automated Terraform deployment | Future improvement |
| Fully automated Ansible deployment | Future improvement |

---

# Future Improvements

Potential CI/CD improvements include:

- Configure GitHub-to-Azure OIDC when Microsoft Entra permissions are available
- Automatically run Terraform after successful CI
- Automatically execute Ansible after infrastructure provisioning
- Add `terraform fmt -check`
- Add `terraform validate`
- Add Ansible syntax checks to CI
- Add Docker image vulnerability scanning
- Use immutable/versioned Docker image tags
- Add separate development and production environments
- Add manual approval before production deployment
- Add application health checks after deployment
- Add automatic rollback on failed health checks
- Add branch protection rules
- Require successful CI before pull requests can be merged
- Add dependency security scanning
- Add deployment notifications

---

# Key Concepts Demonstrated

The CI/CD portion of PawPal demonstrates practical experience with:

- GitHub Actions
- Continuous Integration
- CI/CD pipeline design
- Automated testing
- ESLint
- Node.js dependency installation
- Docker build automation
- GitHub Container Registry
- Terraform validation
- Ansible syntax validation
- Azure deployment architecture
- Microsoft Entra ID
- Azure RBAC
- OIDC concepts
- CI/CD secret management
- Separation of CI and CD
- Pipeline troubleshooting
- Honest documentation of implementation limitations
