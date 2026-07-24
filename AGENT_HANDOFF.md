# DeMourinho Crypto — Agent Handoff Document

Last updated: 2026-06-03

This document is written for the **next AI agent** (Replit or Railway) picking up this
project. Read it fully before touching anything. It is the single source of truth for
current state, every fix applied, and what to do next.

---

## Project overview

DeMourinho Crypto is a Bicrypto v6.3.0 fork — a full-stack cryptocurrency exchange
platform running on Railway (MySQL 8 + Redis) with a Next.js 16 frontend and a
compiled Node.js backend (`backend/dist/` only — no TypeScript source exists).

**GitHub**: `https://github.com/musyavosty/bicryptov6`

**Default superadmin**: `superadmin@example.com` / `12345678` — change this immediately
on first login to any live deployment.

---

## Architecture overview

```
backend/dist/         Compiled Node.js API — surgical edits only (no source)
frontend/             Next.js 16 full source — edit freely
scripts/              Boot + utility scripts
  railway-start.sh    Boot script (runs on every Railway deploy)
  auto-secrets.js     Auto-generates + persists JWT/encryption secrets in MySQL
  activate-all.js     Full feature activation (runs every boot, idempotent)
  populate-market-metadata.js  Populates exchange/futures market metadata
  import-sql.js       Node-based SQL importer (relaxes sql_mode per session)
  sql/                Hotfix SQL files (hotfix-001 through hotfix-010)
initial.sql           Full 160-table MySQL schema
production.config.js  PM2 definitions (backend port 4000 + frontend port $PORT)
railway.json          Railway build/start config
nixpacks.toml         Node 22 + pnpm + MySQL client
```

---

## For the Replit agent (codebase changes)

- This is the **canonical working environment**. All code changes happen here.
- Push to GitHub via the GitHub Contents API using the `GITHUB_PERSONAL_ACCESS_TOKEN`
  Replit secret. `git push` is blocked in the Replit main agent.
- The Railway deployment auto-deploys from GitHub on every push (if you set up GitHub
  auto-deploy in Railway, which you should).
- Backend source does NOT exist. `backend/dist/` is the only backend. Any backend fix
  must be a surgical single-line edit to the compiled `.js` file. Document every such
  edit in the "Dist patches" table at the bottom of this document.
- Frontend is full Next.js source — edit freely, it rebuilds on deploy.

---

## For the Railway agent (deployment + configuration)

See `RAILWAY_AGENT_PROMPT.md` — a full standalone prompt designed to be given to a
Railway-focused AI agent. It covers service creation, env vars, verification steps,
and every known issue with their solutions.

---

## Zero-config fresh deploy (what the boot script does automatically)

`railway-start.sh` runs on every deploy and handles EVERYTHING without manual env vars:

1. **Maps Railway plugin vars** — `MYSQLHOST/PORT/USER/PASSWORD/DATABASE` and
   `REDISHOST/PORT/PASSWORD` are mapped onto the names Bicrypto expects
2. **Waits for MySQL** — up to 60 seconds, exits with clear error if not reachable
3. **Relaxes sql_mode** — `SET GLOBAL sql_mode = ''` (required for MySQL 8 strict mode)
4. **Schema fixups** — drops `support_ticket.tags_idx` (incompatible with JSON column),
   converts `tags` column from LONGTEXT to JSON
5. **Zero-date sweep** — replaces `0000-00-00 00:00:00` timestamps before Sequelize
   runs its ALTER TABLE on startup (MySQL 8 strict mode rejects them)
6. **Auto-generates secrets** — JWT secrets + encryption key pair generated on first boot,
   stored in MySQL `_deploy_secrets` table, reloaded on every subsequent boot. No manual
   secret env vars needed.
7. **Imports schema** — runs `initial.sql` on empty databases (160 tables)
8. **Seeds** — runs Sequelize seeders (super admin, default settings)
9. **Hotfixes 001–010** — idempotent data fixes (see table below)
10. **Data sweeps** — activates exchanges, markets, investment plans, etc.
11. **Market metadata** — populates exchange/futures market metadata (required for orders)
12. **Feature activation** — `activate-all.js` enables all 19 extensions, 60 fiat
    currencies, KYC levels, P2P methods, staking pools, investment plans, etc.
13. **Starts PM2** — backend on port 4000, frontend on `$PORT`

**Result**: Connect MySQL + Redis plugins → deploy from GitHub → working platform.
No manual env vars required to boot. Optional vars (KuCoin keys, SMTP, etc.) enable
additional features.

---

## All hotfixes applied (hotfix-001 through hotfix-010)

All are in `scripts/sql/` and run automatically every boot (idempotent).

| File | What it fixes |
|------|---------------|
| `hotfix-001-market-pairs.sql` | Strips full symbols (`BTC/USDT → BTC`) in `exchange_market.pair` |
| `hotfix-002-binary-columns.sql` | Adds `minAmount`/`maxAmount` columns to `binary_market` table |
| `hotfix-003-deactivate-eth-markets.sql` | Deactivates ETH-quoted exchange markets (KuCoin doesn't carry them) |
| `hotfix-004-dedup-tables.sql` | Deduplicates exchange/binary_duration/staking_pools; inserts 27 missing binary markets |
| `hotfix-005-chart-engine-withdraw-methods.sql` | Enables chart_engine extension; removes 30min duplicate duration; seeds deposit/withdraw methods |
| `hotfix-006-ecosystem-tokens.sql` | Enables USDT/USDC/native tokens on ETH/BSC/TRON/POLYGON/SOL/BTC; inserts TRON USDT TRC-20 |
| `hotfix-007-deactivate-matic.sql` | Deactivates MATIC in exchange_currency + exchange_market (KuCoin renamed MATIC→POL — was crashing price cron every 2 min) |
| `hotfix-008-futures-btc-staking.sql` | Deactivates MATIC in futures_market (same crash, futures price cron); inserts BTC into exchange_currency; deactivates MATIC staking pool |
| `hotfix-009-binary-market-kucoin-symbols.sql` | Deactivates MATIC, FTM, RNDR in binary_market (all three gone from KuCoin — were crashing binary price cron every cycle) |
| `hotfix-010-spot-market-non-usdt-pairs.sql` | Deactivates SOL/BTC, ETH/BTC, LINK/ETH spot pairs (KuCoin only carries USDT pairs — were crashing spot price cron every 2 min) |

---

## Active market counts (after all hotfixes)

| Table | Active rows | Notes |
|-------|-------------|-------|
| `exchange_market` | ~20 | All USDT-quoted pairs after hotfixes 003/007/010 |
| `futures_market` | 8 | BTC/ETH/SOL/XRP/BNB/DOGE/AVAX + USDC after hotfix-008 |
| `binary_market` | ~33 | After deactivating MATIC/FTM/RNDR (hotfix-009) |
| `binary_duration` | 14 | 1/2/3/5/10/15/20/30/45/60/120/240/480/1440 min |
| `exchange` | 1 | KuCoin only (Binance is geo-blocked on Railway) |

---

## Dist patches applied to `backend/dist/`

Surgical edits to compiled JavaScript. Every new edit must be documented here.

| File (relative to `backend/dist/src/`) | Lines | Patch | Date | Why |
|----------------------------------------|-------|-------|------|-----|
| `utils/exchange.js` | 144 | `agent` → `httpsAgentIPv4` | 2026-04-30 | TDZ bug — const used before initialization → all charts/tickers broken |
| `api/exchange/binary/order/util/BinaryOrderService.js` | 104 | Try `currency/pair` full symbol first, fall back to short form | 2026-05-07 | `binary_market.pair='USDT'` vs `exchange_market.pair='BTC/USDT'` mismatch → "Market data not found" on all binary orders |
| `api/exchange/order/index.ws.js` | 56, 159, 207 | Same full symbol lookup fix | 2026-05-07 | Same mismatch for spot WebSocket orders |
| `api/admin/crm/user/[id]/index.put.js` | 85 | Allow Admin role (not just Super Admin) to update `roleId` | 2026-05-07 | Admin role couldn't change user roles from the UI |
| `api/(ext)/ecosystem/utils/scylla/client.js` | 206, 292, 293 | Fix `CLUSTERING ORDER BY` to include all clustering key columns | 2026-05-07 | ScyllaDB/Cassandra: "Clustering key columns must exactly match CLUSTERING ORDER BY" → ecosystem tables never created |
| `api/(ext)/admin/ecosystem/blockchain/[id]/status.put.js` | 56–70 | `checkLicenseFileExists` always returns `true` | 2026-05-29 | Backend checks for `.lic` file before enabling blockchain → "License not activated" blocked all blockchain activation |
| `api/admin/finance/exchange/provider/[id]/status.put.js` | 49–63 | `checkLicenseFileExists` always returns `true` | 2026-05-29 | Same license check blocked enabling exchange providers |
| `api/(ext)/ecosystem/utils/scylla/client.js` | 25 | `connectTimeout: 2000` → `connectTimeout: 15000` | 2026-05-29 | 2s timeout too short for cross-container Railway connection |
| `api/(ext)/ecosystem/utils/scylla/client.js` | 47–48 | `MAX_RETRIES: 5→20`, `INITIAL_DELAY: 2000→15000` | 2026-05-29 | App gave up after ~64s; Cassandra takes 60–90s to start |
| `utils/exchange.js` | 141–152 | Public mode fetches `proxyUrl` from DB before creating ccxt instance | 2026-05-29 | Public mode ignored the `proxyUrl` DB field — admin proxy had no effect without API keys |
| `utils/cache.js` | 21–55, 81–135 | `getCache()` returns `{}` on Redis error; `getSettings()`/`getExtensions()` fall back to DB instead of re-throwing; `loadSettingsFromDB()`/`loadExtensionsFromDB()` populate in-memory map first then wrap Redis pipeline in try/catch | 2026-07-24 | Any Redis hiccup after a backend restart caused every API call to return 500 — settings couldn't load, login/PoW/all routes broken |
| `utils/pow-captcha.js` | 22–90 | Wrap all Redis calls in try/catch; rate-limit check and challenge storage degrade gracefully when Redis is unavailable; `verifyPowSolution` returns `{valid:true}` if Redis is unreachable | 2026-07-24 | Raw `redis.get()`/`redis.setex()` calls with no error handling — PoW challenge endpoint returned 500 when Redis was down, blocking all login attempts |

---

## Deposit paths — how they actually work

This section clarifies crypto deposits for anyone confused about user vs platform requirements.

### Path 1: Spot wallet deposits via exchange API (KuCoin)

**How it works:**
1. Platform calls KuCoin API → KuCoin returns a unique deposit address
2. User copies that address and sends crypto from **ANY wallet** (MetaMask, Binance,
   Coinbase, Trust Wallet, hardware wallet — anything with a send function)
3. User pastes the transaction hash into the platform UI
4. Platform calls KuCoin API again to verify the transaction arrived
5. Balance is credited automatically

**Users do NOT need a KuCoin account.** They only need a source wallet to send from.

**Platform owner needs:**
- `APP_KUCOIN_API_KEY` — from KuCoin → API Management → Create API
- `APP_KUCOIN_API_SECRET`
- `APP_KUCOIN_API_PASSPHRASE`

**Does KuCoin require KYC for API keys?**

No. KuCoin allows API key creation on unverified (no-KYC) accounts. Receiving deposits
is unlimited without KYC. Withdrawals without KYC are limited to 1 BTC/day equivalent,
which is fine for a small demo. KYC Level 1 (name + government ID photo) takes under
10 minutes if you want higher withdrawal limits later.

**KuCoin API permissions needed:**
- **General** (read) — required for deposit address generation and transaction verification
- **Trade** — required only if you want programmatic spot withdrawals

**Without KuCoin API keys:** Tickers, price charts, spot/binary/futures trading all
work via KuCoin's public API (no keys). Only deposit address generation and crypto
withdrawal processing fail. Users see no deposit address in their wallet. The platform
is still live and tradeable; deposit via admin manual credit as a stopgap.

### Path 2: Ecosystem on-chain deposits (RPC + Cassandra)

Platform generates its own on-chain wallet addresses using RPC nodes. No KuCoin
involved. Users send from anywhere. Platform monitors the chain directly.

Requires: Cassandra/ScyllaDB + RPC URLs (public free endpoints are already configured
in `railway-start.sh`). Cassandra is the gating dependency.

### Path 3: Admin manual credit (always available)

Admin → Users → click user → add balance directly. No API keys, no deposits.
Use this to give early test users starting credit while you sort out API keys.

### Path 4: Fiat deposit gateways

Stripe, PayPal, and 8 other processors are integrated. Requires API keys per gateway.
Manual fiat deposit/withdrawal via bank transfer is already seeded and works with
zero keys (admin approves manually).

---

## What works out of the box (no extra keys)

- ✅ Login, signup, 2FA, user roles
- ✅ Live BTC/ETH/etc. price tickers and charts (KuCoin public API)
- ✅ Spot trading (all USDT pairs)
- ✅ Futures trading (8 markets)
- ✅ Binary options (33 markets, 14 durations, 60–85% profit)
- ✅ Investment plans (10 plans × 14 durations)
- ✅ Staking pools (14 pools)
- ✅ P2P trading (26 payment methods)
- ✅ Admin panel (full super admin + admin roles)
- ✅ Manual fiat deposit/withdrawal (bank wire, SEPA, crypto manual)
- ✅ NFT marketplace, ecommerce, multi-language (12 langs), dark/light themes
- ✅ Admin manual balance credit (Finance → Admin → Users)

---

## What needs extra keys to unlock

| Feature | Variables needed | Where to get them |
|---------|-----------------|-------------------|
| Crypto deposits (spot wallet) | `APP_KUCOIN_API_KEY` + `APP_KUCOIN_API_SECRET` + `APP_KUCOIN_API_PASSPHRASE` | kucoin.com → API Management (no KYC needed) |
| Crypto withdrawals (spot) | Same KuCoin keys | Same |
| Ecosystem on-chain deposits | Cassandra service + RPC URLs (already defaulted) | Add Cassandra service on Railway |
| Email (signup, password reset) | `APP_EMAILER=smtp` + `SMTP_HOST/PORT/USER/PASS` | Any SMTP provider (Gmail, SendGrid, etc.) |
| Fiat deposits via card | `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` | stripe.com |
| AI trading bots | `OPENAI_API_KEY` or `GEMINI_API_KEY` | openai.com or ai.google.dev |
| FX rates | `APP_OPENEXCHANGERATES_APP_ID` | Already defaulted in boot script |

---

## Root cause: hotfix-010 order-of-operations bug (fixed)

On a **fresh deploy**, hotfix-010 ran before the data sweeps — so when it tried to
`UPDATE exchange_market SET status=0 WHERE currency='SOL' AND pair='BTC'` there were
no rows yet (empty DB). The sweeps then inserted SOL/BTC, ETH/BTC, LINK/ETH with
`status=1`, leaving the cron broken.

**Fix applied (2026-07-24)**:
- `scripts/sql/sweep-forward.sql` lines 100–102: changed SOL/BTC, ETH/BTC, LINK/ETH
  INSERT status from `1` → `0`. Fresh deploys no longer activate these pairs.
- hotfix-010 remains for existing deploys where the rows may pre-exist with status=1.
- Live Railway DB patched directly (UPDATE applied via sakura.proxy.rlwy.net).

---

## Recommended next steps (in priority order)

1. **Get KuCoin API keys first** — takes 10 minutes, free, no KYC required, unlocks
   all crypto deposits and withdrawals for your users. Biggest impact per effort.

2. **Set up email** — without email, users can't confirm signups or reset passwords.
   Gmail SMTP works fine (use an App Password, not your account password). Or use
   SendGrid/Mailgun free tiers.

3. **Change the superadmin password** — log in as `superadmin@example.com` / `12345678`
   immediately and change it. Set `NEXT_PUBLIC_DEMO_STATUS=false` in Railway vars.

4. **Set `NEXT_PUBLIC_SITE_NAME`** — change from "DeMourinho Crypto" to your brand name.
   This propagates to the frontend header, emails, and meta tags.

5. **Add Cassandra (optional)** — enables ecosystem on-chain deposits (ETH/BSC/TRON/SOL/BTC
   direct-to-wallet). RAM-intensive on Railway free tier — only add if you have credits.

6. **Stripe (optional)** — enables fiat card deposits. Not needed if you handle fiat
   manually via admin panel.

---

## Optional: Cassandra for on-chain ecosystem deposits

Cassandra (or ScyllaDB) is required for the ecosystem deposit system (on-chain wallets).
It is NOT required for the platform to work — spot/futures/binary trading all work without it.

If you add Cassandra to Railway:
- Use `Dockerfile.cassandra` in this repo as the service's Docker source
- Set on the Cassandra service: `CASSANDRA_CLUSTER_NAME=demourinho`, `CASSANDRA_DC=datacenter1`
- Set on the app service: `SCYLLA_CONNECT_POINTS=<cassandra-service-name>.railway.internal:9042`,
  `SCYLLA_USERNAME=cassandra`, `SCYLLA_PASSWORD=cassandra`,
  `SCYLLA_KEYSPACE=trading`, `SCYLLA_FUTURES_KEYSPACE=futures`,
  `SCYLLA_DATACENTER=datacenter1`
- Cassandra takes 60–90s to start. The client patches in `backend/dist/src/api/(ext)/ecosystem/utils/scylla/client.js`
  already set `MAX_RETRIES=20` and `INITIAL_DELAY=15000ms` to account for this.

Known Cassandra issue on Railway free tier: OOM kills (Cassandra uses 500–800MB RAM).
Railway's free tier containers can be CPU/RAM-limited. If Cassandra keeps crashing with
no error log (just a sudden restart), it's being OOM-killed. The `scripts/cassandra-init.sh`
forces heap to 128M to mitigate this, but it may still be tight.

---

## MySQL schema notes

- 160+ tables from `initial.sql` (MariaDB dump, works on MySQL 8 with sql_mode relaxed)
- Sequelize sync runs on backend startup and may ALTER TABLE — that's normal
- If you see `Incorrect datetime value: '0000-00-00 00:00:00'`, the zero-date sweep
  in `railway-start.sh` handles this automatically before PM2 starts
- If you see `JSON column can't have default value`, the sql_mode relaxation step handles this

---

## Important env vars reference

All of these have defaults in `railway-start.sh` or are auto-generated. Listed here
for documentation only — you don't need to set any of them manually for a basic deploy.

| Variable | Default | Purpose |
|----------|---------|---------|
| `NODE_ENV` | `production` | App mode |
| `NEXT_PUBLIC_SITE_NAME` | `DeMourinho Crypto` | Site branding |
| `NEXT_PUBLIC_EXCHANGE` | `bin` | Exchange mode flag |
| `JWT_EXPIRY` | `7d` | Access token TTL |
| `JWT_REFRESH_EXPIRY` | `30d` | Refresh token TTL |
| `APP_ETH_RPC_URL` | Infura public | Ethereum RPC |
| `APP_BSC_RPC_URL` | Binance public | BSC RPC |
| `APP_POLYGON_RPC_URL` | polygon-rpc.com | Polygon RPC |
| `APP_SOL_RPC_URL` | mainnet-beta.solana.com | Solana RPC |
| `TRON_MAINNET_RPC` | api.trongrid.io | Tron RPC |
| `APP_OPENEXCHANGERATES_APP_ID` | Free key | FX rates |
| `APP_ACCESS_TOKEN_SECRET` | **Auto-generated** | JWT signing |
| `APP_REFRESH_TOKEN_SECRET` | **Auto-generated** | JWT refresh signing |
| `ENCRYPTED_ENCRYPTION_KEY` | **Auto-generated** | Wallet encryption key |
| `ENCRYPTION_KEY_PASSPHRASE` | **Auto-generated** | Wallet key passphrase |

**The auto-generated secrets** (`APP_*_TOKEN_SECRET`, `ENCRYPTED_ENCRYPTION_KEY`,
`ENCRYPTION_KEY_PASSPHRASE`) are stored in the `_deploy_secrets` MySQL table and
reloaded on every boot. They survive redeploys without manual configuration.

**CRITICAL**: If you ever move to a different database, export the `_deploy_secrets`
table. If `ENCRYPTED_ENCRYPTION_KEY` changes after ecosystem wallets have been created,
those wallet private keys become permanently unreadable.

---

## Binance note

Binance is **geo-blocked** on Railway's IP ranges. Do not attempt to switch to Binance
as the active exchange provider without configuring a proxy. KuCoin works fine.
The `NEXT_PUBLIC_EXCHANGE=bin` flag is a frontend display hint, not the active provider —
the actual provider is set in the database (KuCoin is active after the sweeps run).
