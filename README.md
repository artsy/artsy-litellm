# artsy-litellm

Artsy's [LiteLLM](https://github.com/BerriAI/litellm) gateway. Apps call LLM providers through it, each with its own key, limits, budget and spend tracking.

- **Staging**: https://litellm.stg.artsy.systems (admin UI, VPN)
- **Production**: https://litellm.prd.artsy.systems (admin UI, VPN)
- **In-cluster**: `http://artsy-litellm-web-internal.default.svc.cluster.local:4000`
- **Deploys**: `main` → staging. `release` → production, after approval in Horizon.

## Configuration

- Gateway settings and the default model: `config.yaml`
- Models, keys, teams, budgets: admin UI. No deploy needed.
- Secrets (`DATABASE_URL`, `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `ANTHROPIC_API_KEY`, `PHOENIX_API_KEY`, and in production `REDIS_PASSWORD`): Vault, one secret per variable under `kubernetes/apps/artsy-litellm/`, loaded by fortress. Changing one needs a pod restart.
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`: config map `artsy-litellm-environment`. Production also sets `REDIS_SSL=true`. Staging leaves `REDIS_SSL` and `REDIS_PASSWORD` unset (no TLS, no password). Never set `REDIS_URL`; it overrides `REDIS_DB`.
- Redis: staging uses shared-staging, on our own DB number (see Notion "Shared Redis DB Assignments"). Production has its own ElastiCache for Valkey group `artsy-litellm-production` (DB 0, TLS, auth token).

Response caching stays off: on staging's shared Redis its flush would wipe every app's data.

## Connecting an app

```
ANTHROPIC_BASE_URL=http://artsy-litellm-web-internal.default.svc.cluster.local:4000
ANTHROPIC_API_KEY=<LiteLLM virtual key>
```

The Vercel AI SDK (`@ai-sdk/anthropic`, used by Metaphysics) needs `/v1` at the end of the base URL. To roll back, unset `ANTHROPIC_BASE_URL` and restore the direct provider key.

## Tracing

Every call is traced to [Phoenix](https://github.com/artsy/artsy-phoenix). Set the project in the key's Metadata:

```json
{ "phoenix_project_name": "<project>" }
```

- Without it, traces go to `PHOENIX_PROJECT_NAME` (`litellm` on staging and production).
- Keys can't opt out (that's Enterprise only). Apps with their own tracing, like Metaphysics, get their LLM calls traced twice, so use a separate project for their key.
- Don't add the UI's "Arize" integration. It sends to Arize's cloud, not our Phoenix.
- Phoenix has auth on, so it needs an API key (Settings > API Keys in that environment's Phoenix), stored in Vault as `PHOENIX_API_KEY`. Without it, Phoenix answers `POST /v1/traces` with 401. LiteLLM logs nothing, so check Phoenix's log (`kubectl logs deploy/artsy-phoenix-web | grep v1/traces`) for a 200. Restart the pods after changing the key.

## First deploy

The first deploy to each environment needs:

- the ECR repo and the Vault policy (artsy/infrastructure), and the Vault secrets
- the `artsy-litellm` ServiceAccount (artsy/substance)
- a `litellm` database
- the config map, created with `kubectl` because Hokusai can't create it:

```
kubectl --context staging create configmap artsy-litellm-environment --from-literal=REDIS_HOST=<host> --from-literal=REDIS_PORT=6379 --from-literal=REDIS_DB=<n>
kubectl --context staging label configmap artsy-litellm-environment app=artsy-litellm
```

Production uses `--context production` and also sets `REDIS_SSL=true`, with `REDIS_DB=0` and the host of the `artsy-litellm-production` group. `REDIS_PASSWORD` goes in Vault.

Both environments also set `PHOENIX_COLLECTOR_HTTP_ENDPOINT` (`http://artsy-phoenix-web-internal.default.svc.cluster.local:6006/v1/traces`) and `PHOENIX_PROJECT_NAME` (`litellm`) in the config map, for example with `kubectl patch configmap artsy-litellm-environment --type merge -p '{"data":{...}}'`. The Phoenix API key goes in Vault as `PHOENIX_API_KEY` (see Tracing).

LiteLLM 1.106 and later builds the two request-log indexes itself after the migrations, so there is nothing to run. On older versions (1.104.x and earlier), create them by hand as the `litellm` user after the first deploy, or pods log `prisma schema out of sync`:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_litellm_call_id_idx" ON "LiteLLM_SpendLogs"("litellm_call_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_api_key_startTime_idx" ON "LiteLLM_SpendLogs"("api_key", "startTime");
```

## First admin

`config.yaml` disables the admin UI login with the master key (`disable_env_credential_login: true`), so the first admin has to be created through the API with the master key (`Authorization: Bearer <master key>`):

1. In a fresh database, create the proxy admin row first: `POST /user/new` with `{"user_id":"default_user_id","user_role":"proxy_admin","auto_create_key":false}`. Without it, `/invitation/new` fails with a foreign key error that blames `user_id`.
2. Create your user: `POST /user/new` with `{"user_email":"<email>","user_role":"proxy_admin","auto_create_key":false}`.
3. Create an invitation: `POST /invitation/new` with `{"user_id":"<id from step 2>"}`, then open `/ui?invitation_id=<id>` to set your password (12 or more characters, with upper and lower case letters, a number and a special character).

## Development

```
export ANTHROPIC_API_KEY=<your key>   # optional, for real model calls
hokusai dev start
```

The API is at http://localhost:4000, with master key `sk-development`.

## Upgrading

Update the tag and digest in `Dockerfile`, then check the release notes for migrations:

```
docker buildx imagetools inspect ghcr.io/berriai/litellm:<version>
```
