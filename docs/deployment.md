# PawPal Deployment

## Overview

PawPal is deployed to an **Ubuntu Linux virtual machine hosted on Microsoft Azure**.

The deployment separates infrastructure provisioning from server configuration:

- **Terraform** provisions the Azure infrastructure.
- **Tailscale** provides private access to the VM.
- **Ansible** configures the server.
- **Docker** runs the PawPal application.
- **GitHub Container Registry (GHCR)** stores the application image.

The overall deployment flow is:

```text
Application Code
      │
      ▼
GitHub
      │
      ▼
Docker Image
      │
      ▼
GitHub Container Registry
      │
      │
      │                     Terraform
      │                         │
      │                         ▼
      │                  Azure Infrastructure
      │                         │
      │                         ▼
      │                     Azure VM
      │                         │
      │                     Tailscale
      │                         │
      │                         ▼
      └─────────────────────► Ansible
                                │
                                ▼
                              Docker
                                │
                                ▼
                              PawPal
```

---

# Deployment Responsibilities

Each tool has a specific role in the deployment.

| Tool | Responsibility |
|---|---|
| GitHub | Source code repository |
| GitHub Actions | Continuous integration |
| GitHub Container Registry | Stores the PawPal Docker image |
| Terraform | Provisions Azure infrastructure |
| Azure | Hosts the VM and networking |
| Tailscale | Provides private connectivity |
| Ansible | Configures the VM and deploys PawPal |
| Docker | Runs the application container |

This separation keeps infrastructure provisioning, configuration management, and application deployment clearly defined.

---

# Deployment Lifecycle

The complete deployment process is:

```text
1. Develop PawPal
        │
        ▼
2. Push code to GitHub
        │
        ▼
3. Run CI checks
        │
        ▼
4. Build Docker image
        │
        ▼
5. Publish image to GHCR
        │
        ▼
6. Provision Azure with Terraform
        │
        ▼
7. Connect VM to Tailscale
        │
        ▼
8. Configure VM with Ansible
        │
        ▼
9. Pull PawPal image
        │
        ▼
10. Run Docker container
        │
        ▼
11. Access PawPal through Tailscale
```

---

# 1. Infrastructure Provisioning

Terraform is responsible for creating the Azure infrastructure required by the deployment.

From the Terraform directory:

```bash
cd terraform
```

Initialise Terraform:

```bash
terraform init
```

Review the proposed infrastructure changes:

```bash
terraform plan
```

If the plan is correct:

```bash
terraform apply
```

Terraform provisions resources including:

```text
Azure Resource Group
│
├── Virtual Network
│   └── Subnet
│       └── Network Interface
│           └── Linux VM
│
├── Network Security Group
└── Public IP
```

The Terraform plan should always be reviewed before applying infrastructure changes.

---

# 2. Verify the Azure VM

After Terraform completes, the VM can be inspected using the Azure CLI.

```bash
az vm show -d   --resource-group pawpal-devops-rg   --name pawpal-vm   -o table
```

The public IP can be retrieved with:

```bash
az vm show -d   --resource-group pawpal-devops-rg   --name pawpal-vm   --query publicIps   -o tsv
```

During the initial setup, public SSH may be temporarily required before Tailscale is configured.

Once Tailscale connectivity is working, public SSH is removed from the Azure NSG.

---

# 3. Tailscale Setup

Tailscale provides the private network used for administrative access.

The Azure VM joins the same tailnet as the administrator's machine.

Once connected, the VM receives a Tailscale IPv4 address.

On the VM:

```bash
tailscale ip -4
```

The connected devices can also be checked with:

```bash
tailscale status
```

The final SSH path is:

```text
Developer Laptop
       │
       │ Tailscale
       ▼
Private Tailnet
       │
       ▼
Azure VM
```

This allows public SSH access to be disabled.

---

# 4. Ansible Inventory

Ansible uses the VM's Tailscale address rather than its Azure public IP.

Example `azure-inventory.ini`:

```ini
[server]
pawpal ansible_host=100.x.x.x ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/pawpal_azure
```

The inventory specifies:

- `pawpal` — Ansible host alias
- `ansible_host` — Tailscale IP
- `ansible_user` — Ubuntu VM user
- `ansible_ssh_private_key_file` — local SSH private key path

The private key itself is not stored in the repository.

---

# 5. Test Ansible Connectivity

Before running the deployment playbook, Ansible connectivity should be tested.

From the Ansible directory:

```bash
cd ansible
```

Run:

```bash
ansible all -i azure-inventory.ini -m ping
```

A successful response looks similar to:

```text
pawpal | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

This confirms that:

```text
Ansible
   │
   │ SSH
   ▼
Tailscale
   │
   ▼
Azure VM
```

is working correctly.

---

# 6. Ansible Deployment

The Azure server is configured using:

```text
azure-playbook.yml
```

The playbook performs the server configuration and application deployment.

The general task sequence is:

```text
Ansible
   │
   ├── Update APT cache
   │
   ├── Install required packages
   │
   ├── Create Docker keyring directory
   │
   ├── Download Docker signing key
   │
   ├── Add Docker repository
   │
   ├── Refresh package cache
   │
   ├── Install Docker
   │
   ├── Start Docker
   │
   ├── Pull PawPal image
   │
   └── Run PawPal container
```

Run the playbook with:

```bash
ansible-playbook   -i azure-inventory.ini   azure-playbook.yml   --ask-become-pass
```

The privilege escalation password is requested interactively rather than stored in the repository.

---

# 7. Docker Installation

Ansible configures Docker's official Ubuntu package repository.

The required Docker packages include:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

The Docker service is then started and enabled.

Conceptually:

```text
Ubuntu VM
   │
   ▼
Docker repository configured
   │
   ▼
Docker installed
   │
   ▼
Docker service started
```

---

# 8. Pull PawPal Image

The PawPal image is stored in GitHub Container Registry.

The image used by the playbook is:

```text
ghcr.io/pand3/pawpal:latest
```

Ansible uses the Docker collection to pull the image.

Conceptually:

```text
GitHub Container Registry
          │
          │ docker pull
          ▼
       Azure VM
          │
          ▼
     Local Docker image
```

This means the application source does not need to be manually copied to the Azure VM.

The deployment unit is the container image.

---

# 9. Run PawPal Container

After the image has been downloaded, Ansible starts the PawPal container.

The container is configured with:

```text
Container name: pawpal
Image:          ghcr.io/pand3/pawpal:latest
Restart policy: unless-stopped
Port mapping:   3000:3000
```

The resulting architecture is:

```text
Azure VM
│
└── Docker Engine
    │
    └── pawpal
        │
        └── 3000:3000
```

The `unless-stopped` restart policy means Docker will normally restart the container after Docker or the VM restarts unless the container was explicitly stopped.

---

# 10. Verify the Container

On the VM, running containers can be checked with:

```bash
docker ps
```

The PawPal container should appear as running.

If the current Linux user does not have permission to access the Docker socket, the command may initially require:

```bash
sudo docker ps
```

The application can also be tested directly from the VM:

```bash
curl http://localhost:3000
```

A successful HTTP response confirms that the application is responding inside the VM.

---

# 11. Access PawPal Through Tailscale

Because PawPal is mapped to the VM's port `3000`, a trusted device on the same tailnet can access it using:

```text
http://<TAILSCALE_IP>:3000
```

For example:

```text
Developer Laptop
       │
       │ Tailscale
       ▼
Azure VM :3000
       │
       ▼
Docker
       │
       ▼
PawPal :3000
```

No public Azure NSG rule for port `3000` is required for this private access method.

---

# Deployment Verification

A deployment is considered successful when the following checks pass.

## Terraform

```bash
terraform plan
```

Expected:

```text
No changes. Your infrastructure matches the configuration.
```

## Tailscale

```bash
tailscale status
```

The Azure VM should appear in the tailnet.

## Ansible

```bash
ansible all -i azure-inventory.ini -m ping
```

Expected:

```text
pawpal | SUCCESS
```

## Docker

```bash
docker ps
```

Expected:

```text
pawpal
```

with the container in a running state.

## Application

```bash
curl http://localhost:3000
```

The application should respond.

## Private Application Access

From another trusted Tailscale device:

```text
http://<TAILSCALE_IP>:3000
```

should load PawPal.

## Public SSH

SSH to the Azure public IP should fail once the public NSG SSH rule has been removed.

---

# Ansible Idempotency

One benefit of configuration management is that the playbook can be run repeatedly.

If the server is already correctly configured, Ansible should report many tasks as:

```text
ok
```

rather than unnecessarily changing the system.

For example:

```text
PLAY RECAP
pawpal : ok=... changed=... unreachable=0 failed=0
```

The most important result is:

```text
failed=0
```

A second run with fewer changed tasks demonstrates that the configuration is moving toward an idempotent state.

---

# Deployment Troubleshooting

Several deployment problems were encountered during the project.

## Azure Ubuntu Mirror Timeout

### Problem

During the Ansible Docker installation, APT failed while downloading `pigz`:

```text
Could not connect to azure.archive.ubuntu.com:80
```

Most Docker packages downloaded successfully from Docker's repository, but the Ubuntu dependency could not be downloaded from the Azure Ubuntu mirror.

### Investigation

The issue was reproduced directly on the VM using:

```bash
sudo apt update
```

and:

```bash
sudo apt install pigz
```

This confirmed that the problem was not specific to Ansible.

### Resolution

The Ubuntu package source/mirror issue was corrected, after which package installation succeeded.

The Ansible playbook could then be run again.

Because Ansible tracks the desired state of each task, successfully completed tasks did not need to be manually repeated.

---

## Docker Socket Permission Error

### Problem

After Docker was installed:

```bash
docker ps
```

returned:

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

### Cause

The current Linux user did not have permission to communicate with the Docker daemon through its Unix socket.

### Resolution

Docker access was configured for the required user, after which `docker ps` worked successfully.

This also highlighted that Docker daemon access is privileged and should only be granted to trusted users.

---

## Ansible APT Repository Deprecation Warning

The playbook produced a warning indicating that:

```text
apt_repository
```

is deprecated in newer Ansible versions in favour of:

```text
deb822_repository
```

The existing task still functioned, but migrating to `deb822_repository` is a future maintenance improvement.

---

# Deployment vs Provisioning

An important design decision is keeping provisioning and configuration separate.

## Terraform

Terraform creates:

```text
Cloud infrastructure
├── Resource Group
├── VNet
├── Subnet
├── NSG
├── NIC
└── VM
```

## Ansible

Ansible configures:

```text
VM
├── APT packages
├── Docker repository
├── Docker Engine
├── Docker service
├── PawPal image
└── PawPal container
```

This provides a clear separation:

> **Terraform creates the server. Ansible prepares and deploys to the server.**

---

# Manual vs Automated Deployment

The project currently combines automated tooling with manually triggered deployment steps.

Infrastructure provisioning is defined in Terraform and server configuration is defined in Ansible, but the entire Azure deployment is not yet automatically executed by GitHub Actions.

The current flow is approximately:

```text
GitHub Actions
      │
      └── CI validation

Developer
   │
   ├── terraform apply
   │
   ├── configure Tailscale
   │
   └── ansible-playbook
             │
             ▼
           PawPal
```

This distinction is intentional in the documentation.

The project demonstrates automated infrastructure and configuration definitions without claiming a fully automated CD pipeline that has not yet been implemented.

---

# Infrastructure Destruction

The Azure environment is temporary and can be removed when it is no longer needed.

From the Terraform directory:

```bash
terraform destroy
```

Terraform displays a destruction plan before removing the managed resources.

The lifecycle becomes:

```text
terraform apply
      │
      ▼
Azure VM
      │
      ▼
Ansible
      │
      ▼
PawPal
      │
      ▼
Testing complete
      │
      ▼
terraform destroy
      │
      ▼
Azure resources removed
```

The Terraform and Ansible code remains in GitHub, allowing the environment to be recreated later.

---

# Recreating the Environment

Because the infrastructure and configuration are stored as code, rebuilding follows the same process:

```text
Clone repository
      │
      ▼
Terraform
      │
      ▼
Create Azure infrastructure
      │
      ▼
Connect VM to Tailscale
      │
      ▼
Update Ansible inventory
      │
      ▼
Run Ansible
      │
      ▼
Pull Docker image
      │
      ▼
Run PawPal
```

This is significantly more reproducible than manually configuring a VM through the Azure Portal and SSH.

---

# Future Improvements

Potential deployment improvements include:

- Fully automate deployment through GitHub Actions
- Authenticate GitHub Actions to Azure using OIDC
- Automate Tailscale registration
- Avoid hard-coding the Tailscale IP in the Ansible inventory
- Use Tailscale MagicDNS for host discovery
- Automatically run Ansible after Terraform completes
- Add application health checks
- Add Docker image vulnerability scanning
- Add deployment rollback
- Add versioned Docker image tags instead of relying only on `latest`
- Add development and production environments
- Add HTTPS through a reverse proxy
- Store secrets in Azure Key Vault or another secrets manager
- Add Prometheus and Grafana monitoring
- Add centralised application logging

---

# Key Concepts Demonstrated

The deployment process demonstrates practical experience with:

- Infrastructure provisioning
- Configuration management
- Docker deployment
- Container registries
- GitHub Container Registry
- Azure Linux VMs
- SSH key authentication
- Tailscale networking
- Ansible inventories
- Ansible playbooks
- Ansible privilege escalation
- Ansible idempotency
- Linux package management
- Docker service management
- Application verification
- Deployment troubleshooting
- Infrastructure teardown
- Reproducible environments
