variable "proxmox_url" {
  description = "Proxmox VE API endpoint (e.g., https://proxmox.example.com:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE API token in format user@realm!tokenid=tokensecret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Ignore SSL certificate verification (not recommended for production)"
  type        = bool
  default     = false
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host"
  type        = string
  default     = "root"
}

variable "template_name" {
  description = "VM ID of the Proxmox VM template to clone"
  type        = number
  default     = 9000  # debian-base template VM ID
}

variable "cloudinit_storage" {
  description = "Storage ID for cloud-init CDROM"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_password" {
  description = "Password for the VM user account"
  type        = string
  sensitive   = true
}

variable "vms" {
  description = "Kubernetes cluster VMs to create"
  type = map(object({
    name       = string
    node       = string
    vmid       = number
    cores      = number
    sockets    = number
    memory     = number
    networks = list(object({
      model  = optional(string, "virtio")
      bridge = string
      mtu    = optional(number, 1500)
    }))
    disks = list(object({
      slot     = number
      size     = number
      storage  = string
      discard  = optional(string, "on")
      iothread = optional(bool, false)
    }))
  }))
}
