# rules_test

Automated checks for the Realtime Database rules work (see `../DESIGN-database-rules.md` and
`../DESIGN-database-rules-phase3.md`).

```bash
npm test            # everything that needs only the Database emulator (demo project)
npm run test:unit   # no emulator needed: boundary canaries, generator, audit, deploy scripts, safety checks
npm run test:dart   # the Dart protocol spikes against the Database emulator
npm run test:live   # the live CLI paths against the Auth + Database emulators (see "Not run")
```

Every npm script runs through `support/isolated.sh`, an operating-system boundary. Spawning tests
refuse to run without it. Run the tests through npm, not with a bare `node --test`.

## Test safety

An earlier version of a deploy-script test ran a real `firebase deploy` against the production
project (phase 3 report, section 8). Four layers now stand between a test and production. **Only the
first is a real boundary**; the others are checks and conventions that make mistakes fail early.

1. **OS boundary (`support/isolated.sh`, macOS `sandbox-exec`).** For every process the npm test
   commands start (Node, Bash, native tools, Dart, the Java emulators, the Firebase launcher): no
   outbound network except loopback and unix sockets; the usual credential stores unreadable; an
   explicit minimal environment with an empty `XDG_CONFIG_HOME`. It **fails closed** where no
   boundary exists (on Linux, run inside a container with no network and no credentials and declare
   `OS_BOUNDARY=1`). `os_boundary.test.mjs` proves it, from inside, with non-Node processes, and
   refuses to attempt any external connection until the OS has first answered `EPERM` to a connect
   to 192.0.2.1 (a documentation address that is never routed).
2. **Fail-closed gating.** `sandboxEnv()` throws unless the runner declared the boundary.
3. **Node preload (`support/no_production.mjs`).** Refuses non-loopback connections and DNS in Node
   (validated loopback IPs or exactly `localhost`) and refuses `firebase`/`gcloud` unless the file is
   byte-identical to the checked-in stub (`support/firebase_stub.sh`, by SHA-256) at the exact path in
   `NO_PRODUCTION_STUB`. It does not see Bash, native tools, Dart or Java. It is not the safety
   mechanism.
4. **Script conventions.** Spawned scripts get `sandboxEnv(dir)` (never `process.env`): an empty
   `HOME`, no credentials, a PATH of only the sandbox bin plus `/usr/bin:/bin`, `FIREBASE_BIN` naming
   the stub, a `demo-` project. The stub refuses any deploy that is not aimed at an explicit `demo-`
   project. Sandbox repositories never copy the repo's `.firebaserc`. The deploy scripts require an
   explicit `--project`, compare it exactly, and never prepend a user npm bin when a firebase is
   already resolvable.

Rules enforced by scan (`safety.test.mjs`): no test names the production project; none passes
`process.env` to a spawned process; every spawning test uses `sandboxEnv`; the npm scripts use the
runner, the preload and `demo-` projects only. The emulator launcher reads the dedicated
`rules_test/firebase.json`, never the repository's.

**Limits.** The boundary covers what the npm scripts launch, not your shell or `npm` itself, and it
allows loopback and unix sockets (so it does not stop talking to other local services). Passing these
checks proves the cases tested, not that every other path is impossible.

## Real-client smoke test

`smoke/` runs the released app through its own UI against the emulators with the R1 rules, inside the
same boundary. It is a separate, slower, on-demand check, not part of `npm test`; see
`smoke/README.md` for how to run it, what is patched, and what it cannot cover.

## Not run

`npm run test:live` is isolated as above but should not be run until its isolation has been reviewed
by the repository owner.
