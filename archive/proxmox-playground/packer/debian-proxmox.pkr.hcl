packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox API username (format: user@realm!tokenid)"
}

variable "proxmox_token_secret" {
  type        = string
  description = "Proxmox API token secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to build on"
  default     = "proxmox1"
}

variable "proxmox_insecure_skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification"
  default     = false
}

variable "debian_version" {
  type    = string
  default = "13.2.0"
}

variable "iso_file" {
  type        = string
  description = "ISO file on Proxmox storage (e.g., local:iso/debian-13.2.0-amd64-netinst.iso)"
}

variable "iso_storage_pool" {
  type        = string
  description = "Storage pool where ISO is located"
  default     = "local"
}

variable "vm_id" {
  type        = number
  description = "VM ID for the template"
  default     = 9000
}

variable "vm_name" {
  type    = string
  default = "debian-base"
}

variable "template_description" {
  type    = string
  default = "Debian 13 base template with cloud-init"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "disk_storage_pool" {
  type        = string
  description = "Storage pool for VM disk"
  default     = "local-lvm"
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cores" {
  type    = number
  default = 2
}

variable "cpu_type" {
  type    = string
  default = "host"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "ssh_username" {
  type    = string
  default = "debian"
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

source "proxmox-iso" "debian-base" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = var.proxmox_insecure_skip_tls_verify
  node                     = var.proxmox_node

  # VM configuration
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.template_description

  # ISO
  boot_iso {
    iso_file         = var.iso_file
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # System
  qemu_agent = true
  scsi_controller = "virtio-scsi-single"

  # CPU and Memory
  cores    = var.cores
  cpu_type = var.cpu_type
  memory   = var.memory

  # Disks
  disks {
    disk_size         = var.disk_size
    storage_pool      = var.disk_storage_pool
    type              = "scsi"
    discard           = true
    ssd               = true
    io_thread         = true
  }

  # Network
  network_adapters {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
  }

  # Cloud-init
  cloud_init              = true
  cloud_init_storage_pool = var.disk_storage_pool

  # Boot configuration
  boot_wait = "10s"
  boot_command = [
    "<wait><esc><wait>",
    "install <wait>",
    "vga=788 <wait>",
    "auto=true <wait>",
    "url=http://10.0.0.151:8100/preseed.cfg <wait>",
    "hostname=${var.vm_name} <wait>",
    "domain=local <wait>",
    "locale=en_US.UTF-8 <wait>",
    "keymap=us <wait>",
    "debconf/frontend=text <wait>",
    "<enter><wait>"
  ]

  # HTTP server for preseed
  http_directory = "http"
  http_port_min  = 8100
  http_port_max  = 8100

  # SSH
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"

  # Convert to template after build
  onboot = false
}

build {
  sources = ["source.proxmox-iso.debian-base"]

  # Wait for system to be ready
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to be ready...'",
      "sudo apt-get update",
    ]
  }

  # Install essential packages
  provisioner "shell" {
    inline = [
      "echo 'Installing essential packages...'",
      "sudo apt-get install -y qemu-guest-agent",
      "sudo apt-get install -y cloud-init cloud-utils cloud-guest-utils",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent"
    ]
  }

  # Configure cloud-init
  provisioner "shell" {
    inline = [
      "echo 'Configuring cloud-init...'",
      "sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg > /dev/null <<EOF",
      "datasource_list: [NoCloud, ConfigDrive]",
      "EOF"
    ]
  }

  # Clean up
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo cloud-init clean",
      "sudo sync"
    ]
  }
}
