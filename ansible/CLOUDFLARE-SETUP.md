# Cloudflare DNS-01 Setup for Wildcard Certificates

This guide walks you through setting up wildcard SSL/TLS certificates using Cloudflare DNS-01 ACME challenge.

## Prerequisites

1. Domain registered and using Cloudflare nameservers
2. Cloudflare account with access to the domain

## Step 1: Create Cloudflare API Token

### 1.1 Log into Cloudflare Dashboard

Go to: https://dash.cloudflare.com/

### 1.2 Navigate to API Tokens

1. Click on your profile icon (top right)
2. Select **"My Profile"**
3. Click on **"API Tokens"** in the left sidebar
4. Click **"Create Token"**

### 1.3 Configure Token Permissions

**Option A: Use Template (Recommended)**
1. Find **"Edit zone DNS"** template
2. Click **"Use template"**
3. Under **"Zone Resources"**, select:
   - **Zone**: `bearflinn.com` (or your specific domain)
4. Click **"Continue to summary"**
5. Click **"Create Token"**

**Option B: Custom Token (Advanced)**
1. Click **"Create Custom Token"**
2. Set **Token name**: `Caddy DNS-01 Challenge`
3. Add permissions:
   - **Zone** → **DNS** → **Edit**
4. Under **Zone Resources**:
   - **Include** → **Specific zone** → `bearflinn.com`
5. Under **IP Address Filtering** (optional but recommended):
   - Add your VPS IP address for extra security
6. Click **"Continue to summary"**
7. Click **"Create Token"**

### 1.4 Save Your Token

**CRITICAL**: Copy the token immediately! It will only be shown once.

```
Example token format:
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0
```

## Step 2: Create Encrypted Ansible Vault

### 2.1 Create Vault Password File (Local Only)

```bash
cd /home/bearf/Projects/lab-iac

# Create a strong password for the vault
openssl rand -base64 32 > .vault_pass

# Secure the password file
chmod 600 .vault_pass
```

**IMPORTANT**: The `.vault_pass` file is in `.gitignore` and should **NEVER** be committed to git.

### 2.2 Create Vault File with Your Token

```bash
cd ansible

# Copy the example
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit and add your real Cloudflare API token
vim group_vars/all/vault.yml
```

Replace `your-cloudflare-api-token-here` with your actual token:

```yaml
---
vault_cloudflare_api_token: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"
```

### 2.3 Encrypt the Vault

```bash
cd /home/bearf/Projects/lab-iac

# Encrypt the vault file
ansible-vault encrypt ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

The file is now encrypted and safe to commit to git!

### 2.4 Verify Encryption

```bash
# View encrypted content (should see $ANSIBLE_VAULT;1.1;AES256...)
cat ansible/group_vars/all/vault.yml

# View decrypted content (requires password)
ansible-vault view ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

## Step 3: Update Ansible Configuration

Update `ansible.cfg` to use the vault password file:

```bash
vim ansible/ansible.cfg
```

Add this line under `[defaults]`:

```ini
[defaults]
vault_password_file = ../.vault_pass
```

## Step 4: Update Inventory for Wildcard Support

Edit your inventory to enable wildcard certificates:

```bash
vim ansible/inventory/proxy-vps.yml
```

Update the configuration:

```yaml
all:
  hosts:
    proxy-vps-1:
      ansible_host: proxy-vps
      ansible_user: bearf
      ansible_port: 2222

      # Wildcard certificate configuration
      caddy_domain: "bearflinn.com"              # Root domain
      caddy_wildcard_domain: "*.bearflinn.com"   # Wildcard subdomain
      caddy_email: "bearflinn@gmail.com"
      enable_caddy: true

      # Enable DNS-01 challenge with Cloudflare
      caddy_dns_provider: "cloudflare"
      caddy_use_wildcard: true
```

## Step 5: Run the Playbook

The updated playbook will automatically:
1. Build Caddy with Cloudflare DNS plugin
2. Configure wildcard certificates
3. Set up the Cloudflare API token securely

```bash
cd /home/bearf/Projects/lab-iac

# Run with vault password
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml \
  --vault-password-file .vault_pass -v
```

## Security Best Practices

### ✅ DO:
- Keep `.vault_pass` file local and never commit it
- Use `ansible-vault encrypt` to encrypt sensitive files
- Restrict Cloudflare token to specific zones only
- Add VPS IP filtering to Cloudflare token (optional but recommended)
- Use strong vault passwords (32+ characters)
- Rotate API tokens periodically

### ❌ DON'T:
- Never commit `.vault_pass` to git
- Never commit unencrypted `vault.yml` with real tokens
- Don't use Global API Key (too powerful, use API Token instead)
- Don't share vault password via insecure channels
- Don't reuse the same token across different projects

## Managing the Vault

### View Encrypted Content

```bash
ansible-vault view ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

### Edit Encrypted Content

```bash
ansible-vault edit ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

### Change Vault Password

```bash
ansible-vault rekey ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

### Decrypt (for emergency recovery)

```bash
# Decrypt to plaintext (be careful!)
ansible-vault decrypt ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass

# Remember to re-encrypt immediately after!
ansible-vault encrypt ansible/group_vars/all/vault.yml \
  --vault-password-file .vault_pass
```

## Troubleshooting

### Token Permissions Error

If Caddy fails to update DNS records:

```
Error: failed to get certificate: acme: error code 403: Forbidden
```

**Solution**: Check token permissions in Cloudflare:
1. Ensure **Zone → DNS → Edit** permission is granted
2. Verify the correct zone is selected
3. Try regenerating the token

### Vault Password Not Found

```
ERROR! Attempting to decrypt but no vault secrets found
```

**Solution**: Ensure `.vault_pass` exists and `ansible.cfg` points to it correctly.

### Token Exposed in Logs

If you accidentally exposed your token:
1. **Immediately** revoke it in Cloudflare dashboard
2. Generate a new token
3. Update the encrypted vault
4. Never commit the exposure to git (use `git filter-branch` if needed)

## Verifying Setup

After deployment, check that wildcard certificate is issued:

```bash
# Check certificate for wildcard
echo | openssl s_client -servername test.bearflinn.com \
  -connect test.bearflinn.com:443 2>/dev/null | \
  openssl x509 -noout -text | grep -A2 "Subject Alternative Name"

# Should show:
# DNS:*.bearflinn.com, DNS:bearflinn.com
```

## Team Collaboration

When working with a team:

1. **Share the `.vault_pass` securely** (use password manager, Signal, etc.)
2. Each team member stores `.vault_pass` locally
3. The encrypted `vault.yml` can be committed to git safely
4. Everyone uses the same vault password to decrypt

Or use different approaches:
- **Separate vaults** per team member
- **CI/CD secrets** for automated deployments
- **HashiCorp Vault** or similar for enterprise setups

## References

- [Cloudflare API Tokens](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Caddy DNS Providers](https://caddyserver.com/docs/modules/)
- [Let's Encrypt DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
