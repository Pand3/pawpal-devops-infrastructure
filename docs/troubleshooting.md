# PawPal Troubleshooting

## Overview

This document records the main problems encountered while building the PawPal DevOps deployment and the steps used to diagnose and resolve them.

The project involved several different layers:

```text
GitHub Actions
      │
      ▼
Docker
      │
      ▼
Terraform
      │
      ▼
Microsoft Azure
      │
      ▼
Networking / Tailscale
      │
      ▼
Ansible
      │
      ▼
PawPal
```

Documenting these problems is important because troubleshooting infrastructure requires identifying **which layer is actually failing** rather than immediately changing configuration.

---

# Terraform and Azure

## Azure Region Restricted by Policy

### Problem

Terraform attempted to deploy resources to an Azure region that was not permitted by the subscription.

Azure returned an error similar to:

```text
RequestDisallowedByAzure
```

The Terraform configuration itself was valid, but Azure Policy prevented the deployment.

### Investigation

The subscription's Azure Policy assignments were inspected using the Azure CLI.

```bash
az policy assignment list   --scope /subscriptions/<SUBSCRIPTION_ID>   -o table
```

The policy parameters were then inspected to determine which Azure locations were allowed.

### Resolution

The Terraform configuration was changed to use an allowed Azure region.

Spain Central was selected for the PawPal infrastructure.

### Lesson Learned

Terraform configuration can be technically correct while still being rejected by cloud-level policies.

When Azure rejects a resource deployment, check:

```text
Terraform syntax
      │
      ▼
Provider configuration
      │
      ▼
Azure subscription policy
      │
      ▼
Regional availability
```

---

# VM Size Unavailable

## Problem

The VM was initially configured to use:

```text
Standard_B1s
```

Azure returned:

```text
SkuNotAvailable
```

with a message explaining that the requested VM size was unavailable in `SpainCentral` because of capacity restrictions.

### Investigation

Available B-series VM SKUs were checked with:

```bash
az vm list-skus   --location spaincentral   --resource-type virtualMachines   --query "[?starts_with(name, 'Standard_B')].{Name:name,Size:name,Restrictions:restrictions}"   -o table
```

The results showed other B-series VM sizes available in the region.

### Resolution

The Terraform VM size was changed to an available B-series SKU.

Terraform was then run again:

```bash
terraform plan
terraform apply
```

### Lesson Learned

A VM size being supported by an Azure region does not guarantee that Azure currently has capacity for that SKU.

Cloud capacity can change independently of the Terraform configuration.

---

# Existing Azure Resource Not in Terraform State

## Problem

Terraform attempted to create a Virtual Network that already existed in Azure.

The error stated:

```text
a resource with the ID "..." already exists -
to be managed via Terraform this resource needs
to be imported into the State
```

A similar problem occurred with the Network Security Group.

### Cause

The resources existed in Azure, but Terraform did not have them recorded correctly in its state.

The situation was effectively:

```text
Terraform configuration
        │
        ├── VNet defined
        │
        └── NSG defined

Terraform state
        │
        └── Missing resources

Azure
        │
        ├── VNet exists
        └── NSG exists
```

Terraform therefore assumed it needed to create them.

### Investigation

The resources were checked directly using Azure CLI.

For the VNet:

```bash
az network vnet show   --resource-group pawpal-devops-rg   --name pawpal-vnet   -o table
```

For the NSG:

```bash
az network nsg show   --resource-group pawpal-devops-rg   --name pawpal-nsg   -o table
```

Both resources existed and had successfully provisioned.

### Resolution

The existing Azure resources were imported into Terraform state.

General syntax:

```bash
terraform import <terraform-resource> <azure-resource-id>
```

After importing:

```bash
terraform plan
```

was used to verify the state.

The desired result was:

```text
No changes. Your infrastructure matches the configuration.
```

### Lesson Learned

Terraform uses three separate sources of information:

```text
Configuration
State
Actual Infrastructure
```

A resource existing in Azure does not automatically mean Terraform knows it exists.

---

# Subnet Failed Because VNet Was Reported Missing

## Problem

Terraform attempted to create:

```text
pawpal-subnet
```

but Azure returned:

```text
ResourceNotFound:
The Resource 'Microsoft.Network/virtualNetworks/pawpal-vnet'
under resource group 'pawpal-devops-rg' was not found.
```

### Investigation

The VNet was checked directly:

```bash
az network vnet show   --resource-group pawpal-devops-rg   --name pawpal-vnet   -o table
```

Azure reported:

```text
ProvisioningState: Succeeded
```

This confirmed that the VNet did exist.

### Resolution

Terraform state was corrected so that the existing VNet was properly managed by Terraform.

After the VNet was correctly represented in state, Terraform could create dependent resources such as the subnet.

### Lesson Learned

When a dependent Terraform resource fails, verify the parent resource in both:

```text
Azure
and
Terraform state
```

Do not assume either side is correct without checking.

---

# Terraform Plan Changed From Four to Five Resources

## Problem

A Terraform plan initially showed:

```text
Plan: 4 to add, 0 to change, 0 to destroy.
```

After another operation, it showed:

```text
Plan: 5 to add, 0 to change, 0 to destroy.
```

### Cause

Terraform plans are calculated from the current combination of:

- Terraform configuration
- Terraform state
- Real infrastructure
- Provider refresh results

If state changes, resources are imported, configuration changes, or Terraform discovers different infrastructure during refresh, the plan can change.

### Lesson Learned

A Terraform plan is not a permanent list of actions.

Always review the latest:

```bash
terraform plan
```

immediately before applying changes.

---

# Terraform State Still Contained an SSH Rule

## Problem

The Terraform NSG configuration no longer visibly contained the `allow-ssh` rule, but Azure still showed:

```text
allow-ssh
```

and Terraform reported:

```text
No changes. Your infrastructure matches the configuration.
```

### Investigation

The NSG's Terraform state was inspected:

```bash
terraform state show azurerm_network_security_group.pawpal
```

The output revealed that the state still contained:

```text
security_rule {
    name = "allow-ssh"
    ...
}
```

A repository search was also performed:

```bash
grep -R "allow-ssh\|azurerm_network_security_rule" .
```

The rule appeared in Terraform state and backup state files.

### Lesson Learned

When Terraform's behaviour does not appear to match the visible configuration, inspect:

```bash
terraform state show <resource>
```

The state may explain what Terraform believes it is managing.

---

# Network Security Group Was Not Associated With the VM

## Problem

An NSG containing an SSH rule existed, but SSH connectivity still did not work as expected.

### Cause

Creating a Network Security Group does not automatically apply it to a VM.

The NSG must be associated with either:

- A subnet
- A network interface

The project associated the NSG with the VM's NIC.

### Resolution

A Terraform association resource was added:

```hcl
resource "azurerm_network_interface_security_group_association" "pawpal" {
  network_interface_id      = azurerm_network_interface.pawpal.id
  network_security_group_id = azurerm_network_security_group.pawpal.id
}
```

Terraform then showed:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

After applying it, the NSG was attached to the VM's networking.

### Lesson Learned

A firewall object existing in the cloud does not mean it is protecting anything.

Always verify the association between the firewall/security group and the actual network resource.

---

# SSH Connection Hung at Port 22

## Problem

SSH debugging showed:

```text
Connecting to <PUBLIC_IP> [<PUBLIC_IP>] port 22.
```

but nothing else happened.

### Investigation

Verbose SSH was used:

```bash
ssh -vvv -i ~/.ssh/pawpal_azure azureuser@<PUBLIC_IP>
```

The connection stopped while attempting to establish TCP connectivity.

This indicated that the failure happened before SSH authentication.

The problem therefore pointed toward:

```text
Network connectivity
NSG rules
NSG association
Firewall
```

rather than the SSH key.

### Resolution

The Azure NSG configuration and its NIC association were checked and corrected.

### Lesson Learned

Verbose SSH output helps identify the stage where the connection fails.

If it stops at:

```text
Connecting to ... port 22
```

the issue is likely networking rather than authentication.

---

# Tailscale SSH Worked While Public SSH Was Blocked

## Goal

After Tailscale was configured, the project intentionally removed public SSH access.

### Verification

Public SSH was tested using the Azure public IP:

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<PUBLIC_IP>
```

This failed as expected.

SSH using the Tailscale IP:

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<TAILSCALE_IP>
```

continued to work.

### Result

```text
Public IP + SSH
      │
      ✕
   Blocked

Tailscale IP + SSH
      │
      ✓
   Allowed
```

### Lesson Learned

Security controls should be tested from the client side rather than assumed to work because the configuration looks correct.

---

# Ansible Connectivity

## Testing Ansible SSH

Before running the full playbook, Ansible connectivity was tested with:

```bash
ansible all -i azure-inventory.ini -m ping
```

A successful response was:

```text
pawpal | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}
```

This confirmed:

- SSH worked
- The inventory was valid
- The SSH key worked
- Python was available on the VM
- Ansible could execute modules remotely

### Lesson Learned

Use the smallest possible test before running a large automation workflow.

For Ansible:

```text
ansible ping
     │
     ▼
syntax check
     │
     ▼
full playbook
```

is easier to troubleshoot than immediately running the entire deployment.

---

# Ansible Playbook Appeared to Hang During APT Update

## Problem

The playbook remained for a long time at:

```text
TASK [Update apt package cache after adding Docker repository]
```

Warnings then appeared:

```text
Failed to update cache after 1 retries
Failed to update cache after 2 retries
...
```

### Cause

The VM could reach Docker's repository, but the Azure Ubuntu package mirror was timing out.

Ansible itself was not frozen.

It was waiting for APT network operations and retrying failed package-index downloads.

### Lesson Learned

A long-running Ansible task is not necessarily an Ansible problem.

Check what the underlying command is doing on the remote server.

---

# Azure Ubuntu Package Mirror Timeout

## Problem

Docker installation failed because APT could not download `pigz`.

The error included:

```text
Failed to fetch http://azure.archive.ubuntu.com/ubuntu/...
Could not connect to azure.archive.ubuntu.com:80
connection timed out
```

Docker packages from:

```text
https://download.docker.com/
```

downloaded successfully.

The Ubuntu dependency from:

```text
http://azure.archive.ubuntu.com/
```

did not.

### Investigation

The problem was reproduced manually on the Azure VM.

```bash
sudo apt update
```

returned repeated timeouts for:

```text
azure.archive.ubuntu.com
```

Then:

```bash
sudo apt install pigz
```

failed with the same error.

This proved that the problem was below the Ansible layer.

```text
Ansible
   │
   ▼
APT
   │
   ▼
Ubuntu mirror
   │
   ✕ timeout
```

### Resolution

The Ubuntu package source/mirror issue was corrected.

After APT could successfully retrieve packages, the Ansible playbook was run again and Docker installation completed.

### Lesson Learned

When an Ansible package task fails, reproduce the package command directly on the remote host.

This distinguishes:

```text
Ansible problem
```

from:

```text
Operating system / repository / networking problem
```

---

# Docker Socket Permission Denied

## Problem

After Docker was installed:

```bash
docker ps
```

returned:

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

### Cause

The current Linux user did not have permission to access Docker's Unix socket.

Docker normally communicates through:

```text
/var/run/docker.sock
```

### Investigation

The command could be tested with elevated privileges:

```bash
sudo docker ps
```

If that works, Docker itself is running and the remaining problem is user permissions.

### Resolution

The required user was granted Docker access and the new group membership was applied.

Afterwards:

```bash
docker ps
```

worked without `sudo`.

### Security Note

Membership in the `docker` group provides significant control over the host.

Only trusted users should be granted Docker daemon access.

---

# Ansible `apt_repository` Deprecation Warning

## Problem

Ansible displayed:

```text
apt_repository has been deprecated.
Use deb822_repository instead.
```

### Impact

This was a warning rather than the cause of the deployment failure.

The existing task still executed.

### Resolution

The warning was documented as a future maintenance improvement.

The playbook can later migrate from:

```yaml
apt_repository:
```

to:

```yaml
deb822_repository:
```

### Lesson Learned

Differentiate between:

```text
WARNING
```

and:

```text
ERROR / FAILED
```

Warnings may require future maintenance but are not necessarily responsible for the current failure.

---

# Ansible Python Interpreter Warning

## Warning

Ansible reported that the host was using:

```text
/usr/bin/python3.12
```

and warned that installing another Python interpreter could change interpreter discovery.

### Impact

The playbook still worked.

### Lesson Learned

This warning is useful for reproducibility but was not a deployment failure.

For stricter environments, the Python interpreter can be explicitly configured in the inventory.

---

# Ansible Syntax Validation

Before rerunning the full deployment, the playbook was checked with:

```bash
ansible-playbook   -i azure-inventory.ini   azure-playbook.yml   --syntax-check
```

The result:

```text
playbook: azure-playbook.yml
```

confirmed that the playbook could be parsed.

### Lesson Learned

Syntax checking is a fast validation step before contacting the remote server.

---

# Git Path Error When Adding Workflow

## Problem

While inside:

```text
.github/workflows/
```

the following command was used:

```bash
git add .github/workflows/deploy.yml
```

Git returned:

```text
warning: could not open directory '.github/workflows/.github/workflows/'
fatal: pathspec '.github/workflows/deploy.yml' did not match any files
```

### Cause

Git interpreted the path relative to the current working directory.

Because the shell was already inside `.github/workflows`, Git effectively looked for:

```text
.github/workflows/.github/workflows/deploy.yml
```

### Resolution

From inside `.github/workflows`:

```bash
git add deploy.yml
```

Alternatively, return to the repository root and use:

```bash
git add .github/workflows/deploy.yml
```

### Lesson Learned

Relative paths depend on the shell's current working directory.

Check it with:

```bash
pwd
```

when a path unexpectedly cannot be found.

---

# GitHub Actions Azure Application Registration Failed

## Problem

To configure GitHub Actions authentication with Azure, an application registration was attempted:

```bash
az ad app create --display-name "pawpal-github-actions"
```

Azure returned:

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

### Cause

Azure subscription permissions and Microsoft Entra directory permissions are separate.

```text
Azure Subscription RBAC
       │
       └── Owner ✓

Microsoft Entra Directory
       │
       └── Application registration permission ✕
```

Being subscription Owner did not grant the directory permission required to create an application registration.

### Resolution

Full GitHub Actions → Azure OIDC authentication was left as a future improvement.

No insecure workaround or long-lived credential was added simply to make the pipeline appear complete.

### Lesson Learned

Cloud permissions exist at multiple layers.

Azure RBAC roles do not automatically provide Microsoft Entra directory permissions.

---

# Terraform Files and Git

## Problem

Terraform generates local files that should not be committed.

Examples include:

```text
terraform.tfstate
terraform.tfstate.backup
.terraform/
```

### Resolution

Terraform-generated state and local data were added to `.gitignore`.

Example:

```gitignore
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.*
terraform/*.tfvars
terraform/*.tfvars.json
terraform/*.tfplan
```

### Lesson Learned

Terraform configuration belongs in source control.

Terraform state generally does not belong in a public Git repository.

---

# Ansible Inventory and Git

## Concern

The Ansible inventory contained:

```ini
pawpal ansible_host=100.x.x.x ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/pawpal_azure
```

The inventory does not contain the private key itself, but it exposes environment-specific information such as:

- Tailscale IP
- Username
- Local key path

### Approach

The actual SSH private key remains outside the repository.

Environment-specific inventory data can either be ignored or replaced with an example inventory such as:

```text
azure-inventory.ini.example
```

Example:

```ini
[server]
pawpal ansible_host=<TAILSCALE_IP> ansible_user=<VM_USER> ansible_ssh_private_key_file=~/.ssh/<PRIVATE_KEY>
```

### Lesson Learned

Not every configuration file is a secret, but environment-specific details should still be reviewed before publishing a repository.

---

# Troubleshooting Method

A useful pattern throughout the project was to troubleshoot from the lowest relevant layer upward.

For example, when Ansible failed to install Docker:

```text
Ansible task failed
       │
       ▼
Inspect error
       │
       ▼
APT download failure
       │
       ▼
SSH into VM
       │
       ▼
Run apt manually
       │
       ▼
Same failure reproduced
       │
       ▼
Repository/network issue identified
```

This prevented unnecessary changes to the Ansible playbook.

---

# Useful Diagnostic Commands

## Terraform

```bash
terraform plan
```

```bash
terraform state list
```

```bash
terraform state show <resource>
```

## Azure

```bash
az vm show -d   --resource-group pawpal-devops-rg   --name pawpal-vm   -o table
```

```bash
az network vnet show   --resource-group pawpal-devops-rg   --name pawpal-vnet   -o table
```

```bash
az network nsg rule list   --resource-group pawpal-devops-rg   --nsg-name pawpal-nsg   -o table
```

## SSH

```bash
ssh -vvv -i ~/.ssh/pawpal_azure azureuser@<IP>
```

## Tailscale

```bash
tailscale status
```

```bash
tailscale ip -4
```

## Ansible

```bash
ansible all -i azure-inventory.ini -m ping
```

```bash
ansible-playbook   -i azure-inventory.ini   azure-playbook.yml   --syntax-check
```

## Ubuntu

```bash
sudo apt update
```

## Docker

```bash
docker ps
```

```bash
sudo systemctl status docker
```

## Git

```bash
pwd
```

```bash
git status
```

These commands helped identify which component was responsible for a failure.

---

# Key Lessons Learned

The main troubleshooting lessons from this project were:

1. **Check the real Azure resource before assuming Terraform is correct.**

2. **Terraform configuration, Terraform state, and actual infrastructure are separate things.**

3. **Review every new Terraform plan before applying it.**

4. **Azure Policy can reject otherwise valid infrastructure.**

5. **Cloud VM SKU availability can change by region and capacity.**

6. **An NSG must be associated with a subnet or NIC before it affects traffic.**

7. **Use verbose SSH output to determine whether a failure is networking or authentication.**

8. **Test security controls instead of assuming they work.**

9. **Test Ansible connectivity before running a full playbook.**

10. **Reproduce Ansible package failures directly on the remote host.**

11. **Warnings and failures should be treated differently.**

12. **Git paths are relative to the current working directory.**

13. **Azure subscription Owner permissions are different from Microsoft Entra directory permissions.**

14. **Terraform state and private credentials should not be committed to Git.**

15. **Automation is most useful when each tool has a clearly defined responsibility.**

---

# Final Troubleshooting Approach

The project reinforced a general troubleshooting workflow:

```text
Observe the error
      │
      ▼
Identify the failing layer
      │
      ▼
Reduce the problem
      │
      ▼
Test the component directly
      │
      ▼
Confirm the root cause
      │
      ▼
Apply the smallest fix
      │
      ▼
Retest
      │
      ▼
Verify the complete system
```

This approach was used across Terraform, Azure, networking, SSH, Ansible, Docker, Git, and GitHub Actions rather than making unrelated changes until the problem disappeared.
