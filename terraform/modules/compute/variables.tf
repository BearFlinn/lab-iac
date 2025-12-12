variable "template_name" {
  description = "VM ID of the Proxmox VM template to clone from"
  type        = number
}

variable "cloudinit_storage" {
  description = "Storage ID for cloud-init CDROM (e.g., local-lvm)"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for VM provisioning"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_password" {
  description = "Password for the VM user account"
  type        = string
}

variable "vms" {
  description = "Map of VMs to create"
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
