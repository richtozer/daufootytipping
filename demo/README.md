# Celebrity Dream League demo

This is a fictional AFL/NRL competition for development and store screenshots:
20 tippers (eight women), 12 combined rounds, seven completed rounds, a mixed
eighth round, two games in progress and future fixtures. Completed scores and matchups
come from the 2026 season. The 2022-2025 seasons are included unshifted as past
competitions, so head-to-head history shows real results; only Daisy has past
tips, which lights up the "tipped correctly" shading on her screens. Dates, identities, accounts and tips are
synthetic. No real tipper data or production credentials are copied.

## Start it

Stop any existing local backend session first. Then, from the repository root:

```sh
bash scripts/start_local_backend.sh --demo
```

For the Android emulator, use `--demo --android` so avatar URLs use `10.0.2.2`.
For iOS Simulator and Chrome the default `localhost` is correct. Physical phones
are not configured by this shortcut.

The command generates dates relative to startup, writes an emulator import
folder (`emulator/demo/export/`), serves local avatars, and starts Auth/RTDB/
Firestore/Functions with `--import`. Imported data is in place before the
Functions emulator registers its triggers, so loading fires none; writing the
same data after startup would fire one or two triggers per tip, which the
emulator refuses in bulk and which can overload the machine.

The emulators start from a generated, gitignored `firebase.demo.json` that
points the database at the final R2 rules. The deployable rules file and the
production admin allowlist are untouched.

Auth emulator tokens are unsigned, so the demo start sets
`FIREBASE_DEBUG_FEATURES={"skipTokenVerification":true}` for the emulator
process only. The Dart server refuses that switch outside the Functions
emulator, and `deploy-functions.sh` refuses to deploy while it is set.

The callables still enforce App Check. A simulator whose App Check debug token
is not registered with the Firebase project sends a placeholder token, and every
callable (device tokens, alias changes, sign-up linking) returns 401. Reading and
tipping go straight to the database, so they still work. Register the token the
app prints at startup (`Firebase App Check debug token: ...` in the device log)
in the Firebase console, or use a simulator that already has one.

Launch **App: Demo emulators (selected device)** or **App: Demo emulators
(Chrome)**. These add `--dart-define=USE_AUTH_EMULATOR=true`; the ordinary
local launches keep using real Firebase Auth and cannot sign in to demo
accounts. Fully restart the app after changing backend modes. Sign out of any
previous account and use the email/password form.

Each demo start creates the Auth accounts afresh, so a simulator's saved sign-in
from an earlier start can no longer refresh its token. Once its last token
expires (within an hour), the database never connects and startup ends on
"Can't reach the server". Clear that simulator's saved sign-in and sign in
again (its App Check debug token is stored elsewhere and is kept):

```sh
xcrun simctl keychain <simulator-udid> reset
```

The demo accounts:

- Account: `daisy@demo.example.test`
- Password: read `emulator/demo/credentials.json` (randomly generated locally).

Every roster entry has a verified email/password account. See `auth-users.json`
for the other addresses; they share the locally generated demo password.
All are ordinary tippers. Admin operations remain available through Emulator UI;
no fake user is added to the production admin allowlist.

## Main artifacts

Generated files live in the existing gitignored `emulator/demo/` directory:

- `export/`: the emulator import folder (database plus Auth accounts).
- `competition.json`: the same RTDB root JSON, including identity indexes, tips,
  and backend round/game statistics. The two in-progress games have no live
  scores, so the stats screens show no live-score warning.
- `auth-users.json`: matching synthetic account definitions (no passwords).
- `credentials.json`: local password; never commit or include in store assets.
- `manifest.json`: anchor time, counts and suggested screenshot account.
- `fixtures/`: shifted feeds for local fixture downloads.

To reproduce the November 2026 snapshot without starting emulators:

```sh
node scripts/demo/generate.mjs --anchor 2026-11-10T09:00:00Z
```

Omit `--anchor` to use now. Restart the demo backend when returning for another
screenshot session; it generates and imports a fresh snapshot. This is a timestamped snapshot, not a frozen app clock or a
live match simulator: upcoming games eventually start, and in-progress games
never get a score. Do not reseed while making test edits you wish to
keep; it replaces the demo dataset and resets demo accounts.

`node scripts/demo/serve.mjs` serves the avatars and local fixture feeds; the
demo start runs it for you. No image hosting account is needed.

## Source and avatar assets

`fixtures-2026.json` and `history.json` (2022-2025) are public-fields-only
fixture extracts. The generator does not need the original production export.
To refresh both deliberately:

```sh
node scripts/demo/generate.mjs --extract-source path/to/local-2026-export.json
```

Only team names/logos, game metadata/results and combined-round dates are read
into the output. Scoring is calculated with the shared Dart production models
and `ScoringCalculator`, including default Away tips for missing started games.

The roster uses seven generated caricatures, seven real photographs and six
normal initials fallbacks. Initials derive from the displayed alias, so the
initials accounts use two-word names. The caricatures were made with the built-in
image_gen tool; exact prompts are in `avatars/generation-prompts.json`.

Photograph authors, source pages and licences are in `avatars/photo-credits.json`.
Preserve the required credits/licence links when publishing imagery containing
those photos. Photo copyright licences do not assert celebrity endorsement.
Suggested screenshot caption: **“Fictional demo competition. Celebrity-inspired
profiles; no affiliation or endorsement.”**

## Validation

```sh
node --test scripts/demo/generate.test.mjs
bash scripts/demo/validate_emulators.sh
flutter analyze --no-pub
flutter test --no-pub test/services/linked_tipper_resolver_test.dart test/view_models/sign_in_link_controller_test.dart packages/dau_shared/test/scoring_calculator_test.dart
```

The Node tests check identity links, public/private separation, round membership,
kickoff/tip timing, historical-score provenance, past seasons, the import
folder, repeatability and local assets. `validate_emulators.sh` starts only the
Auth and Database emulators, on separate ports, from the import folder and
checks sign-ins, rules and the imported data.
