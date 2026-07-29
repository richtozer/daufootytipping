# Local Development

This project has two intended local run modes:

- Local emulator mode: app uses local Firebase emulators and local Dart
  functions.
- Live Firebase mode: app uses real Firebase services and deployed functions.

Do not edit `functions/.env` or `functions_dart/.env` just to switch between
these modes. Those files can keep production-style URLs and secrets. When the
TypeScript Functions wrapper is running inside the Firebase emulator, it routes
backend scoring and scheduled fixture calls to the local Dart function endpoint
automatically.

## Start the local backend

The shortest way to remember this:

1. Press `Cmd+Shift+B`.
2. Paste the absolute path to the RTDB JSON snapshot.
3. Leave the terminal open.

`Cmd+Shift+B` runs the default VS Code build task, which is configured as
`Local Backend: start from RTDB snapshot`.

In VS Code, run one of these tasks:

- `Local Backend: start empty`
- `Local Backend: start from RTDB snapshot`

To run a task manually:

1. Press `Cmd+Shift+P`.
2. Type `Tasks: Run Task`.
3. Choose the task.

Use `Local Backend: start from RTDB snapshot` when testing from a production
Realtime Database export. Paste the absolute path to the JSON snapshot when
VS Code asks for it.

The backend task starts:

- TypeScript Functions build watcher
- native Dart Functions executable
- Firebase Functions emulator
- Realtime Database emulator
- Firestore emulator
- optional RTDB snapshot seed

Leave the backend terminal open while testing.

Expected local URLs:

- Emulator UI: `http://127.0.0.1:4000`
- Realtime Database: `http://127.0.0.1:8000`
- Functions: `http://127.0.0.1:9229`

## Run the app locally

After the backend task is running, choose the device in VS Code, then run:

- `App: Local emulators (selected device)`

For web testing, run:

- `App: Local emulators (Chrome)`

The app sets `USE_FIREBASE_EMULATORS=true`. On iOS and web it uses `localhost`;
on Android emulator it defaults to `10.0.2.2`.

## Run against live Firebase

No local backend is needed. Choose the device in VS Code, then run:

- `App: Live Firebase (selected device)`

For web testing, run:

- `App: Live Firebase (Chrome)`

This sets `USE_FIREBASE_EMULATORS=false`.

## Stop the local backend

In VS Code, run:

- `Local Backend: stop`

You can also press `Ctrl+C` in the backend terminal that started the emulators.

## Snapshot quick action

The existing macOS quick action can continue to call:

```bash
scripts/open_seeded_firebase_emulators_in_terminal.sh <path-to-rtdb-json>
```

That path now flows through `scripts/start_local_backend.sh`, so it starts the
same consolidated backend stack as the VS Code task.

## Backend scoring routing rule

When running in the Firebase Functions emulator:

- TypeScript tip/score/live-score triggers call
  `http://127.0.0.1:9229/dau-footy-tipping-f8a42/asia-southeast1/backend-scoring-command`
- TypeScript scheduled fixture download calls
  `http://127.0.0.1:9229/dau-footy-tipping-f8a42/asia-southeast1/scheduled-fixture-download`

Outside the emulator, the wrappers use the configured production env URLs.
