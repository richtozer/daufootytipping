# Temporary mechanisms

Anything built to be removed later is listed here with the condition that removes it. Add an entry in
the same change that adds the mechanism, and delete the entry in the change that removes it. The list is
reviewed each off-season.

A mechanism is temporary if it exists for a migration, a coexistence period, a platform limit or a
deferred upgrade, and the code would be simpler without it.

| Mechanism | Where | Remove when |
| --- | --- | --- |
| TypeScript Realtime Database and scheduled triggers that hand their work to the Dart HTTPS functions | `functions/src/` | Firebase supports Realtime Database and scheduled triggers for Dart functions in production. See `DESIGN-backend-scoring-wrapper-dart.md`. |
| Identity coexistence with 1.4.x clients: the `pilot` and `coexist` server modes, the legacy public tipper shape they write, the backfill tool, and the rulesets that precede R2 | `functions_dart/lib/identity/`, `functions_dart/bin/identity_backfill.dart`, `config/generated/` | The R2 cutover is complete and the minimum app version excludes 1.4.x. The exact files are confirmed at the cutover: see `DESIGN-database-rules-phase4.md`. |
| `deprecated_member_use: ignore` for the whole app | `analysis_options.yaml` | The dependencies named beside it in that file no longer bind to `package:flutter/material.dart` types, so the app can move to `material_ui`. |
| `prefer_initializing_formals: false` | `analysis_options.yaml` | The existing constructors are migrated. |
