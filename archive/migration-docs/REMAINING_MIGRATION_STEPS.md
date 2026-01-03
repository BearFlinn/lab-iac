# Remaining Migration Steps

## Current Status: Phase 3 Complete ✅

You're **very close** to completing the base migration!

---

## Question 1: Namespace Isolation ✅ FIXED

**Issue:** Apps were deploying to `actions-runner-system` (security risk)

**Fix Applied:** Added `--create-namespace --namespace <app-name>` to Helm commands

**For other services, add these flags:**
```bash
helm upgrade --install <service> ./helm \
  --create-namespace \
  --namespace <service-name> \
  --set ...
```

**Recommendation:** Each service in its own namespace:
- `landing-page` → namespace: landing-page
- `zork` → namespace: zork
- `resume-site` → namespace: resume-site
- `coaching-website` → namespace: coaching-website
- `family-dashboard` → namespace: family-dashboard

---

## Question 2: Database Migration Difficulty

**TL;DR:** Pretty easy since you have SSH access!

### Current Databases on deb-web (optiplex):

1. **coaching-website** - PostgreSQL 16
2. **resume-site** - pgvector/PostgreSQL 16
3. **family-dashboard** - PostgreSQL 16

### Migration Process (Per Database):

**Step 1: Dump from old server (deb-web)**
```bash
ssh deb-web
# For coaching-website
docker exec overwatch-coaching-db pg_dump -U coaching overwatch_coaching > coaching.sql

# For resume-site
docker exec resume-site-db-1 pg_dump -U resume resume_db > resume.sql

# For family-dashboard
docker exec family-dashboard-db pg_dump -U dashboard family_dashboard > family.sql

# Copy dumps back to your machine
scp deb-web:~/*.sql /tmp/
```

**Step 2: Deploy services to K8s (creates empty databases)**
```bash
# Push to production branch triggers deployment
```

**Step 3: Restore to new databases**
```bash
# Get database pod name
kubectl get pods -n coaching-website

# Copy dump into pod
kubectl cp /tmp/coaching.sql coaching-website/coaching-website-db-0:/tmp/

# Restore
kubectl exec -n coaching-website coaching-website-db-0 -- \
  psql -U coaching overwatch_coaching < /tmp/coaching.sql
```

**Downtime:** ~5-15 minutes per service (during restore)

**Alternative:** You mentioned services are "largely unused" - a fresh start is totally fine too!

---

## Question 3: What's Left Before Retiring CF Tunnel?

### Phases Remaining:

#### Phase 4: VPS Caddy Configuration
**Goal:** Route internet traffic through VPS → NetBird tunnel → K8s Ingress

**Check if already done:**
```bash
ssh proxy-vps
cat /etc/caddy/Caddyfile
# Look for routes to 10.0.0.226:30487 (K8s ingress NodePort)
```

**If not configured yet:**
```bash
# On proxy-vps, add to Caddyfile:
landing.grizzly-endeavors.com {
  reverse_proxy http://10.0.0.226:30487
}

zork.grizzly-endeavors.com {
  reverse_proxy http://10.0.0.226:30487
}

# ... etc for each service
```

#### Phase 5: Deploy All Services
**Current status:**
- ✅ landing-page (deployed & tested)
- ⏳ zork (Helm chart ready)
- ⏳ resume-site (Helm chart ready, needs secrets)
- ⏳ coaching-website (Helm chart ready, needs secrets)
- ⏳ family-dashboard (Helm chart ready, Infisical configured)

**Action:** Push to production branch for each repo

#### Phase 6: DNS Cutover
**Action:** Update DNS A records to point to VPS IP

**After this, you can retire:**
- ✅ Cloudflare Tunnel
- ✅ Web services on optiplex (coaching, resume, landing, zork)
- ✅ Caddy on optiplex (for web routing)
- ✅ Most Docker containers on optiplex

**Must keep on optiplex:**
- Palworld server (as you mentioned)

---

## Migration Timeline Summary

```
Phase 0: Prerequisites          ✅ DONE
Phase 1: Registry              ✅ DONE
Phase 2: GitHub Runners        ✅ DONE
Phase 3: Helm Charts           ✅ DONE
─────────────────────────────────────
Phase 4: VPS Configuration     🔄 ~30 minutes
Phase 5: Deploy Services       🔄 ~1-2 hours
  - Push each repo to production
  - Add GitHub secrets
  - Optional: Migrate databases
Phase 6: DNS Cutover           🔄 ~15 minutes
─────────────────────────────────────
TOTAL REMAINING: ~2-3 hours
```

---

## You're VERY Close!

**Completed:** Core infrastructure (95%)
**Remaining:** Configuration and deployment (5%)

After Phase 6, you'll have:
- All web services running in Kubernetes
- Fully automated CI/CD (push to deploy)
- VPS handling TLS and routing
- NetBird tunnel secured
- Can retire Cloudflare Tunnel
- Can retire most of optiplex (keep Palworld)

---

## Next Immediate Steps

1. **Check VPS Caddy config** - May already be done
2. **Deploy services** - Just push to production branches
3. **Update DNS** - Point to VPS
4. **Celebrate** 🎉

Would you like me to:
- Check/configure VPS Caddy now?
- Help deploy the remaining services?
- Create database migration scripts?
