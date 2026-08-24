# PawPal Infrastructure

## Overview

The PawPal cloud infrastructure is provisioned using **Terraform** and hosted on **Microsoft Azure**.

The purpose of this part of the project is to demonstrate Infrastructure as Code (IaC): instead of manually creating cloud resources through the Azure Portal, the required infrastructure is defined in Terraform configuration files.

This makes the environment reproducible, version controlled, easier to modify, and easy to destroy when it is no longer required.

## Infrastructure Architecture

```text
Microsoft Azure
│
└── Resource Group
    │
    ├── Virtual Network
    │   └── Subnet
    │       └── Network Interface
    │           └── Linux Virtual Machine
    │
    ├── Network Security Group
    └── Public IP
```

The Linux VM hosts Docker and the PawPal application. Server administration is performed through **Tailscale**, while **Ansible** configures the VM after Terraform provisions it.

## Technology Stack

| Technology | Purpose |
|---|---|
| Microsoft Azure | Cloud infrastructure |
| Terraform | Infrastructure provisioning |
| Ubuntu | VM operating system |
| Azure VNet | Private Azure networking |
| Azure NSG | Network traffic control |
| Tailscale | Private administrative access |
| Ansible | VM configuration |
| Docker | Application runtime |

## Terraform

Terraform is responsible for creating and managing the Azure infrastructure.

```text
Terraform configuration
        │
        ▼
terraform plan
        │
        ▼
terraform apply
        │
        ▼
Microsoft Azure
        │
        ▼
Infrastructure created
```

The Terraform configuration is stored separately from the application and Ansible configuration.

```text
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── providers.tf
```

Terraform-generated state and provider files are excluded from Git.

## Azure Resource Group

The resource group acts as the logical container for the PawPal infrastructure:

```text
pawpal-devops-rg
```

It groups the VM, networking resources, security group, and related Azure resources together.

## Virtual Network

The VM is connected to an Azure Virtual Network named:

```text
pawpal-vnet
```

During the project the VNet used the address space:

```text
10.0.0.0/16
```

The VNet provides the private Azure networking environment in which the VM operates.

## Subnet and Network Interface

A subnet is created inside the VNet. The VM's Azure Network Interface connects the VM to that subnet.

```text
Virtual Network
      │
      ▼
    Subnet
      │
      ▼
Network Interface
      │
      ▼
Virtual Machine
```

The Network Security Group is associated with the network interface to control network traffic.

## Network Security Group

An Azure Network Security Group controls inbound and outbound network traffic.

Public SSH was initially permitted while the server was being configured. Once Tailscale connectivity was working, the public SSH rule was removed.

The intended management paths became:

```text
Public IP → SSH ❌

Tailscale IP → SSH ✅
```

This allows the VM to remain remotely manageable without exposing SSH directly to the public internet.

Further details are documented in `networking.md` and `security.md`.

## Public IP

A public IP resource was created for the Azure VM and was useful during initial provisioning and connectivity testing.

The VM's public IP could be retrieved with:

```bash
az vm show -d \
  --resource-group pawpal-devops-rg \
  --name pawpal-vm \
  --query publicIps \
  -o tsv
```

After Tailscale was configured, the Azure NSG no longer permitted public SSH access.

## Linux Virtual Machine

The PawPal application runs on an Ubuntu Azure VM.

```text
Azure VM
├── Ubuntu
├── Tailscale
└── Docker Engine
    └── PawPal container
```

Terraform creates the VM, while Ansible handles operating-system configuration and application deployment.

```text
Terraform
   │ Provision
   ▼
Azure VM
   │ Configure
   ▼
Ansible
```

This keeps infrastructure provisioning separate from configuration management.

## Azure Region Restrictions

The Azure subscription used for the project contained an Azure Policy restricting deployments to a specific set of regions.

The policy assignment was inspected with the Azure CLI:

```bash
az policy assignment list \
  --scope /subscriptions/<SUBSCRIPTION_ID> \
  -o table
```

The allowed regions included locations such as Austria East, Spain Central, Denmark East, Norway East, and Germany West Central.

**Spain Central** was ultimately used.

This demonstrated that valid Terraform configuration can still be rejected because of organisation- or subscription-level Azure policies.

## VM SKU Availability

The project initially attempted to deploy:

```text
Standard_B1s
```

Azure returned a `SkuNotAvailable` error because that VM size did not have available capacity in the selected region.

Available B-series VM sizes were inspected with:

```bash
az vm list-skus \
  --location spaincentral \
  --resource-type virtualMachines \
  --query "[?starts_with(name, 'Standard_B')].{Name:name,Size:name,Restrictions:restrictions}" \
  -o table
```

An available B-series VM size was selected instead.

This demonstrated that a VM SKU being supported in a region does not guarantee that Azure currently has capacity to deploy it.

## Terraform State

Terraform state tracks the relationship between Terraform resources and real Azure resources.

```text
Terraform configuration
        │
        ▼
Terraform state
        │
        ▼
Azure resources
```

During development, some resources existed successfully in Azure but were not correctly represented in Terraform state following an interrupted or inconsistent apply.

Terraform then attempted to create resources that already existed and returned errors indicating that they needed to be imported.

This highlighted an important distinction:

```text
Configuration ≠ State ≠ Infrastructure
```

All three must remain consistent.

## Importing Existing Resources

When an Azure resource already exists but is missing from Terraform state, it can be imported:

```bash
terraform import <terraform-resource> <azure-resource-id>
```

For example:

```bash
terraform import azurerm_virtual_network.pawpal "<RESOURCE_ID>"
```

After importing the required resources, the infrastructure was checked using:

```bash
terraform plan
```

The final desired result was:

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed that Terraform's configuration, state, and the real Azure infrastructure were aligned.

## Terraform Workflow

### Initialise

```bash
terraform init
```

Initialises the working directory and downloads the required Terraform providers.

### Plan

```bash
terraform plan
```

Terraform compares the configuration, state, and current Azure resources and displays the changes it intends to make.

For example:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

The plan is reviewed before changes are applied.

### Apply

```bash
terraform apply
```

Creates or modifies the required Azure infrastructure.

### Verify

After deployment:

```bash
terraform plan
```

should ideally report:

```text
No changes. Your infrastructure matches the configuration.
```

### Destroy

When the temporary environment is no longer needed:

```bash
terraform destroy
```

Terraform removes the infrastructure it manages.

This allows the cloud environment to be created only when required rather than leaving the VM running permanently.

## Azure CLI Verification

The Azure CLI was used alongside Terraform to inspect the actual cloud resources during troubleshooting.

### Inspect the VNet

```bash
az network vnet show \
  --resource-group pawpal-devops-rg \
  --name pawpal-vnet \
  -o table
```

### Inspect the NSG

```bash
az network nsg show \
  --resource-group pawpal-devops-rg \
  --name pawpal-nsg \
  -o table
```

### List NSG rules

```bash
az network nsg rule list \
  --resource-group pawpal-devops-rg \
  --nsg-name pawpal-nsg \
  -o table
```

### Inspect the VM

```bash
az vm show -d \
  --resource-group pawpal-devops-rg \
  --name pawpal-vm \
  -o table
```

Using both Terraform and the Azure CLI helped distinguish between problems with Terraform configuration, Terraform state, and Azure itself.

## Infrastructure Troubleshooting

### Region Policy Restriction

**Problem:** Terraform returned `RequestDisallowedByAzure` because the selected Azure region was prohibited by subscription policy.

**Resolution:** The policy assignment and its allowed locations were inspected with Azure CLI, and the deployment region was changed to an allowed region.

### VM Capacity Restriction

**Problem:** Azure returned `SkuNotAvailable` for `Standard_B1s`.

**Resolution:** Available B-series VM SKUs were inspected for Spain Central and an available size was selected.

### Terraform Provider Inconsistent Result

**Problem:** Terraform reported:

```text
Provider produced inconsistent result after apply
```

An Azure resource had been created, but Terraform did not correctly retain the expected resource state.

**Resolution:** The actual Azure resources were inspected with Azure CLI and existing resources were imported into Terraform state where necessary.

### Existing Resources Missing From State

**Problem:** Terraform attempted to create resources that already existed in Azure.

**Resolution:** The existing resources were imported into Terraform state and `terraform plan` was used to verify that the configuration and real infrastructure matched.

## Infrastructure Security

### SSH Keys

The VM uses SSH key authentication. The private key remains on the administrator's machine and is never stored in the repository.

Example local path:

```text
~/.ssh/pawpal_azure
```

### Tailscale

Tailscale provides private connectivity between the administrator's machine and the Azure VM.

Ansible and manual SSH sessions therefore use the VM's Tailscale address.

### Network Security Group

After Tailscale connectivity was confirmed, public SSH access through the Azure NSG was removed.

```text
Internet
   │
   │ SSH
   ▼
Azure Public IP
   │
   ✕ BLOCKED

Developer
   │
   │ Tailscale
   ▼
Azure VM
   │
   ✓ SSH
```

## Files Excluded From Git

Terraform-generated state, provider data, variable files containing secrets, and credentials should not be committed.

Examples:

```gitignore
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.*
terraform/*.tfvars
terraform/*.tfvars.json
terraform/*.tfplan
```

Terraform state is excluded because it contains detailed infrastructure information and may contain sensitive values.

SSH private keys and environment files are also excluded.

## Reproducibility

A major goal of the project is that the Azure environment does not need to exist permanently.

```text
Terraform code
      │
      ▼
terraform apply
      │
      ▼
Azure infrastructure
      │
      ▼
Ansible configuration
      │
      ▼
PawPal deployment
```

When it is no longer required:

```text
terraform destroy
      │
      ▼
Azure infrastructure removed
```

The environment can later be recreated from the Terraform configuration.

## Separation of Responsibilities

Terraform and Ansible intentionally have separate responsibilities.

```text
Terraform
├── Azure networking
├── Security group
├── Network interface
└── Virtual machine

Ansible
├── Package configuration
├── Docker installation
└── PawPal deployment
```

> **Terraform provisions the infrastructure. Ansible configures the server.**

## Key Concepts Demonstrated

This infrastructure demonstrates practical experience with:

- Infrastructure as Code
- Terraform providers
- Terraform planning and applying
- Terraform state management
- Terraform resource imports
- Azure Resource Groups
- Azure Virtual Networks
- Azure subnets
- Azure Network Interfaces
- Azure Network Security Groups
- Azure Linux Virtual Machines
- Azure Policy
- Azure regional restrictions
- VM SKU capacity restrictions
- Azure CLI
- SSH key authentication
- Tailscale private networking
- Infrastructure troubleshooting
- Reproducible cloud environments
- Infrastructure destruction and cleanup

## Future Improvements

Potential improvements include:

- Store Terraform state remotely in Azure Storage
- Enable remote state locking
- Add consistent Azure resource tags
- Separate development and production environments
- Remove unnecessary public IP resources
- Add automated Terraform validation in GitHub Actions
- Add `terraform plan` checks to pull requests
- Configure GitHub Actions authentication to Azure using OIDC
- Introduce Azure Key Vault for secrets
- Add infrastructure monitoring and alerts
- Add automated infrastructure tests
