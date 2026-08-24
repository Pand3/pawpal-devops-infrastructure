terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = "a41caf5a-21c0-4133-821d-4b059b193a6c"
  resource_provider_registrations = "none"
}

resource "azurerm_resource_group" "pawpal" {
  name     = "pawpal-devops-rg"
  location = "Spain Central"
}

resource "azurerm_virtual_network" "pawpal" {
  name                = "pawpal-vnet"
  location            = azurerm_resource_group.pawpal.location
  resource_group_name = azurerm_resource_group.pawpal.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "pawpal" {
  name                 = "pawpal-subnet"
  resource_group_name  = azurerm_resource_group.pawpal.name
  virtual_network_name = azurerm_virtual_network.pawpal.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pawpal" {
  name                = "pawpal-public-ip"
  location            = azurerm_resource_group.pawpal.location
  resource_group_name = azurerm_resource_group.pawpal.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "pawpal" {
  name                = "pawpal-nsg"
  location            = azurerm_resource_group.pawpal.location
  resource_group_name = azurerm_resource_group.pawpal.name
}

resource "azurerm_network_interface_security_group_association" "pawpal" {
  network_interface_id      = azurerm_network_interface.pawpal.id
  network_security_group_id = azurerm_network_security_group.pawpal.id
}

resource "azurerm_network_interface" "pawpal" {
  name                = "pawpal-nic"
  location            = azurerm_resource_group.pawpal.location
  resource_group_name = azurerm_resource_group.pawpal.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.pawpal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pawpal.id
  }
}

resource "azurerm_linux_virtual_machine" "pawpal" {
  name                = "pawpal-vm"
  resource_group_name = azurerm_resource_group.pawpal.name
  location            = azurerm_resource_group.pawpal.location
  size                = "Standard_B2ts_v2"

  admin_username = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.pawpal.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
