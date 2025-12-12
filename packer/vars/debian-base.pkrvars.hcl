# Debian Base Image Variables
# Customize these values for your environment

debian_version = "13.2.0"
debian_codename = "trixie"

# VM Configuration
vm_name   = "debian-base"
disk_size = "20G"
memory    = "2048"
cpus      = "2"

# SSH Credentials (change for production!)
ssh_username = "debian"
ssh_password = "<REDACTED>"

# You can override the ISO URL and checksum if needed
# iso_url = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
# iso_checksum = "sha256:677c4d57aa034dc192b5191870141057574c1b05df2b9569c0ee08aa4e32125d"
