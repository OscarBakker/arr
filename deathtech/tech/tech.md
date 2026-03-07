# Tech – stack, domains, integrations

Living document for technology choices. Extend with stack details, domains, and integration notes.

---

## Stack (proposed)

TypeScript-first, full-stack, with compliance and document-heavy workflows in mind.

| Layer | Choice | Why |
|-------|--------|-----|
| **Runtime** | Node.js (LTS) | Single language, strong ecosystem, good for integrations (payments, email, later gemeente if we automate). |
| **Framework** | Next.js (App Router) | Full-stack TS, SSR/SEO, API routes, great DX. Fits both customer portal and internal tools. |
| **Database** | PostgreSQL | Reliable, JSON/audit-friendly, full-text. EU hosting easy. |
| **ORM / query** | Drizzle or Prisma | Type-safe schema + migrations; Drizzle lighter, Prisma more batteries-included. |
| **Validation** | Zod | Runtime + types from one source; reuse on client and server. |
| **Auth (customers)** | Auth.js (NextAuth) | Sessions, multiple providers; customer-facing only. |
| **Auth (eHerkenning)** | *Optional* – only if app does aangifte | If staff do aangifte manually in the gemeente portal (browser + eHerkenning), we don't need this. Add custom OAuth/gateway only when we integrate gemeente into the app. See [detail-eherkenning.md](../plan/detail-eherkenning.md). |
| **File / documents** | Filesystem (simplest at home) or S3-compatible | **Simplest at home:** one directory (e.g. `data/documents/{caseId}/`), no extra service; app serves files via authenticated route; backup = rsync/restic. **Upgrade:** MinIO or R2/S3 for presigned URLs and cloud portability. |
| **Payments** | Mollie | Dutch, iDEAL, good API; matches gemeente payment flow. |
| **Jobs / queues** | Inngest or BullMQ (Redis) | Async: reminders, status updates, “batch” document submissions, retries. |
| **Email** | Resend or Postmark | Transactional + templates; EU options available. |
| **Monitoring** | Sentry + (optional) Axiom/Logtail | Errors and audit-style logs; keep PII minimal in logs. |

### Frontend

- **React** (with Next.js), **TypeScript** strict.
- **Tailwind CSS** for UI;
- **React Hook Form + Zod** for forms (aanmelding, document checklists).
- **TanStack Query** for server state and caching.

### Dev / quality

- **pnpm** for packages and monorepo (optional).
- **Vitest** for unit/integration tests; **Playwright** for E2E on critical flows.
- **ESLint + Biome or Prettier** for lint/format.

### Hosting / infra

- Prefer **EU** for app and data (GDPR, AVG).
- **Home hosting:** app + Postgres on your own hardware; **simplest storage** = one directory on disk (e.g. `data/documents/`), no MinIO needed. Expose app via reverse proxy (Caddy, Traefik); back up DB + document folder (e.g. restic, rsync). Optional: add MinIO if you want S3 API and presigned URLs later.
- Cloud options: **Vercel** (EU), **Coolify** / **Hetzner** / **TransIP** VPS, **Fly.io** (EU). DB: **Neon**, **Supabase**, or self-hosted Postgres.

---

## Domains (bounded contexts)

Rough split for later service/module boundaries:

| Domain | Scope | Notes |
|--------|--------|--------|
| **Aanmelding** | Customer signup, intake, document upload (A, B, ID’s) | Forms, validation, secure upload to object storage. |
| **Aangifte** | Death declaration at gemeente | Staff do this (in our app we show case + docs). Can be manual: staff open gemeente portal in browser, log in with eHerkenning there. App–gemeente integration optional (phase 2). See [detail-aangifte.md](../plan/detail-aangifte.md). |
| **Verlof & crematie** | Crematorium booking, verlof tot crematie, transport coordination | Partners, SLA’s; see plan docs. |
| **Klantcommunicatie** | Status updates, termijnen, as-afgifte | Email + optional portal; see [detail-klantcommunicatie.md](plan/detail-klantcommunicatie.md). |
| **Partners** | Crematoria, vervoerders, gemeenten | Configuration, contact, possibly APIs. |
| **Product & betaling** | Pakketten, prijzen, Mollie | [detail-product-prijzen.md](plan/detail-product-prijzen.md). |

---

## Integrations (to detail)

**Must-have (app ↔ external):** customers (your app), Mollie (payments).  
**Not required for v1:** your app does not need to connect to the gemeente. Staff can do aangifte in the gemeente’s website in their browser. Integration (eHerkenning in app, APIs) is for later automation if desired.

| Integration | Purpose | Tech note |
|-------------|---------|-----------|
| **eHerkenning / gemeente** | Only if we do aangifte from inside the app | Optional. Manual alternative: staff use gemeente portal + eHerkenning in browser. |
| **Mollie** | iDEAL (and later other methods) | REST API; webhooks for status. |
| **Crematorium / vervoerder** | Boeking, afspraken | TBD: email, portal, or API. |

---

## Security & compliance

- **Encryption at rest** for document storage; **TLS** everywhere.
- **Document storage (filesystem):** not less safe than S3 if done right: (1) build paths only from DB IDs (e.g. `caseId`), never from user input – prevents path traversal; (2) serve files only via an authenticated API route that checks session and case access; (3) keep document directory outside web root so the server never serves it directly; (4) encrypt backups (e.g. restic). Optional: encrypt volume (LUKS) or encrypt files in app before write.
- **Audit log** for who did what (aangifte, status changes, document access); store in DB or append-only store.
- **AVG/GDPR**: data minimalisatie, retention (e.g. as 1 maand), processing agreements if using processors.
- **eHerkenning** only for intended use (aangifte namens opdrachtgever).

---

## Open points

- [ ] Aangifte: manual (staff + gemeente portal) first, or build gemeente/eHerkenning into app from day one?
- [ ] Monorepo vs single Next.js app (start simple, split by domain when needed).
- [ ] First gemeente: which one to support and document first.
- [ ] Document generation: need for PDFs/templates (overlijdensakte, bevestigingen)?

---

*Start simple: one Next.js app, Postgres, S3-compatible storage, Mollie – all customer- and workflow-facing. No gemeente integration required for v1; add eHerkenning/gemeente only if we automate the aangifte step.*
