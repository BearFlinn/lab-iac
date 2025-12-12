module "compute" {
  source = "../../modules/compute"

  template_name        = var.template_name
  cloudinit_storage    = var.cloudinit_storage
  ssh_private_key_path = var.ssh_private_key_path

  vms = var.vms
}
