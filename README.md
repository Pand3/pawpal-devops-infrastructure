# PawPal DevOps Infrastructure

DevOps infrastructure and deployment pipeline for **PawPal**, a pet-minder web application. This project demonstrates how a web application can be containerised, provisioned on Microsoft Azure using Infrastructure as Code, configured with Ansible, and securely administered through Tailscale.

## Overview

The goal of this project is to build a production-style infrastructure workflow around the PawPal application while gaining practical experience with cloud infrastructure, automation, networking, containerisation, and CI/CD.

## Related Repository

This repository contains the DevOps infrastructure and deployment configuration for the **PawPal Pet Minder application**.

The application source code is maintained separately:

**Application Repository:** [Pet-Minder-Mobile-App](https://github.com/Pand3/Pet-Minder-App)

The two repositories have separate responsibilities:

- **Pet-Minder-Mobile-App** — application source code, testing, and container image creation.
- **pawpal-devops-infrastructure** — Azure infrastructure, Terraform, Ansible, networking, security, and deployment automation.

Then your README would roughly start:
### Technologies

- **Microsoft Azure** — Cloud infrastructure
- **Terraform** — Infrastructure as Code
- **Ansible** — Server configuration and application deployment
- **Docker** — Application containerisation
- **Tailscale** — Private network access and SSH administration
- **GitHub Actions** — Continuous integration and workflow automation
- **Ubuntu/Linux** — Server operating system

## Architecture

```text
                         GitHub
                           │
                           │ Push
                           ▼
                   GitHub Actions
                      ┌────┴────┐
                      │         │
                     CI      Deployment
                      │         │
                      │         ▼
                      │     Terraform
                      │         │
                      │         ▼
                      │   Microsoft Azure
                      │         │
                      │    ┌────┴─────┐
                      │    │          │
                      │   VNet       NSG
                      │    │
                      │  Subnet
                      │    │
                      │   NIC
                      │    │
                      │    ▼
                      │ Azure VM
                      │    │
                      │ Tailscale
                      │    │
                      │ Ansible
                      │    │
                      │ Docker
                      │    │
                      │    ▼
                      └─ PawPal
```

## Infrastructure

Terraform provisions the Azure infrastructure required to host PawPal.

| Resource | Purpose |
|---|---|
| Resource Group | Contains the Azure resources |
| Virtual Network | Provides the VM's private Azure network |
| Subnet | Network segment for the VM |
| Network Interface | Connects the VM to the subnet |
| Network Security Group | Controls network traffic |
| Public IP | Provides Azure-level public connectivity |
| Linux Virtual Machine | Hosts the PawPal application |

Terraform allows the infrastructure to be recreated or destroyed consistently rather than relying on manually configured Azure resources.

## Server Configuration

Ansible is used to configure the Azure VM after it has been provisioned.

The playbook performs tasks including:

1. Updating the Ubuntu package cache
2. Installing required packages
3. Configuring the Docker package repository
4. Installing Docker Engine and Docker Compose
5. Starting and enabling the Docker service
6. Pulling the PawPal container image
7. Running the PawPal container

This keeps server configuration separate from infrastructure provisioning.

## Containerisation

PawPal is packaged as a Docker image.

The deployed container runs the application on port `3000`.

```text
Azure VM
│
└── Docker
    │
    └── pawpal container
        │
        └── Port 3000
```

The Docker image is published to GitHub Container Registry and can be pulled by the Ansible deployment process.

## Networking and Security

A key part of the project is avoiding direct public SSH access to the VM.

The Azure Network Security Group does not expose SSH to the public internet. Instead, the VM is accessed through its Tailscale address.

```text
Laptop
   │
   │ Tailscale
   ▼
Tailscale network
   │
   ▼
Azure VM
   │
   └── SSH
```

This provides a private management path to the server without requiring port `22` to be publicly accessible.

## CI/CD

GitHub Actions is used for continuous integration.

The CI workflow performs automated checks on changes pushed to the repository, helping ensure that changes do not introduce obvious problems before deployment.

The repository also contains a deployment workflow that provides the foundation for automating infrastructure and application deployment.

The architecture separates:

- **CI** — Testing and validating application changes
- **Infrastructure** — Terraform-managed Azure resources
- **Configuration** — Ansible-managed server configuration
- **Application deployment** — Docker-based PawPal deployment

## Repository Structure

```text
Pet-Minder-Mobile-App/
│
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml
│
├── ansible/
│   ├── azure-inventory.ini
│   └── azure-playbook.yml
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── providers.tf
│
├── docs/
│   ├── architecture.md
│   ├── infrastructure.md
│   ├── networking.md
│   ├── security.md
│   ├── deployment.md
│   ├── ci-cd.md
│   └── troubleshooting.md
│
├── Dockerfile
├── package.json
├── package-lock.json
├── .gitignore
└── README.md
```

## Deployment Workflow

The infrastructure and application follow this general deployment process:

```text
1. Application code
       │
       ▼
2. GitHub
       │
       ▼
3. GitHub Actions
       │
       ▼
4. Terraform
       │
       ▼
5. Azure infrastructure
       │
       ▼
6. Ansible
       │
       ▼
7. Docker
       │
       ▼
8. PawPal
```

Terraform is responsible for the infrastructure layer, while Ansible handles configuration and application deployment.

This follows the principle:

> **Terraform provisions infrastructure; Ansible configures it.**

## Troubleshooting and Lessons Learned

Building the infrastructure involved several real-world cloud and Linux administration issues.

### Azure region restrictions

The Azure subscription had a policy restricting deployments to a specific set of regions. This required checking the subscription's policy assignments and selecting an allowed region.

### VM SKU availability

Even after selecting an allowed region, the `Standard_B1s` VM size was unavailable due to Azure capacity restrictions.

The available VM SKUs were inspected using the Azure CLI before selecting an alternative B-series VM size.

### Terraform state

Some Azure resources existed in Azure but were missing from Terraform state. Terraform therefore required those resources to be imported before it could manage them correctly.

This demonstrated the difference between:

- The actual infrastructure
- Terraform configuration
- Terraform state

### Network troubleshooting

The Azure VM initially had connectivity issues with the Azure Ubuntu package mirror. Docker packages could be downloaded successfully while packages from `azure.archive.ubuntu.com` timed out.

This was diagnosed from the VM directly using `apt update` and package installation commands.

### Secure SSH access

Rather than leaving SSH publicly accessible, Tailscale was configured so that administrative access could take place over the private Tailscale network.

## Key DevOps Concepts Demonstrated

This project demonstrates practical experience with:

- Infrastructure as Code
- Cloud infrastructure provisioning
- Terraform state management
- Azure networking
- Network Security Groups
- Linux server administration
- SSH
- Tailscale networking
- Ansible configuration management
- Ansible idempotency
- Docker containerisation
- GitHub Container Registry
- GitHub Actions
- Continuous integration
- Automated server configuration
- Infrastructure troubleshooting

## Future Improvements

Potential future improvements include:

- Fully automate Azure authentication for GitHub Actions using OIDC
- Automatically deploy after successful CI
- Add automated infrastructure testing
- Add monitoring with Prometheus and Grafana
- Add HTTPS through a reverse proxy
- Add application health checks
- Add automated rollback strategies
- Improve secrets management
- Add deployment environments such as development and production

## Technologies

| Technology | Role |
|---|---|
| Ubuntu | Server operating system |
| Azure | Cloud platform |
| Terraform | Infrastructure as Code |
| Ansible | Configuration management |
| Docker | Containerisation |
| Tailscale | Private networking |
| GitHub Actions | CI/CD |
| GitHub Container Registry | Container image registry |
| Node.js | PawPal runtime |
| Git | Version control |

## Project Goals

The primary goal of this project is to demonstrate the complete lifecycle of deploying and managing a web application using modern DevOps practices:

**Develop → Test → Containerise → Provision → Configure → Deploy → Secure → Destroy**

The infrastructure is intentionally reproducible so that the Azure environment can be created when required and destroyed afterwards without relying on permanent manually configured infrastructure.
