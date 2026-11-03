# LiteLLM and Phoenix, end to end

How an app gets its LLM calls, its own steps (agent turns, tool calls) and user feedback into [Phoenix](https://github.com/artsy/artsy-phoenix), using only its LiteLLM key. The app never talks to Phoenix directly.

```
App ──(LiteLLM key)──► LiteLLM ──► Phoenix
  • LLM calls                       → traced by LiteLLM (tokens, cost)
  • the app's own spans (JSON)      → /phoenix/v1/projects/<project>/spans
  • 👍/👎 feedback                  → /phoenix/v1/trace_annotations
```

An app that only calls the LLM needs steps 1, 3 and 4. Its own spans and feedback are optional.

## 1. Connect LiteLLM to Phoenix (once per environment)

1. Phoenix is running in the environment (see artsy-phoenix).
2. In that environment's Phoenix, go to **Settings > API Keys** and create a key.
3. Put it in Vault as `PHOENIX_API_KEY` under `kubernetes/apps/artsy-litellm/`.
4. Set these in the `artsy-litellm-environment` config map:
   - `PHOENIX_COLLECTOR_HTTP_ENDPOINT=http://artsy-phoenix-web-internal.default.svc.cluster.local:6006/v1/traces`
   - `PHOENIX_PROJECT_NAME=litellm` (where traces go when a key names no project)
5. Restart the LiteLLM pods.
6. Check: make any call through LiteLLM. It shows up in Phoenix's `litellm` project.

## 2. Add the app's pass-through routes (only for its own spans or feedback)

Routes are defined in [`config.yaml`](../config.yaml) under `pass_through_endpoints` and ship with every deploy. LiteLLM adds the Phoenix key, so the app only needs its LiteLLM key.

- `/phoenix/v1/trace_annotations`: feedback on a trace. Already there, shared by every app.
- `/phoenix/v1/projects/<new_app>/spans`: the app's own spans. Add one per app: copy an existing spans route and change the project in both `path` and `target`.

## 3. Create the app's key

1. In the LiteLLM admin UI, create a virtual key for the app.
2. In the key's **Metadata** field, set its Phoenix project and, if it uses them, the routes from step 2:

   ```json
   {
     "phoenix_project_name": "<new_app>",
     "allowed_passthrough_routes": [
       "/phoenix/v1/trace_annotations",
       "/phoenix/v1/projects/<new_app>/spans"
     ]
   }
   ```

   The UI says "Allowed Pass Through Routes" is a Premium feature. Ignore that and use the Metadata field: it works.

3. `phoenix_project_name` must be the same project as the spans route, or each trace gets split across two projects.

## 4. Point the app at LiteLLM

Set:

```
LITELLM_BASE_URL=<the LiteLLM base URL>
LITELLM_API_KEY=<the key from step 3>
```

- In the cluster: `http://artsy-litellm-web-internal.default.svc.cluster.local:4000`
- On your laptop: `https://litellm.stg.artsy.systems`, on VPN. The in-cluster address only works inside Kubernetes.

That's enough for the app's LLM calls to show up in its project.

## 5. Send the app's own spans and feedback (optional)

- **One trace per unit of work**, e.g. one agent turn. The app picks a trace ID and a root span ID, and sends `traceparent: 00-<trace id>-<root span id>-01` on every LLM call in it. LiteLLM then nests its LLM spans under the app's root.
- **The app's spans** go to `POST <LITELLM_BASE_URL>/phoenix/v1/projects/<new_app>/spans` as JSON (`{"data": [spans]}`), with the same trace ID. Phoenix's OTLP endpoint can't be used: it only takes protobuf, and the pass-through sends JSON.
- **Feedback** goes to `POST <LITELLM_BASE_URL>/phoenix/v1/trace_annotations` with the trace ID, a name (e.g. `user_feedback`), a label and score, and the user as `identifier`. Annotating again with the same name and identifier replaces the earlier one.
- **Every pass-through call has `"no-log": true` in its body.** Otherwise LiteLLM traces the call itself, and Phoenix gets a stray trace. Phoenix ignores the field.
- Authenticate with `Authorization: Bearer <LITELLM_API_KEY>`.

## Example: Metaphysics's Art Assistant

- **Project:** `metaphysics`. Routes `/phoenix/v1/trace_annotations` and `/phoenix/v1/projects/metaphysics/spans`.
- **Settings:** `LITELLM_BASE_URL` and `LITELLM_API_KEY`. With both set, the assistant goes through LiteLLM and Phoenix. Unset `LITELLM_BASE_URL` to go back to Anthropic directly, traced to Sentry.
- **What it sends:** one trace per assistant turn. The `ai_agent_turn` root holds the question, the answer (cards and suggested replies included) and the session (`session.id` = the conversation). Each `query_artsy` tool call is a child span, next to LiteLLM's LLM calls. The trace ID goes back to Eigen as `feedbackID`.
- **Feedback:** Eigen's 👍/👎 calls Metaphysics's `createAIAgentFeedback`, which records `user_feedback` (1 or 0) on the turn's trace.
- **Code:** `src/lib/apis/phoenix.ts` (pass-through calls) and `src/schema/v2/ai/agent/turnTrace.ts` (the turn's spans).

To check it:

1. Ask the Art Assistant something.
2. In Phoenix, open the `metaphysics` project, then **Sessions**. The conversation has one turn per question, each with its tool calls and LLM calls inside.
3. Tap 👍 or 👎 under the answer. The turn shows `user_feedback` (1 for 👍, 0 for 👎). Voting again replaces the vote.

## If something's wrong

| What you see | Why | Fix |
|---|---|---|
| No traces at all | Phoenix rejects LiteLLM's key | Check `PHOENIX_API_KEY` (step 1). `kubectl logs deploy/artsy-phoenix-web \| grep v1/traces` shows 401s. |
| App logs `ENOTFOUND artsy-litellm-web-internal…` | In-cluster address used outside Kubernetes | Use `https://litellm.stg.artsy.systems` locally (step 4) |
| Pass-through call gets 401 or 403 | Route missing from the key | Add it to `allowed_passthrough_routes` (step 3) |
| Spans call gets 415 | Sent as OTLP/protobuf | Send JSON to the spans route (step 5) |
| LLM calls and the app's spans are in separate traces | No `traceparent` on the LLM calls | Send it on every LLM call (step 5) |
| LLM calls and the app's spans are in different projects | Project names differ | Make `phoenix_project_name` match the spans route (step 3) |
| Extra `litellm_proxy_request` traces with feedback or spans as input | The app didn't send `"no-log": true` | Send it on every pass-through call (step 5) |
