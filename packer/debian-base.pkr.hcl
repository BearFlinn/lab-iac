packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "debian_version" {
  type    = string
  default = "13.2.0"
}

variable "debian_codename" {
  type    = string
  default = "trixie"
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:677c4d57aa034dc192b5191870141057574c1b05df2b9569c0ee08aa4e32125d"
}

variable "vm_name" {
  type    = string
  default = "debian-base"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "ssh_username" {
  type    = string
  default = "debian"
}

variable "ssh_password" {
  type    = string
  default = "debian"
  sensitive = true
}

source "qemu" "debian" {
  vm_name          = var.vm_name
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = "output-${var.vm_name}"

  disk_size        = var.disk_size
  format           = "qcow2"
  accelerator      = "kvm"

  memory           = var.memory
  cpus             = var.cpus

  http_directory   = "http"

  boot_wait        = "5s"
  boot_command     = [
    "<esc><wait>",
    "auto <wait>",
    "console-setup/ask_detect=false <wait>",
    "console-setup/layoutcode=us <wait>",
    "console-setup/modelcode=pc105 <wait>",
    "debconf/frontend=noninteractive <wait>",
    "debian-installer=en_US.UTF-8 <wait>",
    "fb=false <wait>",
    "kbd-chooser/method=us <wait>",
    "keyboard-configuration/layout=USA <wait>",
    "keyboard-configuration/variant=USA <wait>",
    "locale=en_US.UTF-8 <wait>",
    "netcfg/get_domain=local <wait>",
    "netcfg/get_hostname=${var.vm_name} <wait>",
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "<enter><wait>"
  ]

  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "30m"

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  headless         = true
  vnc_bind_address = "0.0.0.0"
}

build {
  sources = ["source.qemu.debian"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }

  provisioner "shell" {
    inline = [
      "# Install essential packages",
      "sudo apt-get install -y curl wget vim git sudo qemu-guest-agent",
      "sudo apt-get install -y cloud-init cloud-utils cloud-guest-utils",
      "sudo systemctl enable qemu-guest-agent"
    ]
  }

  provisioner "shell" {
    inline = [
      "# Clean up",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",

      "# Clear logs",
      "sudo find /var/log -type f -delete",

      "# Clear bash history",
      "history -c",
      "cat /dev/null > ~/.bash_history"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
