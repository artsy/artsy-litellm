# artsy-litellm

This repository configures and deploys Artsy's [LiteLLM](https://github.com/BerriAI/litellm) gateway. Apps call LLM providers through it, each with its own key, rate limits, budget and spend tracking.

- **State**: Development
- **Staging**: https://litellm.stg.artsy.systems 🔒 (admin UI, VPN only). In-cluster: `http://artsy-litellm-web-internal.default.svc.cluster.local:4000`
- **Production**: not deployed yet
- **GitHub**: https://github.com/artsy/artsy-litellm
- **[CircleCI](https://circleci.com/gh/artsy/artsy-litellm)**: Merged PRs to artsy/artsy-litellm#main are automatically deployed to staging.

## How it runs

- The image is LiteLLM's published image (`Dockerfile`, pinned by digest) plus `config.yaml` and a script that loads secrets from fortress.
- Every pod is identical. Jobs that must run once (budget resets, spend log cleanup) take a Redis lock.
- Database migrations run once per deploy in Hokusai's `pre-deploy` hook. Pods have `DISABLE_SCHEMA_UPDATE=true`.
- Redis: shared-staging, on our own DB number (see Notion "Shared Redis DB Assignments"). The response cache stays off: on a shared Redis its flush endpoint would empty every app's data.

## Configuration

| What | Where | Change needs |
| --- | --- | --- |
| Secrets (`DATABASE_URL`, `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `ANTHROPIC_API_KEY`) | Vault `kubernetes/apps/artsy-litellm`, loaded by fortress | Pod restart |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB` | Config map `artsy-litellm-environment` (`hokusai staging env set`). Never set `REDIS_URL`; it overrides `REDIS_DB`. | Pod restart |
| Gateway settings and the default model | `config.yaml` | PR and deploy |
| Other models, keys, teams, budgets, limits | Admin UI | Nothing; pods pick it up within about 30 seconds |

`LITELLM_SALT_KEY` encrypts credentials stored in the database. Never change it after the first start.

## First deploy prerequisites

The first deploy fails unless all of these exist:

1. ECR repository `artsy-litellm` (artsy/infrastructure `terraform/shared/ecr.tf`)
2. Vault policy for `artsy-litellm` (artsy/infrastructure `terraform/staging/vault/k8s_apps_role_policy.tf`) and the secrets at `kubernetes/apps/artsy-litellm`
3. ServiceAccount `artsy-litellm` (artsy/substance `services/service-accounts-k8s-apps.yml`, applied manually to each cluster with `kubectl apply`)
4. A `litellm` database and user on staging-shared Postgres (`staging-shared-20210128`), with `DATABASE_URL` pointing at it
5. The config map. Current Hokusai has no `env create`, and `hokusai staging create` needs the image in ECR first, so create it with kubectl in the shape Hokusai expects:
   ```
   kubectl --context staging -n default create configmap artsy-litellm-environment \
     --from-literal=REDIS_HOST=<shared-staging endpoint> --from-literal=REDIS_PORT=6379 --from-literal=REDIS_DB=<n>
   kubectl --context staging -n default label configmap artsy-litellm-environment app=artsy-litellm
   ```
   After that, `hokusai staging env get` / `env set` work as usual.
6. The CircleCI project followed, using the `hokusai` context

## One-time database setup

LiteLLM's migrations deliberately leave two spend log indexes for operators to build online. Until they exist, pods log `prisma schema out of sync with db` at startup. After the first deploy, run once against the LiteLLM database:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_litellm_call_id_idx" ON "LiteLLM_SpendLogs"("litellm_call_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "LiteLLM_SpendLogs_api_key_startTime_idx" ON "LiteLLM_SpendLogs"("api_key", "startTime");
```

## Connecting an app

Apps using an Anthropic SDK need no code changes, only two env vars. The base URL depends on the SDK.

Vercel AI SDK (`@ai-sdk/anthropic`, used by Metaphysics) expects `/v1` in the base URL:

```
ANTHROPIC_BASE_URL=http://artsy-litellm-web-internal.default.svc.cluster.local:4000/v1
ANTHROPIC_API_KEY=<LiteLLM virtual key for the app>
```

Official Anthropic SDKs (`@anthropic-ai/sdk`, Python `anthropic`) add `/v1` themselves:

```
ANTHROPIC_BASE_URL=http://artsy-litellm-web-internal.default.svc.cluster.local:4000
ANTHROPIC_API_KEY=<LiteLLM virtual key for the app>
```

To roll back, unset `ANTHROPIC_BASE_URL` and restore the app's direct provider key.

## Development

```
export ANTHROPIC_API_KEY=<your key>   # optional, only for real model calls
hokusai dev start
```

The admin UI is at http://localhost:4000/ui (master key `sk-development`).

## Upgrading LiteLLM

Change the tag and digest in `Dockerfile`. Get the digest with:

```
docker buildx imagetools inspect ghcr.io/berriai/litellm:<version>
```

Read the release notes for migrations and config changes first.
