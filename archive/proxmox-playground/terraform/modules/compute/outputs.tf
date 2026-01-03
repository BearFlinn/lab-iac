output "vms" {
  description = "Created VM details"
  value = {
    for name, vm in proxmox_virtual_environment_vm.debian_vm : name => {
      vmid         = vm.vm_id
      name         = vm.name
      ip_addresses = flatten([for addr_list in vm.ipv4_addresses : [for addr in addr_list : addr if !startswith(addr, "127.")]])
    }
  }
}
