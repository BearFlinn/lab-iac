resource "proxmox_vm_qemu" "debian_vm" {
  for_each = var.vms

  name        = each.value.name
  target_node = each.value.node
  vmid        = each.value.vmid

  clone       = var.template_name
  full_clone  = each.value.full_clone

  cores   = each.value.cores
  sockets = each.value.sockets
  memory  = each.value.memory

  agent = 1

  # Network configuration
  dynamic "network" {
    for_each = each.value.networks
    content {
      model  = network.value.model
      bridge = network.value.bridge
      mtu    = lookup(network.value, "mtu", 1500)
    }
  }

  # Disk configuration
  dynamic "disk" {
    for_each = each.value.disks
    content {
      slot     = disk.value.slot
      size     = disk.value.size
      type     = disk.value.type
      storage  = disk.value.storage
      discard  = lookup(disk.value, "discard", "on")
      iothread = lookup(disk.value, "iothread", 0)
    }
  }

  # Cloud-init configuration
  cloudinit_cdrom_storage = var.cloudinit_storage

  lifecycle {
    ignore_changes = [
      disk,
      network,
    ]
  }

  provisioner "remote-exec" {
    inline = ["echo 'VM is ready'"]

    connection {
      type        = "ssh"
      user        = "debian"
      private_key = file(var.ssh_private_key_path)
      host        = self.default_ipv4_address
      timeout     = "2m"
    }
  }
}
