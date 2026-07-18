# Backend Scoring Deploy Runbook

This runbook covers the manual prerequisites for deploying the TypeScript RTDB
wrappers and Dart HTTPS scoring worker.

Do not commit actual secret values. The `.env` files referenced below are
ignored local files.

## Required Runtime Configuration

Backend scoring functions are deployed in `asia-southeast1` to match the RTDB
trigger region and avoid cross-region wrapper-to-worker calls.

`admin-fixture-download` is client/admin-app callable and enforces Firebase App
Check. Smoke test it from a valid app client or a debug-token-enabled simulator,
not with raw `curl`.

`backend-scoring-command` is an internal TypeScript-wrapper-to-Dart-worker HTTP
endpoint. It intentionally uses the shared `x-backend-scoring-secret` header
instead of App Check because callers are backend functions, not app clients.

The Dart worker requires:

```text
BACKEND_SCORING_COMMAND_SECRET=<shared secret>
```

The scheduled fixture-download wrapper additionally requires the deployed Dart
fixture endpoint URL:

```text
DART_FIXTURE_DOWNLOAD_COMMAND_URL=<deployed scheduled fixture download URL>
```

The TypeScript wrapper functions require:

```text
BACKEND_SCORING_COMMAND_URL=<deployed Dart backend-scoring-command URL>
BACKEND_SCORING_COMMAND_SECRET=<same shared secret>
```

The code also accepts `DART_BACKEND_SCORING_COMMAND_SECRET` and
`DART_BACKEND_SCORING_COMMAND_URL`, but prefer the `BACKEND_SCORING_*` names so
both runtimes use the same convention.

## First Deployment Sequence

The TypeScript wrappers need the Dart HTTPS URL, so the first deployment is a
two-step sequence.

1. Create `functions_dart/.env` with the shared secret:

   ```bash
   BACKEND_SCORING_COMMAND_SECRET=<shared secret>
   ```

2. Build and deploy Dart functions:

   ```bash
   bash scripts/build_dart_functions.sh linux
   firebase deploy --only functions:dart_functions
   ```

3. Find the deployed `backend-scoring-command` HTTPS URL in Firebase Console or
   with the Firebase/Google Cloud CLI.

4. Create `functions/.env` with the Dart URL and the same shared secret:

   ```bash
   BACKEND_SCORING_COMMAND_URL=<deployed backend-scoring-command URL>
   BACKEND_SCORING_COMMAND_SECRET=<same shared secret>
   ```

5. Verify local deploy prerequisite files:

   ```bash
   bash scripts/check_backend_scoring_deploy_prereqs.sh
   ```

6. Deploy TypeScript wrappers:

   ```bash
   firebase deploy --only functions:default
   ```

After this first deployment, the Dart HTTPS URL should remain stable. Future
deployments can deploy both codebases together if the env files remain present.

## Region Migration Notes

Changing function regions creates new functions in the new region rather than
renaming the old regional functions in place.

When moving backend scoring from `us-central1` to `asia-southeast1`:

1. Deploy Dart functions first:

   ```bash
   bash scripts/build_dart_functions.sh linux
   firebase deploy --only functions:dart_functions
   ```

2. Get the new `asia-southeast1` `backend-scoring-command` HTTPS URL.

3. Update ignored local runtime config:

   ```bash
   # functions/.env
   BACKEND_SCORING_COMMAND_URL=<asia-southeast1 backend-scoring-command URL>
   BACKEND_SCORING_COMMAND_SECRET=<same shared secret>
   ```

4. Deploy TypeScript wrappers:

   ```bash
   firebase deploy --only functions:default
   ```

5. Smoke test the new region before deleting old regional functions.

6. Delete old `us-central1` backend scoring functions only after the new
   `asia-southeast1` functions are verified:

   ```bash
   firebase functions:delete tipWrittenBackendScoring --region us-central1
   firebase functions:delete officialScoreWrittenBackendScoring --region us-central1
   firebase functions:delete liveScoreWrittenBackendScoring --region us-central1
   firebase functions:delete backend-scoring-command --region us-central1
   ```

7. If the admin fixture callable is used by clients/admin tools, update
   `/config/cloudFunctionsBaseURL` to the new `asia-southeast1` base URL before
   deleting the old `admin-fixture-download` function:

   ```bash
   firebase functions:delete admin-fixture-download --region us-central1
   ```

## Smoke Test

Use a non-production test comp first if available.

1. POST a manual admin rescore command directly to the Dart worker:

   ```bash
   curl -i -X POST "$BACKEND_SCORING_COMMAND_URL" \
     -H 'Content-Type: application/json' \
     -H "x-backend-scoring-secret: $BACKEND_SCORING_COMMAND_SECRET" \
     -d '{"command":{"commandType":"adminRescore","compKey":"<compKey>","sourceEventId":"manual-smoke-admin-rescore","sourcePath":"/admin/backendScoring/adminRescore","scopeKey":"comp:<compKey>/all_rounds/all_tippers","commandId":"manual-smoke-admin-rescore"}}'
   ```

2. Confirm the response is `200 OK` with `"status":"completed"`.

3. Confirm RTDB shadow branches update under:

   ```text
   /Stats/<compKey>/round_stats_backend_v1
   /Stats/<compKey>/game_stats_backend_v1
   /Stats/<compKey>/scoring_status
   /Stats/<compKey>/scoring_idempotency_backend_v1
   ```

4. Trigger one normal client tip write and confirm the TypeScript wrapper calls
   Dart by checking:

   ```text
   /Stats/<compKey>/scoring_idempotency_backend_v1/<eventId>
   /Stats/<compKey>/round_stats_backend_v1/<round>/<tipperId>
   ```

5. Run the comparison tool against an emulator copy when validating at scale:

   ```bash
   npm run compare:backend-scoring -- --comp-key <compKey>
   npm run compare:backend-scoring -- --comp-key <compKey> --type game-stats
   ```
