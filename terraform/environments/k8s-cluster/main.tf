terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.50.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure = var.proxmox_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}

module "compute" {
  source = "../../modules/compute"

  template_name        = var.template_name
  cloudinit_storage    = var.cloudinit_storage
  ssh_private_key_path = var.ssh_private_key_path
  ssh_public_key       = var.ssh_public_key
  vm_password          = var.vm_password

  vms = var.vms
}
