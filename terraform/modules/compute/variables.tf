variable "template_name" {
  description = "Name of the Proxmox VM template to clone from"
  type        = string
}

variable "cloudinit_storage" {
  description = "Storage ID for cloud-init CDROM (e.g., local-lvm)"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for VM provisioning"
  type        = string
}

variable "vms" {
  description = "Map of VMs to create"
  type = map(object({
    name       = string
    node       = string
    vmid       = number
    full_clone = optional(bool, true)
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
      size     = string
      type     = optional(string, "virtio")
      storage  = string
      discard  = optional(string, "on")
      iothread = optional(number, 0)
    }))
  }))
}
