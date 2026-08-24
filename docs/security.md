# PawPal Security

## Overview

Security for the PawPal deployment focuses on reducing unnecessary public exposure, protecting administrative access, and keeping credentials outside the Git repository.

The main security controls used in the project are:

- Azure Network Security Groups
- Tailscale private networking
- SSH key authentication
- Restricted public SSH access
- Git-ignored secrets and Terraform state
- Separation of infrastructure and configuration responsibilities
- Disposable Azure infrastructure

The final design avoids relying on publicly exposed SSH for normal administration.

---

## Security Architecture

```text
                         Public Internet
                               │
                               │ SSH :22
                               ▼
                       Azure Public IP
                               │
                               ▼
                       Azure NSG
                               │
                               ✕
                         SSH BLOCKED


Developer Laptop
      │
      │ Encrypted Tailscale connection
      ▼
Tailscale Network
      │
      ▼
Azure VM
      │
      ├── SSH
      │
      ├── Ansible
      │
      └── Docker
           │
           ▼
         PawPal
```

The Azure public IP can exist without making SSH publicly accessible because the Network Security Group controls which inbound connections are allowed.

---

# Network Security Group

Azure Network Security Groups are used to control traffic reaching the VM.

During the initial setup, an inbound SSH rule was temporarily used:

```text
Name:             allow-ssh
Priority:         100
Direction:        Inbound
Access:           Allow
Protocol:         TCP
Destination Port: 22
Source:           *
```

This allowed the VM to be reached through its Azure public IP while the initial server configuration was being completed.

However, allowing:

```text
Source: *
Port:   22
```

means SSH connection attempts can originate from anywhere on the internet.

This was not retained as the intended final configuration.

---

# Removing Public SSH Access

After Tailscale was installed and tested, public SSH access was removed from the Azure NSG.

The final intended behaviour became:

```text
Azure Public IP → TCP 22 → BLOCKED
Tailscale IP    → SSH    → ALLOWED
```

The configuration was verified by testing both connection methods.

## Public Test

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<AZURE_PUBLIC_IP>
```

The connection failed or timed out after the public SSH rule was removed.

## Private Test

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<TAILSCALE_IP>
```

The Tailscale connection continued to work.

This provided practical verification that SSH was no longer available through the public Azure path.

---

# Tailscale

Tailscale provides the private management network used by the project.

Both the administrator's machine and the Azure VM join the same tailnet.

```text
Developer Laptop
       │
       │ Tailscale
       ▼
Encrypted Tailnet
       │
       ▼
Azure VM
```

The VM receives a Tailscale address in the `100.x.x.x` range.

The address can be checked with:

```bash
tailscale ip -4
```

Connected Tailscale devices can be inspected with:

```bash
tailscale status
```

---

## Why Tailscale Is Used

Without Tailscale, remote SSH administration would typically require a path such as:

```text
Developer
    │
    ▼
Public Internet
    │
    ▼
Azure Public IP
    │
    ▼
Open SSH port
    │
    ▼
Azure VM
```

With Tailscale:

```text
Developer
    │
    ▼
Private Tailscale Network
    │
    ▼
Azure VM
```

This reduces the need to expose administrative services directly through Azure's public interface.

---

# SSH Authentication

The VM uses SSH key authentication.

The private key remains on the developer's machine.

Example:

```text
~/.ssh/pawpal_azure
```

An SSH connection through Tailscale uses:

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<TAILSCALE_IP>
```

The private key is not copied into the Git repository.

---

## Private Key vs Public Key

SSH authentication uses a key pair:

```text
Private key
    │
    │ kept secret
    ▼
Developer machine


Public key
    │
    │ installed on
    ▼
Azure VM
```

The private key proves the identity of the connecting client.

The public key can be installed on the VM without exposing the private key.

The private key must never be committed to GitHub.

---

# Ansible Security

Ansible connects to the VM over SSH through Tailscale.

Example inventory:

```ini
[server]
pawpal ansible_host=100.x.x.x ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/pawpal_azure
```

This inventory contains:

- A Tailscale IP
- A Linux username
- A local filesystem path to the SSH key

It does **not** contain the contents of the private SSH key.

The actual key remains outside the repository.

The connection path is:

```text
Ansible
   │
   │ SSH key
   ▼
Tailscale
   │
   ▼
Azure VM
```

---

# Privilege Escalation

Some Ansible tasks require administrative privileges.

For example:

- Updating APT
- Installing Docker
- Creating files under `/etc`
- Managing system services

The playbook uses:

```yaml
become: true
```

The playbook was run with:

```bash
ansible-playbook   -i azure-inventory.ini   azure-playbook.yml   --ask-become-pass
```

Using `--ask-become-pass` means the privilege escalation password is entered interactively rather than written directly into the playbook.

This prevents the password from being stored in the repository.

---

# Docker Security Considerations

Docker is installed and managed by Ansible.

The PawPal application runs inside a container rather than being installed directly into the host operating system.

```text
Azure VM
   │
   ▼
Docker Engine
   │
   ▼
PawPal Container
```

Containerisation provides application isolation and makes the runtime environment reproducible.

However, Docker containers should not be treated as a complete security boundary by themselves.

Security still depends on:

- Host security
- Container configuration
- Network exposure
- Image security
- Secrets management
- Keeping software updated

---

# Docker Socket Permissions

During deployment, running:

```bash
docker ps
```

initially returned:

```text
permission denied while trying to connect to the docker API
```

This occurs because access to the Docker daemon is restricted.

Users granted access to the Docker socket effectively gain significant control over the host through Docker.

For this reason, membership of the `docker` group should only be granted to trusted users.

---

# Application Network Exposure

PawPal runs on port:

```text
3000
```

The Docker container uses a port mapping equivalent to:

```text
3000:3000
```

This means Docker binds the application to the VM's network interfaces.

However, Azure's NSG provides an additional network-control layer.

No public NSG rule was intentionally added for PawPal port `3000`.

The application can instead be accessed through Tailscale:

```text
http://<TAILSCALE_IP>:3000
```

The intended access path is therefore:

```text
Trusted Device
     │
     │ Tailscale
     ▼
Azure VM :3000
     │
     ▼
Docker
     │
     ▼
PawPal
```

---

# Secrets and Git

Sensitive files should never be committed to the repository.

The `.gitignore` protects files such as:

```gitignore
# Environment files
.env
.env.*
!.env.example

# Terraform
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.*
terraform/*.tfvars
terraform/*.tfvars.json
terraform/*.tfplan

# SSH / credentials
*.pem
*.key
*.p12
*.pfx
id_rsa
id_rsa.pub

# Ansible
ansible/*.retry
ansible/.vault_password
ansible/*.vault
```

Project-specific private SSH keys should also remain outside the repository.

---

# Terraform State Security

Terraform state is deliberately excluded from Git.

State files may contain:

- Azure resource IDs
- IP addresses
- Infrastructure metadata
- Configuration values
- Potentially sensitive values depending on the resources being managed

Therefore:

```text
terraform.tfstate
terraform.tfstate.*
```

should not be pushed to a public repository.

The Terraform configuration files themselves should be committed because they document how the infrastructure is built.

---

# Environment Variables

Application secrets should be provided through environment variables rather than hard-coded into application source code or infrastructure files.

For example:

```text
.env
```

should remain local and be ignored by Git.

A safe example file can be committed:

```text
.env.example
```

but it should contain placeholder values rather than real credentials.

For example:

```env
JWT_SECRET=replace_me
DATABASE_URL=replace_me
```

---

# Azure Credentials

Azure CLI authentication used during development should not be exported into the repository.

Credentials such as:

- Azure client secrets
- Access tokens
- Subscription credentials
- Service principal passwords

must not be placed directly into Terraform configuration or GitHub workflow files.

The project explored using GitHub Actions with Azure OIDC authentication.

OIDC would allow GitHub Actions to receive short-lived Azure credentials rather than storing a permanent Azure client secret.

Full Azure OIDC automation was not completed because the Microsoft Entra tenant did not permit the current account to create the required application registration.

This is documented as a future improvement rather than pretending the deployment is fully automated.

---

# GitHub Actions Secrets

If deployment automation is expanded in the future, sensitive values should be stored using GitHub Actions secrets or an external secrets-management system.

A workflow should reference a secret:

```yaml
${{ secrets.SECRET_NAME }}
```

rather than containing the secret directly:

```yaml
password: actual-password
```

Secrets should still be granted the minimum permissions required.

---

# Principle of Least Privilege

A general security goal of the project is to avoid granting more access than required.

Examples include:

- Public SSH is removed after private connectivity is available.
- SSH uses key authentication.
- Private keys remain outside Git.
- Administrative passwords are entered interactively.
- Infrastructure configuration and secrets are kept separate.
- Azure network access is controlled through an NSG.
- Administrative traffic uses Tailscale.

Further improvements can reduce permissions even more.

---

# Infrastructure Destruction

The Azure infrastructure is not intended to run permanently when it is not being used.

Terraform allows the environment to be removed with:

```bash
terraform destroy
```

The lifecycle is:

```text
terraform apply
      │
      ▼
Temporary Azure environment
      │
      ▼
Testing / deployment
      │
      ▼
terraform destroy
      │
      ▼
Resources removed
```

Destroying unused infrastructure provides both cost and security benefits.

An unused internet-connected VM cannot become an unnecessary long-term attack surface if it no longer exists.

---

# Security Verification

Security controls should be tested rather than assumed.

Several checks were performed during the project.

## Verify NSG Rules

```bash
az network nsg rule list   --resource-group pawpal-devops-rg   --nsg-name pawpal-nsg   -o table
```

## Verify Public SSH Is Blocked

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<AZURE_PUBLIC_IP>
```

Expected result:

```text
Connection timeout / failure
```

## Verify Tailscale SSH Works

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<TAILSCALE_IP>
```

Expected result:

```text
Successful SSH connection
```

## Verify Ansible Connectivity

```bash
ansible all -i azure-inventory.ini -m ping
```

Expected result:

```text
pawpal | SUCCESS
```

These checks confirm the intended security model is actually functioning.

---

# Security Model Summary

```text
                     PUBLIC INTERNET
                           │
              ┌────────────┴────────────┐
              │                         │
          SSH :22                   Other traffic
              │                         │
              ▼                         ▼
        Azure Public IP             Azure NSG
              │
              ▼
            NSG
              │
              ✕
         SSH BLOCKED


                    PRIVATE ACCESS
                          │
                    Tailscale
                          │
               ┌──────────┴──────────┐
               │                     │
              SSH                PawPal :3000
               │                     │
               ▼                     ▼
           Azure VM              Docker
                                     │
                                     ▼
                                   PawPal
```

---

# Current Limitations

This project demonstrates security-conscious infrastructure, but it should not be considered a complete production security architecture.

Current limitations include:

- The VM still uses an Azure public IP.
- PawPal does not currently use a production HTTPS setup.
- Tailscale access control can be tightened further.
- Secrets are not managed through a dedicated cloud secrets manager.
- Terraform state is local rather than stored in a secured remote backend.
- GitHub Actions deployment to Azure is not fully automated with OIDC.
- Automated vulnerability and container image scanning can be added.
- Automated patch management is not implemented.

These are appropriate areas for future development.

---

# Future Improvements

Potential security improvements include:

- Remove the Azure public IP entirely
- Use Tailscale MagicDNS instead of hard-coded IP addresses
- Configure least-privilege Tailscale ACLs or grants
- Use Azure Key Vault for application secrets
- Store Terraform state in a secured Azure Storage backend
- Use GitHub Actions OIDC for short-lived Azure authentication
- Add HTTPS using Nginx or another reverse proxy
- Add automated container vulnerability scanning
- Add dependency security scanning
- Add application health monitoring
- Add automated operating-system patching
- Use separate development and production environments
- Apply more restrictive Azure RBAC permissions
- Add audit logging and security alerts

---

# Key Security Concepts Demonstrated

The security portion of PawPal demonstrates practical experience with:

- Network Security Groups
- Firewall rules
- SSH key authentication
- Public vs private network access
- Tailscale private networking
- Reducing exposed services
- Secure Ansible administration
- Privilege escalation
- Git secret hygiene
- Terraform state protection
- Environment-variable based secrets
- Docker permissions
- Azure RBAC awareness
- Least privilege
- Security verification
- Disposable infrastructure
