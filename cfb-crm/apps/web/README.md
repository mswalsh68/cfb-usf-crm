# CFB CRM — Web App

Next.js admin and staff web interface for the CFB CRM platform.

---

## What this app does

- **Platform admin** — Provision new clients, manage teams, users, and permissions
- **Roster CRM** — View, add, edit, and transfer players to alumni
- **Alumni CRM** — Track alumni, log interactions, and manage outreach campaigns

Talks to:
- `global-api` (port 3001) — auth, users, permissions, platform admin
- `app-api` (port 3002) — all roster and alumni data (tenant-scoped)

---

## Local dev

From the repo root (`cfb-crm/`):

```bash
npm run dev
```

Or run just the web app:

```bash
cd apps/web
npm run dev
# Open http://localhost:3000
```

Make sure both APIs are running first (`npm run global-api` and `npm run app-api`).

---

## Environment variables

Create `apps/web/.env.local`:

```env
NEXT_PUBLIC_GLOBAL_API_URL=http://localhost:3001
NEXT_PUBLIC_APP_API_URL=http://localhost:3002
```

---

## Key folders

```
apps/web/
├── app/               Next.js App Router pages
├── components/        Page-level and shared components
├── lib/
│   ├── api.ts         Axios clients for global-api and app-api (withCredentials)
│   ├── auth.ts        User profile storage, role helpers, switchTeam
│   └── teamConfig.ts  Team theme/config types
└── middleware.ts      Route protection (redirect unauthenticated users)
```

---

## Auth notes

- Tokens are stored in **httpOnly cookies** set by the server — never in localStorage
- `lib/auth.ts` stores only the decoded user profile (`cfb_user`) in localStorage for UI use
- All API calls use `withCredentials: true` — cookies are sent automatically
- Silent token refresh is handled in `lib/api.ts` via the axios response interceptor
