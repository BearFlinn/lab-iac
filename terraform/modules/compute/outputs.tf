output "vms" {
  description = "Created VM details"
  value = {
    for name, vm in proxmox_vm_qemu.debian_vm : name => {
      vmid     = vm.vmid
      name     = vm.name
      ip_addresses = vm.default_ipv4_address
    }
  }
}
