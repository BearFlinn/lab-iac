# Proxy VPS Setup Guide

This playbook sets up a secure VPS with Caddy web server, automatic SSL/TLS certificates, and proper firewall configuration.

## Overview

The setup includes:
- **Caddy Web Server**: Modern web server with automatic HTTPS
- **Let's Encrypt SSL/TLS**: Automatic certificate provisioning and renewal
- **UFW Firewall**: Configured for web services (HTTP/HTTPS)
- **Fail2ban**: SSH brute-force protection (from cloud-init)
- **Security Hardening**: Configured via cloud-init

## Prerequisites

### 1. VPS Provisioned with Cloud-Init

Your VPS should already be provisioned using `proxy-vps-1_cloud-init.yml`:
- ✅ User `bearf` created with sudo access
- ✅ SSH key authentication configured
- ✅ SSH running on port 2222
- ✅ Fail2ban enabled
- ✅ UFW firewall enabled (port 2222 allowed)

### 2. SSH Configuration

Ensure `proxy-vps` is configured in `~/.ssh/config`:

```
Host proxy-vps
    HostName <your-vps-ip>
    User bearf
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

Test connectivity:
```bash
ssh proxy-vps
```

### 3. Domain Configuration (Required for SSL)

For automatic SSL/TLS certificates:
1. **Register a domain** (e.g., example.com)
2. **Point DNS A record** to your VPS IP address
3. **Wait for DNS propagation** (can take up to 48 hours, usually much faster)

Verify DNS:
```bash
dig +short example.com
# Should return your VPS IP address
```

## Configuration

### 1. Update Inventory File

Edit `ansible/inventory/proxy-vps.yml`:

```yaml
all:
  hosts:
    proxy-vps-1:
      ansible_host: proxy-vps
      ansible_user: bearf
      ansible_port: 2222

      # IMPORTANT: Set your domain and email
      caddy_domain: "example.com"           # Your actual domain
      caddy_email: "admin@example.com"      # Email for Let's Encrypt

      enable_caddy: true
```

**Critical Configuration:**
- `caddy_domain`: Your actual domain name (must be DNS-resolvable)
- `caddy_email`: Valid email for Let's Encrypt notifications
- Leave as `localhost` only for testing (no SSL)

### 2. Optional Configuration

Additional settings in `proxy-vps.yml`:

```yaml
all:
  vars:
    timezone: "America/New_York"      # Your timezone
    enable_firewall: true              # Keep UFW enabled

    # Additional UFW rules (optional)
    ufw_web_rules:
      - { port: '8080', proto: 'tcp', comment: 'Custom App' }
```

## Running the Playbook

### Step 1: Verify Connectivity

```bash
cd /home/bearf/Projects/lab-iac

# Test SSH connection
ssh proxy-vps

# Test Ansible connectivity
ansible -i ansible/inventory/proxy-vps.yml all -m ping
```

### Step 2: Run the Setup

```bash
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml -v
```

The playbook will:
1. ✅ Update system packages
2. ✅ Install essential utilities
3. ✅ Configure UFW firewall (ports 2222, 80, 443)
4. ✅ Install Caddy web server
5. ✅ Configure automatic HTTPS
6. ✅ Deploy default landing page

### Step 3: Verify Deployment

After the playbook completes:

```bash
# Check HTTP (will redirect to HTTPS)
curl http://example.com

# Check HTTPS
curl https://example.com

# Verify SSL certificate
curl -vI https://example.com 2>&1 | grep -i "subject:\|issuer:"
```

## What Gets Installed

### Caddy Web Server

- **Installation**: Official Caddy APT repository
- **Configuration**: `/etc/caddy/Caddyfile`
- **Web Root**: `/var/www/html`
- **Logs**: `/var/log/caddy/`
- **Data**: `/var/lib/caddy/` (SSL certificates stored here)
- **User**: Runs as `caddy` user

### Firewall Rules

UFW is configured with:
- **Port 2222**: SSH (from cloud-init)
- **Port 80**: HTTP (redirects to HTTPS)
- **Port 443**: HTTPS
- **Default**: Deny incoming, allow outgoing

View current rules:
```bash
ssh proxy-vps
sudo ufw status verbose
```

### SSL/TLS Certificates

- **Provider**: Let's Encrypt (via Caddy)
- **Auto-renewal**: Handled automatically by Caddy
- **Storage**: `/var/lib/caddy/.local/share/caddy/certificates/`
- **Email notifications**: Sent to `caddy_email`

## Post-Deployment Tasks

### 1. Deploy Your Website

```bash
# SSH into VPS
ssh proxy-vps

# Upload your site files
sudo rsync -avz /local/path/to/site/ /var/www/html/

# Or clone from git
cd /var/www/html
sudo git clone https://github.com/user/repo.git .

# Fix permissions
sudo chown -R caddy:caddy /var/www/html
```

### 2. Customize Caddyfile

For reverse proxy, PHP, or other configurations:

```bash
ssh proxy-vps
sudo vim /etc/caddy/Caddyfile
```

Example reverse proxy configuration:
```
example.com {
    reverse_proxy localhost:8080
}
```

Validate and reload:
```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

### 3. Monitor Logs

```bash
# Access logs
ssh proxy-vps
sudo tail -f /var/log/caddy/access.log

# Caddy service logs
sudo journalctl -u caddy -f

# System logs
sudo tail -f /var/log/syslog
```

### 4. Check Service Status

```bash
ssh proxy-vps

# Caddy status
sudo systemctl status caddy

# UFW status
sudo ufw status verbose

# Fail2ban status
sudo systemctl status fail2ban
```

## Advanced Configuration

### Multiple Domains

Edit `/etc/caddy/Caddyfile`:

```
example.com {
    root * /var/www/example
    file_server
}

blog.example.com {
    root * /var/www/blog
    file_server
}
```

### Reverse Proxy

```
api.example.com {
    reverse_proxy localhost:3000
}
```

### PHP Support

```bash
# Install PHP-FPM
sudo apt install php-fpm php-cli php-mysql

# Update Caddyfile
example.com {
    root * /var/www/html
    php_fastcgi unix//run/php/php-fpm.sock
    file_server
}
```

### WebSocket Proxy

```
ws.example.com {
    reverse_proxy localhost:8080
}
```

## Troubleshooting

### SSL Certificate Not Issued

**Symptoms**: HTTP works, but HTTPS shows error

**Causes**:
1. DNS not pointing to VPS
2. Port 80/443 blocked
3. Invalid email address

**Solution**:
```bash
# Verify DNS
dig +short example.com

# Check if port 443 is open
ssh proxy-vps
sudo ufw status | grep 443

# Check Caddy logs
sudo journalctl -u caddy -n 50

# Manually test ACME challenge
curl http://example.com/.well-known/acme-challenge/test
```

### Caddy Not Starting

```bash
ssh proxy-vps

# Check configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# View detailed logs
sudo journalctl -u caddy -n 100 --no-pager

# Restart service
sudo systemctl restart caddy
```

### Firewall Blocking Connections

```bash
ssh proxy-vps

# Check UFW status
sudo ufw status verbose

# Temporarily disable for testing
sudo ufw disable

# Re-enable after testing
sudo ufw enable
```

### DNS Not Resolving

```bash
# Check nameservers
dig example.com
nslookup example.com

# Wait for DNS propagation
# Use https://dnschecker.org to check globally
```

## Security Best Practices

### 1. Regular Updates

```bash
ssh proxy-vps
sudo apt update && sudo apt upgrade -y
```

### 2. Monitor Fail2ban

```bash
# Check banned IPs
sudo fail2ban-client status sshd

# View logs
sudo tail -f /var/log/fail2ban.log
```

### 3. Review Access Logs

```bash
# Check for suspicious activity
sudo tail -f /var/log/caddy/access.log
```

### 4. Backup SSL Certificates

```bash
# Backup Caddy data directory
sudo tar -czf caddy-backup.tar.gz /var/lib/caddy
```

## Rerunning the Playbook

The playbook is idempotent and can be safely rerun:

```bash
# Update configuration
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml -v

# Run specific tags (if added)
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml \
  --tags firewall -v
```

## Useful Commands

```bash
# Test from local machine
curl -I https://example.com

# Check certificate expiry
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -dates

# Reload Caddy config
ssh proxy-vps sudo systemctl reload caddy

# View real-time connections
ssh proxy-vps sudo netstat -tulpn | grep caddy

# Check disk usage
ssh proxy-vps df -h

# Check memory usage
ssh proxy-vps free -h
```

## Next Steps

1. **Deploy Your Application**: Upload your website/app to `/var/www/html`
2. **Configure Backups**: Set up automated backups for your data
3. **Add Monitoring**: Consider tools like Uptime Kuma or Prometheus
4. **Set Up CI/CD**: Automate deployments with GitHub Actions
5. **Scale**: Add more VPS instances with load balancing if needed

## Reference Files

- **Playbook**: `ansible/playbooks/setup-proxy-vps.yml`
- **Inventory**: `ansible/inventory/proxy-vps.yml`
- **Role**: `ansible/roles/caddy/`
- **Cloud-init**: `proxy-vps-1_cloud-init.yml`

## Getting Help

### Check Logs
```bash
# Caddy logs
ssh proxy-vps sudo journalctl -u caddy -f

# System logs
ssh proxy-vps sudo tail -f /var/log/syslog
```

### Validate Configuration
```bash
ssh proxy-vps sudo caddy validate --config /etc/caddy/Caddyfile
```

### Test Ansible Connection
```bash
ansible -i ansible/inventory/proxy-vps.yml all -m ping -vvv
```
