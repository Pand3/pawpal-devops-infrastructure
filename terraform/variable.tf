variable "ssh_public_key" {
  description = "SSH public key used to access the Azure VM"
  type        = string
  sensitive   = true
}
