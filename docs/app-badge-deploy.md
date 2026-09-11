# Outstanding Tips App Badge Deploy Runbook

This runbook covers the server-driven iOS and Android outstanding-tips badge.
The feature is limited to paid, non-anonymous tippers and does not persist badge
state in RTDB.

## Safety Model

Server sends are disabled unless this RTDB value is exactly `true`:

```text
/AppConfig/outstandingTipsPushEnabled
```

Leave the key absent or `false` while deploying and validating the client and
server components. The client-side badge calculation continues to work while
server sends are disabled.

The `app-badge-count` Dart endpoint is an internal TypeScript-to-Dart endpoint.
It uses a dedicated `x-app-badge-secret` header rather than App Check because
its callers are backend functions, not app clients. Its generated HTTPS trigger
is publicly invokable at the Cloud Run IAM layer so those functions can reach
it, while the shared secret remains the application-level authorization check.

## Required Ignored Runtime Configuration

Do not commit actual URLs or secret values. Both `.env` files below are ignored.

Add to `functions_dart/.env`:

```text
APP_BADGE_COMMAND_SECRET=<shared app-badge secret>
```

After deploying the Dart codebase once, add to `functions/.env`:

```text
APP_BADGE_COUNT_URL=<deployed app-badge-count URL>
APP_BADGE_COMMAND_SECRET=<same shared app-badge secret>
```

Use the exact `run.app` Function URL printed by the Dart deployment. Do not
substitute a `cloudfunctions.net` URL unless Firebase explicitly reports one for
the deployed function.

The code also accepts `DART_APP_BADGE_COUNT_URL` and
`DART_APP_BADGE_COMMAND_SECRET`, but the `APP_BADGE_*` names are preferred.

## Rollout Order

1. Keep `/AppConfig/outstandingTipsPushEnabled` absent or `false`.
2. Release and verify the client build on iOS and Android. This ensures devices
   have the background-capable badge plugin before any server messages arrive.
3. Configure `APP_BADGE_COMMAND_SECRET` in `functions_dart/.env`.
4. Build and deploy the Dart functions, then copy the deployed
   `app-badge-count` URL into `functions/.env` as `APP_BADGE_COUNT_URL`.
5. Configure the same `APP_BADGE_COMMAND_SECRET` in `functions/.env`.
6. Run `bash scripts/check_backend_scoring_deploy_prereqs.sh`.
7. Deploy the TypeScript functions.
8. Smoke-test one paid account using a targeted tip submission while the flag
   remains off; confirm no server badge message is sent.
9. Set `/AppConfig/outstandingTipsPushEnabled` to `true` in the intended Firebase
   environment.
10. During an active round badge window, verify a tip submission, a kickoff
    transition, a new token registration, and a zero-count badge clear on both
    platforms. Between rounds, those events intentionally send nothing.

## Runtime Behaviour

- Tip writes recalculate and send the affected tipper immediately while a round
  badge window is active.
- Payment/anonymous eligibility changes recalculate that tipper and can send
  zero to clear an existing badge while a round badge window is active.
- New token registrations receive the current count on that token only while a
  round badge window is active.
- A one-minute boundary sweep starts a round's badges 48 hours before its
  effective stored start and updates all eligible tippers after each
  regular-comp kickoff. Generated round starts already include a three-hour
  buffer, so activation is normally about 51 hours before the first kickoff.
- Badge counts return to zero at the last kickoff and remain off until the next
  round enters its 48-hour activation window.
- An hourly reconciliation repairs missed or delayed events until the stored
  or admin-overridden round end. Generated round ends include a three-hour
  post-kickoff buffer, providing repeated zero-count clear attempts before
  reconciliation stops until the next round enters its activation window.
- FCM collapse identifiers keep only the newest pending badge update.
- Permanently invalid FCM tokens are removed from `/AllTippersTokens`.

To stop server-driven badge updates without rolling back code, set
`/AppConfig/outstandingTipsPushEnabled` to `false`.
