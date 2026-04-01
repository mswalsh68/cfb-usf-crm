# Onboarding
In `apps/global-api` run:
```bash
npm run onboard "--" "--email=admin@admin.com" "--firstName=PHS" "--lastName=Admin"
```

---

# CFB CRM — Monorepo

College Football Player & Alumni CRM — Next.js web app + React Native (Expo) mobile app, backed by two Node.js APIs and Azure SQL Server databases.

---

## Architecture

```
cfb-crm/
├── apps/
│   ├── web/             Next.js web app (admin + staff UI)
│   ├── mobile/          React Native (Expo) — iOS + Android
│   ├── global-api/      Auth, users, permissions, platform admin  → port 3001
│   └── app-api/         Roster CRM + Alumni CRM (tenant-scoped)  → port 3002
├── packages/
│   ├── auth/            JWT helpers (sign, verify, extract — shared across APIs)
│   ├── db/              Tenant-scoped database executor (shared across APIs)
│   ├── types/           Shared TypeScript types
│   ├── ui/              Shared component library + theme tokens
│   └── assets/          Shared static assets
└── databases/
    ├── global/          Global DB schema migrations + stored procedures
    │   ├── migrations/  001_initial_schema → 008_token_version
    │   └── stored-procedures/
    ├── app/             App DB schema migrations + stored procedures
    │   ├── migrations/  001_app_db_schema → 005_rls_policies
    │   └── stored-procedures/
    └── scripts/         Utility scripts (seed data, clear test data)
```

---

## Database Model

| Database | What it holds | One per... |
|---|---|---|
| **Global DB** | Users, roles, permissions, teams, team config, refresh tokens | Platform (shared by all clients) |
| **App DB** | Players, stats, alumni, interactions, campaigns | Client (one DB per team) |

Each client provisioned via the platform admin gets their own App DB (`{ClientCode}_App`). The app-api routes all data operations to the correct App DB based on the JWT's `appDb` and `dbServer` claims.

---

## Prerequisites

- Node.js 20+
- npm 10+
- Azure subscription (SQL Server + App Service or Container Apps)
- Expo CLI: `npm install -g expo-cli`

---

## Local Setup

### 1. Clone the repo

```bash
git clone https://github.com/mswalsh68/cfb-usf-crm.git
cd cfb-usf-crm/cfb-crm
```

### 2. Install dependencies & activate Git hooks

```bash
npm install
npm run setup
```

> `npm run setup` points Git at the `.githooks/` folder stored in the repo.
> This protects `main` — you will be blocked from committing or pushing directly to it.

### 3. Always work on a branch

```bash
# Pull latest main first
git checkout main
git pull

# Create your branch
git checkout -b feature/your-feature-name

# When done, push and open a PR on GitHub — never push to main directly
git push origin feature/your-feature-name
```

### 4. Configure environment variables

```bash
# global-api
cp .env.example apps/global-api/.env

# app-api
cp .env.example apps/app-api/.env

# web
cp .env.example apps/web/.env.local

# mobile
cp .env.example apps/mobile/.env
```

Each `.env` file needs:
- Azure SQL connection details (`DB_SERVER`, `DB_USER`, `DB_PASS`)
- JWT secrets (generate with: `node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"`)
- `ALLOWED_ORIGINS` — comma-separated list of allowed client URLs

### 5. Set up the Global DB

Run migrations in order against your Global Azure SQL database:

```bash
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/migrations/001_initial_schema.sql
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/migrations/002_team_config.sql
# ... continue through 008_token_version.sql
```

Then deploy stored procedures:

```bash
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/stored-procedures/sp_Global_AllProcedures.sql
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/stored-procedures/sp_TeamConfig.sql
sqlcmd -S your-server.database.windows.net -d CfbGlobal -i databases/global/stored-procedures/sp_Teams.sql
```

### 6. Provision a client (App DB)

Each client gets their own App DB created automatically via the platform admin onboarding screen, or manually:

```bash
npm run onboard "--" "--email=admin@client.com" "--firstName=Admin" "--lastName=User"
```

This creates the `{ClientCode}_App` database, applies the app schema and stored procedures, and creates the first admin user.

### 7. Start APIs

```bash
# Both APIs in parallel:
npm run dev

# Or individually:
npm run global-api   # port 3001
npm run app-api      # port 3002
```

### 8. Start web app

```bash
cd apps/web
npm run dev
# Open http://localhost:3000
```

### 9. Start mobile app

```bash
npm run mobile
# Press i for iOS simulator, a for Android emulator
# Scan QR with Expo Go for a physical device
```

---

## Roles Reference

| Role | Platform Admin | Roster CRM | Alumni CRM |
|---|---|---|---|
| `platform_owner` | Full access | Full access | Full access |
| `global_admin` | Full access | Full access | Full access |
| `app_admin` | — | Full access in assigned app | Full access in assigned app |
| `coach_staff` | — | Read + write | Read + write |
| `player` | — | View own record only | — |
| `readonly` | — | View only | View only |

---

## Player → Alumni Transfer Flow

1. Coach/admin selects active players and clicks **Transfer to Alumni**
2. Sets transfer reason, year, and semester
3. Confirms via modal
4. `POST /players/transfer` calls `sp_TransferToAlumni` on the App DB
5. Stored proc marks players as transferred/graduated in the roster tables
6. app-api then calls `sp_CreateAlumniFromPlayer` to create alumni records in the same App DB
7. Players disappear from the active roster and appear in the Alumni CRM

> No linked servers or distributed transactions needed — both roster and alumni data live in the same App DB per client.

---

## Azure Deployment

### APIs — Azure App Service or Container Apps

- `global-api` and `app-api` are separate deployable Node.js apps
- Use **Managed Identity** for SQL auth in production (no passwords in env vars)
- Add each service's URL to `ALLOWED_ORIGINS` in the other services

### Databases — Azure SQL

- 1 **Global DB** shared across all clients
- 1 **App DB** per client, provisioned at onboarding time
- All databases can share a single logical Azure SQL server (cost-effective for dev)
- Enable **Azure Active Directory authentication** + Managed Identity for production

### Web — Vercel or Azure Static Web Apps

```bash
cd apps/web
npm run build
```

### Mobile — Expo EAS Build

```bash
npm install -g eas-cli
eas build --platform all
eas submit
```

Set production API URLs in EAS build profile environment variables.

---

## First Login

After running migrations and provisioning a client, log in with the admin credentials provided during onboarding. To manually hash a password:

```bash
node -e "
const bcrypt = require('bcryptjs');
bcrypt.hash('YourNewPassword123!', 12).then(h => console.log(h));
"
# Then: UPDATE dbo.users SET password_hash = 'output' WHERE email = 'admin@yourprogram.com'
```
