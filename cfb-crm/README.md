# Onboarding
in apps/global-api run
npm run onboard "--" "--email=admin@admin.com" "--firstName=PHS" "--lastName=Admin"



# CFB CRM — Monorepo

College Football Player & Alumni CRM — React Native (Expo) mobile app backed by three Azure-hosted Node.js APIs and Azure SQL Server databases.

---

## Architecture

```
cfb-crm/
├── apps/
│   ├── mobile/          React Native (Expo) — iOS + Android
│   ├── global-api/      Auth, users, permissions   → port 3001
│   ├── roster-api/      Current roster CRM         → port 3002
│   └── alumni-api/      Alumni CRM + outreach       → port 3003
├── packages/
│   ├── ui/              Shared component library + theme tokens
│   ├── auth/            JWT helpers (shared across all APIs)
│   └── types/           Shared TypeScript types
└── databases/
    ├── global/          Schema migrations (users, roles, permissions)
    ├── roster/          Schema migrations (players, stats, docs)
    ├── alumni/          Schema migrations (alumni, campaigns, messages)
    └── stored-procedures/  sp_GraduatePlayer + helpers
```

---

## Prerequisites

- Node.js 20+
- Yarn (classic, v1)
- Azure subscription (SQL Server + App Service or Container Apps)
- Expo CLI: `npm install -g expo-cli`

---

## Local Setup

### 1. Install dependencies

```bash
yarn install
```

### 2. Configure environment variables

```bash
# Copy and fill in each .env file:
cp .env.example apps/global-api/.env
cp .env.example apps/roster-api/.env
cp .env.example apps/alumni-api/.env
cp .env.example apps/mobile/.env

# Edit each file with your Azure SQL connection strings and JWT secrets.
# Generate JWT secrets:
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

### 3. Set up databases

Run migrations in order against each Azure SQL database using SSMS or sqlcmd:

```bash
# Global DB
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/migrations/001_initial_schema.sql

# Roster DB
sqlcmd -S your-roster-server.database.windows.net -d CfbRoster -i databases/roster/migrations/001_initial_schema.sql

# Alumni DB
sqlcmd -S your-alumni-server.database.windows.net -d CfbAlumni -i databases/alumni/migrations/001_initial_schema.sql
```

### 4. Deploy stored procedures

```bash
# Run on the Roster DB server (it calls Alumni and Global via linked servers)
sqlcmd -S your-roster-server -d CfbRoster -i databases/stored-procedures/sp_GraduatePlayer.sql
```

Before running the graduation stored proc in production:
1. Set up a SQL Server Linked Server from Roster → Alumni named `[ALUMNI_DB]`
2. Set up a SQL Server Linked Server from Roster → Global named `[GLOBAL_DB]`
3. Enable MSDTC on both servers for distributed transactions

### 5. Start APIs

```bash
# All three APIs in parallel:
yarn dev

# Or individually:
yarn global-api   # port 3001
yarn roster-api   # port 3002
yarn alumni-api   # port 3003
```

### 6. Start mobile app

```bash
yarn mobile
# Then press i for iOS simulator or a for Android emulator
# Scan QR with Expo Go app for physical device
```

---

## Roles Reference

| Role | Global Admin screen | Roster CRM | Alumni CRM |
|------|--------------------| -----------|------------|
| `global_admin` | Full access | Full access | Full access |
| `app_admin` | — | Full access in assigned app | Full access in assigned app |
| `coach_staff` | — | Read + write | Read + write |
| `player` | — | View own record only | — |
| `readonly` | — | View only | View only |

---

## Graduation Flow

1. Coach/admin opens **Graduate Players** tab in Roster CRM
2. Multi-selects active players, sets graduation year + semester
3. Confirms the action via modal
4. `POST /players/graduate` calls `sp_GraduatePlayer` on Roster DB
5. Stored proc runs as a **distributed transaction**:
   - Marks players as `graduated` in Roster DB
   - Inserts alumni records in Alumni DB (via linked server)
   - Swaps app permissions in Global DB (roster → alumni)
   - Rolls back everything if any step fails
6. Players disappear from active roster, appear in Alumni CRM

---

## Azure Deployment

### APIs — Azure App Service or Container Apps

Each API is a separate deployable Node.js app. Recommended:
- Azure App Service (Basic B1 tier per API for dev, Standard S1 for prod)
- Use **Managed Identity** for SQL Server auth in production (no passwords in env vars)
- Add each API's App Service URL to ALLOWED_ORIGINS in the other services

### Databases — Azure SQL

- 3 separate Azure SQL databases (can share a single logical server for cost savings in dev)
- Enable **Azure Active Directory authentication** + Managed Identity for production
- Set up **Linked Servers** between Roster and Alumni + Global for the graduation stored proc
- Recommended tier: General Purpose, 2 vCores per DB

### Mobile — Expo EAS Build

```bash
npm install -g eas-cli
eas build --platform all
eas submit
```

Set production API URLs in EAS build profile environment variables.

---

## Adding a New Screen

All screens live in `apps/mobile/app/`. Expo Router uses file-based routing:

```
app/(roster)/stats.tsx        → navigable at /(roster)/stats
app/(alumni)/campaigns.tsx    → navigable at /(alumni)/campaigns
```

Import shared components from `@cfb-crm/ui` and types from `@cfb-crm/types`.

---

## First Login

After running migrations, a default global admin account is seeded:

```
Email:    admin@yourprogram.com
Password: (set via the update-password script before first deploy)
```

Run this to hash and update the seed password:

```bash
node -e "
const bcrypt = require('bcryptjs');
bcrypt.hash('YourNewPassword123!', 12).then(h => console.log(h));
"
# Then UPDATE users SET password_hash = 'output' WHERE email = 'admin@yourprogram.com'
```
