variable "proxmox_url" {
  description = "Proxmox VE API endpoint (e.g., https://proxmox.example.com:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE API token in format user@realm!tokenid=tokensecret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Ignore SSL certificate verification (not recommended for production)"
  type        = bool
  default     = false
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host"
  type        = string
  default     = "root"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
