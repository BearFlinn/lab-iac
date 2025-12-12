# Proxmox Connection Settings
proxmox_url  = "https://10.0.0.176:8006/api2/json"
proxmox_node = "proxmox"
proxmox_username = "terraform@pve!terraform-token"
# proxmox_token_secret is set via environment variable PKR_VAR_proxmox_token_secret
proxmox_insecure_skip_tls_verify = true  # Only for self-signed certs in dev

# ISO Configuration
# You need to download the Debian ISO to Proxmox first
# Upload via Proxmox UI: Datacenter -> Storage -> local -> ISO Images -> Upload
iso_file         = "local:iso/debian-13.2.0-amd64-netinst.iso"
iso_storage_pool = "local"

# Template Configuration
vm_id                = 9000
vm_name              = "debian-base"
template_description = "Debian 13 base template with cloud-init"

# VM Resources
disk_size         = "20G"
disk_storage_pool = "local-lvm"
memory            = 2048
cores             = 2
cpu_type          = "host"

# Network
network_bridge = "vmbr0"

# SSH Credentials
ssh_username = "debian"
# ssh_password is set via environment variable PKR_VAR_ssh_password

# Debian Version
debian_version = "13.2.0"
