output "vms" {
  description = "Created Kubernetes cluster VMs"
  value       = module.compute.vms
}

output "control_plane_ips" {
  description = "Control plane node IP addresses"
  value = {
    for key, vm in module.compute.vms : key => vm.ip_addresses
    if can(regex("^k8s-control-.*", key))
  }
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value = {
    for key, vm in module.compute.vms : key => vm.ip_addresses
    if can(regex("^k8s-worker-.*", key))
  }
}

output "ansible_inventory" {
  description = "Ansible inventory in JSON format for dynamic inventory"
  value = jsonencode({
    all = {
      children = {
        k8s_cluster = {
          children = {
            k8s_control_plane = {
              hosts = {
                for key, vm in module.compute.vms :
                key => {
                  ansible_host = length(vm.ip_addresses) > 0 ? vm.ip_addresses[0] : ""
                }
                if can(regex("^k8s-control-.*", key)) && length(vm.ip_addresses) > 0
              }
            }
            k8s_workers = {
              hosts = {
                for key, vm in module.compute.vms :
                key => {
                  ansible_host = length(vm.ip_addresses) > 0 ? vm.ip_addresses[0] : ""
                }
                if can(regex("^k8s-worker-.*", key)) && length(vm.ip_addresses) > 0
              }
            }
          }
          vars = {
            ansible_user                 = "debian"
            ansible_ssh_private_key_file = "~/.ssh/id_ed25519"
            ansible_python_interpreter   = "/usr/bin/python3"
            kubernetes_version           = "1.28"
            kubernetes_cni               = "calico"
            calico_version              = "v3.26.1"
            pod_network_cidr            = "192.168.0.0/16"
          }
        }
      }
    }
  })
}
