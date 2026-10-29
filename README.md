# artsy-litellm

Artsy's [LiteLLM](https://github.com/BerriAI/litellm) gateway. Apps call LLM providers through it, each with its own key, limits, budget and spend tracking.

- **Staging**: https://litellm.stg.artsy.systems (admin UI, VPN)
- **Production**: not deployed yet
- **In-cluster**: `http://artsy-litellm-web-internal.default.svc.cluster.local:4000`
- **Deploys**: `main` → staging

## Configuration

- Gateway settings and the default model: `config.yaml`
- Models, keys, teams, budgets: admin UI. No deploy needed.

Response caching stays off: on the shared Redis its flush would wipe every app's data.

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

- Without it, traces go to `PHOENIX_PROJECT_NAME` (`litellm` on staging).
- Keys can't opt out (that's Enterprise only). Apps with their own tracing, like Metaphysics, get their LLM calls traced twice, so use a separate project for their key.
- Don't add the UI's "Arize" integration. It sends to Arize's cloud, not our Phoenix.

## First deploy

The first deploy needs:

- the ECR repo and the Vault policy and secrets (artsy/infrastructure)
- the `artsy-litellm` ServiceAccount (artsy/substance)
- a `litellm` database
- the config map, created with `kubectl` because Hokusai can't create it:

```
kubectl --context staging create configmap artsy-litellm-environment --from-literal=REDIS_HOST=<host> --from-literal=REDIS_PORT=6379 --from-literal=REDIS_DB=<n>
kubectl --context staging label configmap artsy-litellm-environment app=artsy-litellm
```

After the first deploy, create two indexes that LiteLLM's migrations leave out. Until they exist, pods log `prisma schema out of sync`:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_litellm_call_id_idx" ON "LiteLLM_SpendLogs"("litellm_call_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_api_key_startTime_idx" ON "LiteLLM_SpendLogs"("api_key", "startTime");
```

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
