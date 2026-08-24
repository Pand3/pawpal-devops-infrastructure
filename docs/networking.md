# PawPal Networking

## Overview

The PawPal deployment uses **Azure networking** for the cloud infrastructure and **Tailscale** for private administrative access.

The networking design has two main goals:

1. Provide the Azure VM with the networking required to run PawPal.
2. Avoid exposing SSH directly to the public internet.

The main Azure networking components are:

- Virtual Network (VNet)
- Subnet
- Network Interface (NIC)
- Public IP
- Network Security Group (NSG)

Tailscale provides an additional private network between the administrator's machine and the Azure VM.

---

## Network Architecture

```text
                         Microsoft Azure
                              │
                    ┌─────────┴─────────┐
                    │   Resource Group  │
                    └─────────┬─────────┘
                              │
                         pawpal-vnet
                              │
                         pawpal-subnet
                              │
                          pawpal-nic
                              │
                         ┌────┴────┐
                         │   NSG   │
                         └────┬────┘
                              │
                         pawpal-vm
                         /        \
                        /          \
               Azure Public IP   Tailscale IP
                                      │
                                      │ Private tailnet
                                      ▼
                              Developer machine
```

The Azure networking layer provides the VM's cloud connectivity, while Tailscale provides the preferred management path.

---

# Azure Virtual Network

The Azure Virtual Network provides the private network used by the PawPal infrastructure.

The VNet created for the project is:

```text
pawpal-vnet
```

During the project, it used the address space:

```text
10.0.0.0/16
```

This gives Azure a private address range from which subnets can be created.

```text
pawpal-vnet
10.0.0.0/16
      │
      ▼
pawpal-subnet
      │
      ▼
pawpal-vm
```

The VNet is not the same as Tailscale. It is the private network used internally by Azure resources.

---

# Subnet

A subnet divides the VNet address space into a smaller network segment.

The PawPal VM's network interface is attached to the subnet.

```text
VNet
 │
 ▼
Subnet
 │
 ▼
NIC
 │
 ▼
VM
```

This relationship is defined through Terraform so the network can be recreated consistently.

---

# Network Interface

The Azure Network Interface connects `pawpal-vm` to the Azure subnet.

The NIC used by the project is:

```text
pawpal-nic
```

Conceptually:

```text
pawpal-subnet
      │
      ▼
  pawpal-nic
      │
      ▼
  pawpal-vm
```

The NIC also provides the point at which the Network Security Group is associated with the VM's networking.

---

# Network Security Group

The Network Security Group acts as an Azure network traffic filter.

The project uses:

```text
pawpal-nsg
```

The NSG is associated with the VM's network interface.

```text
Internet
   │
   ▼
Public IP
   │
   ▼
Network Security Group
   │
   ▼
Network Interface
   │
   ▼
Azure VM
```

The NSG determines which inbound connections are allowed to reach the VM through Azure networking.

---

# Initial SSH Access

During the initial deployment, an inbound rule was created to allow SSH:

```text
Name:             allow-ssh
Priority:         100
Direction:        Inbound
Access:           Allow
Protocol:         TCP
Destination Port: 22
Source:           *
```

This produced the following path:

```text
Developer
    │
    │ Internet
    ▼
Azure Public IP
    │
    │ TCP 22
    ▼
Azure NSG
    │
    ▼
pawpal-vm
```

This was useful for the initial connection to the VM, but allowing SSH from any public source was not the desired final configuration.

---

# Tailscale

Tailscale was installed on the Azure VM to provide private connectivity.

Once the VM joined the same tailnet as the developer machine, it received a Tailscale address in the `100.x.x.x` range.

For example:

```text
Developer laptop
Tailscale
    │
    │ Encrypted private network
    ▼
100.x.x.x
    │
    ▼
pawpal-vm
```

The VM's Tailscale IPv4 address can be checked on the VM with:

```bash
tailscale ip -4
```

The devices connected to the tailnet can also be viewed with:

```bash
tailscale status
```

---

# SSH Through Tailscale

After Tailscale was configured, SSH could use the Tailscale address instead of the Azure public IP.

Example:

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@100.x.x.x
```

The connection path becomes:

```text
Developer laptop
       │
       │ Tailscale
       ▼
Private tailnet
       │
       ▼
Azure VM
       │
       └── SSH
```

This removes the requirement for SSH to be reachable from the public internet.

---

# Removing Public SSH

After confirming that Tailscale SSH worked correctly, the Azure NSG's public `allow-ssh` rule was removed.

The result was tested by attempting to SSH to the Azure public IP.

The public connection timed out, while the Tailscale connection continued to work.

```text
Azure Public IP
      │
      │ TCP 22
      ▼
     NSG
      │
      ✕
   BLOCKED
```

while:

```text
Developer laptop
      │
      │ Tailscale
      ▼
100.x.x.x
      │
      ▼
Azure VM
      │
      ✓
     SSH
```

This verified that administration could only be performed through the private Tailscale path.

---

# Public IP

The Azure VM also had an Azure public IP resource.

The public IP could be retrieved with:

```bash
az vm show -d \
  --resource-group pawpal-devops-rg \
  --name pawpal-vm \
  --query publicIps \
  -o tsv
```

The existence of a public IP does not automatically mean every service on the VM is publicly accessible.

The NSG controls which inbound traffic Azure permits.

For example:

```text
Public IP exists
      │
      ▼
NSG evaluates traffic
      │
      ├── Allowed rule → traffic can continue
      │
      └── No allowed rule → traffic blocked
```

This distinction was important when testing the final SSH configuration.

---

# PawPal Application Access

The PawPal Docker container runs on port:

```text
3000
```

The Docker configuration maps the VM's port `3000` to the container's port `3000`:

```text
3000:3000
```

Conceptually:

```text
Azure VM :3000
      │
      ▼
Docker
      │
      ▼
PawPal container :3000
```

Because Tailscale provides direct private connectivity to the VM, PawPal can be accessed through the VM's Tailscale address:

```text
http://100.x.x.x:3000
```

This allows the application to be tested without intentionally exposing application port `3000` to the public internet through an Azure NSG rule.

---

# Ansible Networking

Ansible also uses the Tailscale network to connect to the VM.

The inventory contains the VM's Tailscale address:

```ini
[server]
pawpal ansible_host=100.x.x.x ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/pawpal_azure
```

The private SSH key itself is **not** stored in the repository.

The connection path is:

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

Connectivity can be tested with:

```bash
ansible all -i azure-inventory.ini -m ping
```

A successful connection returns:

```text
pawpal | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

This confirms that Ansible can manage the VM without public SSH access.

---

# Azure Networking Verification

The Azure CLI was useful for checking networking resources independently of Terraform.

## Check the VNet

```bash
az network vnet show \
  --resource-group pawpal-devops-rg \
  --name pawpal-vnet \
  -o table
```

## Check the NSG

```bash
az network nsg show \
  --resource-group pawpal-devops-rg \
  --name pawpal-nsg \
  -o table
```

## List NSG Rules

```bash
az network nsg rule list \
  --resource-group pawpal-devops-rg \
  --nsg-name pawpal-nsg \
  -o table
```

This command was particularly useful for verifying whether the public SSH rule still existed.

## Retrieve the VM Public IP

```bash
az vm show -d \
  --resource-group pawpal-devops-rg \
  --name pawpal-vm \
  --query publicIps \
  -o tsv
```

---

# Testing Public and Private Connectivity

The final networking configuration was verified from the developer machine.

## Public SSH Test

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<AZURE_PUBLIC_IP>
```

With the public SSH NSG rule removed, this connection should fail or time out.

## Tailscale SSH Test

```bash
ssh -i ~/.ssh/pawpal_azure azureuser@<TAILSCALE_IP>
```

This connection should succeed.

Together these tests demonstrate:

```text
Public SSH       → blocked
Tailscale SSH    → allowed
```

---

# Azure Network vs Tailscale Network

The project uses two different private networking concepts.

## Azure VNet

The Azure VNet exists inside Azure and provides networking between Azure resources.

```text
Azure Resource
      │
      ▼
Azure VNet
```

## Tailscale

Tailscale creates an encrypted overlay network between authorised devices.

```text
Developer laptop
      │
      ├──────── Tailscale ────────┐
      │                           │
      ▼                           ▼
Local device                  Azure VM
```

The Tailscale address is independent of the VM's Azure private IP.

This means the VM can be reached through the tailnet even though public SSH access is blocked.

---

# Network Traffic Summary

| Traffic | Method | Result |
|---|---|---|
| SSH through Azure public IP | TCP 22 | Blocked |
| SSH through Tailscale | Private tailnet | Allowed |
| Ansible management | Tailscale + SSH | Allowed |
| PawPal access | Tailscale + port 3000 | Allowed |
| Azure internal networking | VNet/Subnet | Available |

---

# Security Benefits

The networking design provides several benefits.

### Reduced SSH exposure

Port `22` does not need to be exposed to arbitrary public internet addresses.

### Private management network

Tailscale provides a dedicated private path for administration.

### Encrypted connectivity

Tailscale connections are encrypted between authorised devices.

### Separation of cloud and management networking

Azure networking handles the VM's cloud connectivity, while Tailscale handles private administrative access.

### Infrastructure as Code

Azure networking resources are defined through Terraform rather than depending entirely on manual Azure Portal configuration.

---

# Troubleshooting Lessons

## NSG Was Not Initially Associated With the NIC

An NSG can exist in Azure without actually filtering traffic for a VM.

The NSG therefore had to be associated with the VM's network interface.

The Terraform relationship is conceptually:

```text
pawpal-nsg
     │
     ▼
NSG/NIC association
     │
     ▼
pawpal-nic
     │
     ▼
pawpal-vm
```

This demonstrated that creating an NSG alone is not sufficient; it must be associated with the appropriate subnet or network interface.

## Public SSH Rule Remained in Azure

During the project, the `allow-ssh` rule remained visible in Azure even after changes were made to the Terraform configuration/state.

The rule was inspected with:

```bash
az network nsg rule list \
  --resource-group pawpal-devops-rg \
  --nsg-name pawpal-nsg \
  -o table
```

The final configuration was verified by testing both the public IP and Tailscale IP rather than assuming the firewall behaviour from configuration alone.

## Tailscale Address in Ansible Inventory

The Ansible inventory references the VM's Tailscale IP.

If the VM is destroyed and recreated, the new Tailscale node may have a different address.

The inventory therefore needs to be updated after a fresh deployment unless a more automated discovery method is introduced.

---

# Future Improvements

Potential networking improvements include:

- Remove the Azure public IP entirely if it is no longer required
- Use Tailscale DNS/MagicDNS instead of a hard-coded Tailscale IP
- Automate Tailscale installation and registration
- Automate Ansible inventory generation
- Introduce Tailscale ACLs or grants with least-privilege access
- Add HTTPS for application traffic
- Add an Nginx reverse proxy
- Add separate development and production networks
- Add Azure Network Watcher diagnostics
- Add monitoring and alerts for network connectivity
- Review outbound access requirements
- Use private cloud services where appropriate

---

# Key Concepts Demonstrated

The networking portion of PawPal demonstrates practical experience with:

- Azure Virtual Networks
- Azure subnets
- Azure Network Interfaces
- Azure Network Security Groups
- Public and private IP addressing
- Firewall rules
- NSG associations
- SSH networking
- Tailscale
- Private overlay networks
- Docker port mappings
- Ansible over SSH
- Azure CLI network troubleshooting
- Public exposure reduction
- Network connectivity testing
