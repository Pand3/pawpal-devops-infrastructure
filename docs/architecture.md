# PawPal Architecture

## Overview

PawPal uses a layered DevOps architecture where each tool is responsible for a specific part of the application lifecycle.

The main goal is to separate:

- Application development
- Continuous integration
- Infrastructure provisioning
- Server configuration
- Containerisation
- Secure server administration

This makes the environment reproducible and easier to maintain.

## High-Level Architecture

```text
                         ┌──────────────────┐
                         │     Developer    │
                         └────────┬─────────┘
                                  │
                                  │ git push
                                  ▼
                         ┌──────────────────┐
                         │     GitHub       │
                         │   Repository     │
                         └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
           ┌─────────────────┐        ┌─────────────────┐
           │  GitHub Actions │        │   Docker Image  │
           │       CI        │        │      GHCR       │
           └────────┬────────┘        └────────┬────────┘
                    │                          │
                    │ validation               │ image pull
                    │                          │
                    ▼                          │
           ┌─────────────────┐                  │
           │    Terraform    │                  │
           │ Infrastructure  │                  │
           │      as Code    │                  │
           └────────┬────────┘                  │
                    │                           │
                    │ provisions                │
                    ▼                           │
        ┌────────────────────────────┐           │
        │       Microsoft Azure     │           │
        │                            │           │
        │  ┌──────────────────────┐  │           │
        │  │        VNet          │  │           │
        │  │          │           │  │           │
        │  │       Subnet         │  │           │
        │  │          │           │  │           │
        │  │        NIC           │  │           │
        │  │          │           │  │           │
        │  │       Linux VM       │◄─┼───────────┘
        │  │          │           │  │
        │  └──────────┼───────────┘  │
        │             │              │
        │            NSG             │
        └─────────────┼──────────────┘
                      │
                      │ Tailscale
                      ▼
              ┌─────────────────┐
              │     Ansible     │
              │ Configuration   │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │     Docker      │
              │                 │
              │  ┌───────────┐  │
              │  │  PawPal   │  │
              │  │ Container │  │
              │  └───────────┘  │
              └─────────────────┘
```

## Application Layer

PawPal is the application being deployed.

The application is containerised using Docker so that the runtime environment is consistent between development and deployment.

The container exposes the application on port `3000`.

```text
PawPal
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
Docker container
  │
  ▼
Port 3000
```

## CI Layer

GitHub Actions provides continuous integration for the repository.

The CI workflow is responsible for validating application changes before they are considered ready for deployment.

The general flow is:

```text
Code change
    │
    ▼
git push
    │
    ▼
GitHub Actions
    │
    ├── Install dependencies
    ├── Run tests
    └── Run linting
```

This separates application validation from infrastructure management.

## Infrastructure Layer

Terraform manages the Azure infrastructure.

Instead of manually creating resources through the Azure Portal, the infrastructure is defined as code.

```text
Terraform
    │
    ├── Resource Group
    │
    ├── Virtual Network
    │      └── Subnet
    │
    ├── Network Security Group
    │
    ├── Public IP
    │
    ├── Network Interface
    │
    └── Linux Virtual Machine
```

Terraform state is used to track the relationship between the Terraform configuration and the actual Azure resources.

## Azure Network

The Azure VM is placed inside a dedicated virtual network.

```text
Azure
└── Resource Group
    │
    ├── Virtual Network
    │   │
    │   └── Subnet
    │       │
    │       └── Network Interface
    │           │
    │           └── Linux VM
    │
    ├── Network Security Group
    │
    └── Public IP
```

The Network Security Group controls network access to the infrastructure.

SSH is not intended to be exposed publicly. Administrative SSH access is performed through Tailscale.

## Secure Administration

Tailscale provides a private network connection between the developer's machine and the Azure VM.

```text
Developer machine
       │
       │ Tailscale
       ▼
Tailscale network
       │
       ▼
Azure VM
       │
       │ SSH
       ▼
Ansible
```

This allows Ansible to configure the server using its Tailscale IP rather than relying on the VM's public IP.

The public Azure IP therefore does not need to provide SSH access.

## Configuration Management

Ansible operates at the server configuration layer.

Terraform answers:

> "What infrastructure should exist?"

Ansible answers:

> "How should the server be configured?"

The relationship is:

```text
Terraform
   │
   │ Creates VM
   ▼
Azure VM
   │
   │ Tailscale SSH
   ▼
Ansible
   │
   ├── Configure packages
   ├── Configure Docker repository
   ├── Install Docker
   ├── Start Docker
   ├── Pull PawPal image
   └── Run PawPal
```

This separation prevents Terraform from becoming responsible for application-level server configuration.

## Container Layer

Docker provides the application runtime on the VM.

```text
Azure VM
│
└── Docker Engine
    │
    └── PawPal container
        │
        └── Application :3000
```

Ansible ensures Docker is installed and running before deploying the PawPal container.

## Deployment Lifecycle

The complete deployment lifecycle is:

```text
1. Develop
      │
      ▼
2. Push to GitHub
      │
      ▼
3. GitHub Actions CI
      │
      ▼
4. Build / publish Docker image
      │
      ▼
5. Terraform provisions Azure
      │
      ▼
6. Tailscale provides private access
      │
      ▼
7. Ansible configures VM
      │
      ▼
8. Docker pulls PawPal image
      │
      ▼
9. PawPal container runs
```

## Infrastructure Lifecycle

One of the goals of the project is reproducibility.

The infrastructure can be created and removed using Terraform:

```text
terraform apply
      │
      ▼
Azure infrastructure
      │
      ▼
VM configuration
      │
      ▼
PawPal deployment
```

When the environment is no longer required:

```text
terraform destroy
      │
      ▼
Azure resources removed
```

This allows the project to avoid relying on manually created, permanent cloud infrastructure.

## Design Principles

### Separation of responsibilities

Each technology has a specific responsibility:

| Technology | Responsibility |
|---|---|
| Git | Version control |
| GitHub | Source code hosting |
| GitHub Actions | CI and workflow automation |
| Docker | Application packaging |
| GitHub Container Registry | Container image storage |
| Terraform | Infrastructure provisioning |
| Azure | Cloud infrastructure |
| Tailscale | Private network access |
| Ansible | Server configuration |
| Ubuntu | Server operating system |

### Infrastructure as Code

Infrastructure is defined in Terraform rather than being dependent on manual Azure Portal configuration.

### Configuration as Code

Server configuration is defined in Ansible playbooks rather than being performed manually over SSH.

### Private administration

Tailscale provides the management path to the VM, reducing the need to expose SSH publicly.

### Reproducibility

The environment can be recreated from the repository's infrastructure and configuration code rather than depending on undocumented manual steps.

## Future Architecture Improvements

The current architecture can be extended with:

- GitHub Actions OIDC authentication with Azure
- Fully automated deployment after successful CI
- HTTPS through a reverse proxy
- Application health checks
- Prometheus and Grafana monitoring
- Centralised logging
- Automated deployment rollback
- Separate development and production environments
- Managed secrets through Azure Key Vault
