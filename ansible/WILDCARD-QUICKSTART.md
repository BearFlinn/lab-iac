# Wildcard Certificate Quick Start Guide

This is a condensed guide to get wildcard SSL/TLS certificates working quickly. For detailed instructions, see `CLOUDFLARE-SETUP.md`.

## Prerequisites

- ✅ Domain using Cloudflare DNS (nameservers pointing to Cloudflare)
- ✅ VPS already provisioned and accessible via `ssh proxy-vps`
- ✅ DNS records pointing to VPS:
  ```
  A    bearflinn.com        -> <vps-ip>
  A    *.bearflinn.com      -> <vps-ip>
  ```

## 5-Minute Setup

### Step 1: Get Cloudflare API Token (2 minutes)

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **"Create Token"**
3. Use **"Edit zone DNS"** template
4. Select your zone: `bearflinn.com`
5. Click **"Create Token"**
6. **Copy the token** (shown only once!)

### Step 2: Create Vault (1 minute)

```bash
cd /home/bearf/Projects/lab-iac

# Generate vault password
openssl rand -base64 32 > .vault_pass
chmod 600 .vault_pass

# Create vault file
cd ansible
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit and add your token
vim group_vars/all/vault.yml
```

Replace with your actual token:
```yaml
---
vault_cloudflare_api_token: "paste-your-token-here"
```

### Step 3: Encrypt Vault (30 seconds)

```bash
cd /home/bearf/Projects/lab-iac

# Encrypt the file
ansible-vault encrypt ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass

# Verify it's encrypted
cat ansible/group_vars/all/vault.yml
# Should see: $ANSIBLE_VAULT;1.1;AES256...
```

### Step 4: Update ansible.cfg (30 seconds)

```bash
vim ansible/ansible.cfg
```

Add under `[defaults]`:
```ini
vault_password_file = ../.vault_pass
```

### Step 5: Create Wildcard Inventory (1 minute)

```bash
cp ansible/inventory/proxy-vps-wildcard.yml.example \
   ansible/inventory/proxy-vps-wildcard.yml

vim ansible/inventory/proxy-vps-wildcard.yml
```

Update these values:
```yaml
caddy_domain: "bearflinn.com"              # Your root domain
caddy_wildcard_domain: "*.bearflinn.com"   # Wildcard
caddy_email: "your-email@gmail.com"        # Your email
caddy_use_wildcard: true
caddy_dns_provider: "cloudflare"
```

### Step 6: Deploy (5-10 minutes)

```bash
cd /home/bearf/Projects/lab-iac

ansible-playbook -i ansible/inventory/proxy-vps-wildcard.yml \
  ansible/playbooks/setup-proxy-vps.yml \
  --vault-password-file .vault_pass -v
```

This will:
1. Install Caddy base package
2. Build Caddy with Cloudflare DNS plugin
3. Configure wildcard certificates
4. Request Let's Encrypt wildcard certificate
5. Set up automatic renewal

### Step 7: Verify (1 minute)

```bash
# Test root domain
curl -I https://bearflinn.com

# Test wildcard (any subdomain)
curl -I https://test.bearflinn.com
curl -I https://api.bearflinn.com
curl -I https://anything.bearflinn.com

# Check certificate
echo | openssl s_client -servername test.bearflinn.com \
  -connect test.bearflinn.com:443 2>/dev/null | \
  openssl x509 -noout -text | grep -A2 "Subject Alternative Name"

# Should show:
# DNS:*.bearflinn.com, DNS:bearflinn.com
```

## Security Checklist

After setup, verify:

- ✅ `.vault_pass` is in `.gitignore` (don't commit!)
- ✅ `vault.yml` is encrypted (run `cat ansible/group_vars/all/vault.yml`)
- ✅ Wildcard cert issued (check with `openssl` command above)
- ✅ HTTP redirects to HTTPS
- ✅ All subdomains work with SSL

## What You Get

With wildcard certificates:

✅ **Root domain**: `bearflinn.com` → SSL certificate
✅ **Any subdomain**: `*.bearflinn.com` → Same SSL certificate
✅ **Automatic renewal**: Caddy handles it automatically
✅ **No manual intervention**: Add subdomains anytime, SSL just works

## Common Issues

### "Token doesn't have permission"

**Fix**: Go to Cloudflare dashboard → API Tokens → Edit token → Ensure "Zone → DNS → Edit" is granted for your specific zone.

### "DNS record not found"

**Fix**: Ensure `*.bearflinn.com` A record points to your VPS IP in Cloudflare DNS.

### "Module dns.providers.cloudflare not found"

**Fix**: The xcaddy build failed. Check logs:
```bash
ssh proxy-vps sudo journalctl -u caddy -n 50
```

Re-run the playbook with `-vvv` for verbose output.

### Vault password error

**Fix**: Ensure `.vault_pass` exists and `ansible.cfg` has:
```ini
vault_password_file = ../.vault_pass
```

## Adding Subdomains

Once wildcard is set up, adding new subdomains is easy:

### Option 1: Same Content (Default)

Just add DNS record in Cloudflare:
```
A    blog.bearflinn.com    -> <vps-ip>
```

It automatically serves content from `/var/www/html` with SSL!

### Option 2: Different Content Per Subdomain

Update `caddy_additional_config` in inventory:

```yaml
caddy_additional_config: |
  @blog host blog.bearflinn.com
  handle @blog {
      root * /var/www/blog
      file_server
  }

  @api host api.bearflinn.com
  handle @api {
      reverse_proxy localhost:3000
  }
```

Re-run playbook to apply.

## Team Sharing

To share with teammates:

1. **Share `.vault_pass` securely** (password manager, Signal, etc.)
2. They put it in their local `.vault_pass`
3. The encrypted `vault.yml` can be committed to git safely
4. Everyone can decrypt with the shared password

## Files to Commit vs. Keep Local

### ✅ Safe to commit (already encrypted/public):
- `ansible/group_vars/all/vault.yml` (encrypted)
- `ansible/group_vars/all/vars.yml` (references vault)
- `ansible/inventory/proxy-vps-wildcard.yml` (your actual inventory)
- `ansible/roles/caddy/**` (role files)

### ❌ NEVER commit (in .gitignore):
- `.vault_pass` (vault password)
- `ansible/group_vars/all/vault.yml` (if unencrypted!)
- Any file with actual API tokens

## Next Steps

1. **Deploy your app**: Upload files to `/var/www/html`
2. **Add more subdomains**: Just add DNS records, SSL works automatically
3. **Customize routing**: Edit `caddy_additional_config` for per-subdomain routing
4. **Monitor logs**: `ssh proxy-vps sudo tail -f /var/log/caddy/access.log`

## Need Help?

See detailed guides:
- **Full setup**: `ansible/CLOUDFLARE-SETUP.md`
- **VPS setup**: `ansible/README-PROXY-VPS.md`
- **Caddy config**: `/etc/caddy/Caddyfile` on VPS

---

**Done!** You now have wildcard SSL certificates that automatically work for any subdomain you create. 🎉
