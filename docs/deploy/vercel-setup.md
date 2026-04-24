# Vercel deploy + DNS runbook

One-time setup to get `www.inferbridge.dev` live on Vercel with SSL.
Written 2026-04-24. Should take ~15 minutes end-to-end.

## Prerequisites

- GitHub repo pushed to `Yogeshshirsath01/inferbridge-site` (public).
- Vercel account connected to the same GitHub.
- DNS control at the registrar (Namecheap) for `inferbridge.dev`.

## 1. Import the repo into Vercel

1. Go to [vercel.com/new](https://vercel.com/new).
2. Pick **Import Git Repository** → select `Yogeshshirsath01/inferbridge-site`.
   If the repo isn't listed, click **Adjust GitHub App Permissions** and grant
   Vercel access to this repo.
3. Framework preset: Vercel will auto-detect **Astro**. Leave defaults:
   - Build command: `npm run build`
   - Output directory: `dist`
   - Install command: `npm install`
   - Node version: 20.x (set under Settings → General → Node.js Version if needed)
4. Root directory: leave blank (repo root).
5. Environment variables: none required for the landing page.
6. Click **Deploy**. First build takes 1–2 minutes. The preview URL will be
   something like `inferbridge-site-abc123.vercel.app`.

## 2. Attach the production domain

Once the first deploy is green:

1. Project dashboard → **Settings → Domains**.
2. Add `www.inferbridge.dev`. Vercel will show it as **Invalid Configuration**
   until DNS is wired up — this is expected.
3. Add `inferbridge.dev` (apex) as well. Mark `www.inferbridge.dev` as the
   **primary** domain; Vercel will auto-redirect the apex to the www host.

Vercel will show two required DNS records:

| Type  | Name (host) | Value                   |
| ----- | ----------- | ----------------------- |
| CNAME | `www`       | `cname.vercel-dns.com`  |
| A     | `@` (apex)  | `76.76.21.21`           |

(If Vercel gives different values in the UI, use those — the UI is the source
of truth.)

## 3. Wire up DNS at Namecheap

1. Namecheap dashboard → **Domain List** → `inferbridge.dev` → **Manage**.
2. **Advanced DNS** tab → **Add New Record**:
   - Type: `CNAME Record`, Host: `www`, Value: `cname.vercel-dns.com`, TTL: Automatic.
   - Type: `A Record`, Host: `@`, Value: `76.76.21.21`, TTL: Automatic.
3. Remove any conflicting records for `@` or `www` (old Namecheap parking
   pages, URL redirects, etc.).
4. Save. Propagation usually completes in 5–15 minutes on Namecheap.

## 4. Verify

1. Back in Vercel → **Settings → Domains**: both domains should flip to
   **Valid Configuration** within 10 minutes. Vercel auto-provisions Let's
   Encrypt SSL certificates — no manual cert action needed.
2. From a terminal:
   ```
   dig +short www.inferbridge.dev
   curl -I https://www.inferbridge.dev
   ```
   First should return a CNAME chain ending at Vercel. Second should return
   `HTTP/2 200`.
3. Visit [https://www.inferbridge.dev](https://www.inferbridge.dev) in a
   browser and confirm:
   - Page loads with hero + all eight sections.
   - Padlock icon is green (SSL valid).
   - Code Migration tabs switch between Python / Node / cURL.
   - "Copy" button on the active panel copies to clipboard.
4. Visit [https://inferbridge.dev](https://inferbridge.dev) (apex, no www) —
   should redirect to `https://www.inferbridge.dev`.

## 5. Auto-deploy on push

Already enabled by default. Every push to `main` triggers a production deploy.
Pull requests get preview deployments.

## Rollback

- Vercel → **Deployments** → pick a previous green deployment → **Promote to
  Production**. Takes ~10 seconds, no DNS change needed.

## Common issues

- **"Invalid Configuration" after 30 minutes**: check Namecheap DNS for stale
  records. Sometimes old CNAMEs linger; delete and re-add.
- **Mixed-content warnings**: should not happen — all assets are first-party
  and served from the same origin. If Lighthouse flags it, check that no
  hardcoded `http://` URLs snuck into the source.
- **Apex redirect loop**: make sure the apex uses the `A` record to
  `76.76.21.21`, not a CNAME to the www host.
