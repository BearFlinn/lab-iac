terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.50.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "debian_vm" {
  for_each = var.vms

  name        = each.value.name
  node_name   = each.value.node
  vm_id       = each.value.vmid

  clone {
    vm_id = var.template_name
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  # Network configuration
  dynamic "network_device" {
    for_each = each.value.networks
    content {
      model  = network_device.value.model
      bridge = network_device.value.bridge
      mtu    = lookup(network_device.value, "mtu", 1500)
    }
  }

  # Disk configuration
  dynamic "disk" {
    for_each = each.value.disks
    content {
      datastore_id = disk.value.storage
      interface    = "scsi${disk.value.slot}"
      size         = disk.value.size
      discard      = lookup(disk.value, "discard", "on")
      iothread     = lookup(disk.value, "iothread", 0)
    }
  }

  # Cloud-init configuration
  initialization {
    datastore_id = var.cloudinit_storage

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = var.vm_password
      username = "debian"
    }
  }

  lifecycle {
    ignore_changes = [
      disk,
      network_device,
    ]
  }

  provisioner "remote-exec" {
    inline = ["echo 'VM is ready'"]

    connection {
      type        = "ssh"
      user        = "debian"
      private_key = file(var.ssh_private_key_path)
      host        = self.ipv4_addresses[0][0]
      timeout     = "2m"
    }
  }
}
