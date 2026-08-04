import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Message} from "firebase-admin/messaging";
import {
  buildOutstandingTipsBadgeMessage,
  handleKickoffAppBadgeSweep,
  handleTipWrittenAppBadge,
  handleTipperTokenCreatedAppBadge,
  syncAppBadges,
  tipperEligibilityChanged,
} from "./app_badge";

class FakeSnapshot {
  constructor(private readonly value: unknown) {}

  exists(): boolean {
    return this.value != null;
  }

  val(): unknown {
    return this.value;
  }
}

class FakeDatabase {
  public readonly removedPaths: string[] = [];
  public readonly readPaths: string[] = [];

  constructor(private readonly values: Record<string, unknown>) {}

  ref(path: string): {
    once(eventType: "value"): Promise<FakeSnapshot>;
    remove(): Promise<void>;
  } {
    return {
      once: async () => {
        this.readPaths.push(path);
        return new FakeSnapshot(this.values[path]);
      },
      remove: async () => {
        this.removedPaths.push(path);
      },
    };
  }
}

class FakeMessaging {
  public readonly batches: Message[][] = [];
  public responseCodes: Array<string | undefined> = [];

  async sendEach(messages: Message[]): Promise<{
    responses: Array<{
      success: boolean;
      error?: {code?: string};
    }>;
  }> {
    this.batches.push(messages);
    return {
      responses: messages.map((_, index) => {
        const code = this.responseCodes[index];
        return code == null ? {success: true} : {
          success: false,
          error: {code},
        };
      }),
    };
  }
}

const silentLogger = {
  log: (_message: string) => undefined,
  warn: (_message: string) => undefined,
  error: (_message: string) => undefined,
};

test("buildOutstandingTipsBadgeMessage targets Android and iOS", () => {
  const message = buildOutstandingTipsBadgeMessage(
    "token-1",
    3,
    "2026-08-04T12:00:00Z",
  );

  assert.equal("token" in message ? message.token : null, "token-1");
  assert.deepEqual(message.data, {
    type: "outstanding_tips_badge",
    count: "3",
    calculatedAt: "2026-08-04T12:00:00Z",
  });
  assert.equal(message.android?.priority, "high");
  assert.equal(message.android?.collapseKey, "outstanding-tips-badge");
  assert.equal(message.apns?.payload?.aps?.badge, 3);
  assert.equal(
    message.apns?.headers?.["apns-collapse-id"],
    "outstanding-tips-badge",
  );
});

test("syncAppBadges is inert while the runtime flag is absent", async () => {
  const db = new FakeDatabase({});
  const messaging = new FakeMessaging();
  let fetched = false;

  await syncAppBadges("comp-1", ["tipper-1"], {
    db,
    messaging,
    fetchImpl: async () => {
      fetched = true;
      return new Response("{}", {status: 200});
    },
    logger: silentLogger,
  });

  assert.equal(fetched, false);
  assert.equal(messaging.batches.length, 0);
});

test("tip writes for a non-current competition do not send a badge", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "current-comp",
    "/AppConfig/outstandingTipsPushEnabled": true,
  });
  const messaging = new FakeMessaging();
  let fetched = false;

  await handleTipWrittenAppBadge(
    {
      before: new FakeSnapshot(null),
      after: new FakeSnapshot({tip: "home"}),
    },
    {params: {compKey: "old-comp", tipperId: "tipper-1"}},
    {
      db,
      messaging,
      fetchImpl: async () => {
        fetched = true;
        return new Response("{}", {status: 200});
      },
      logger: silentLogger,
    },
  );

  assert.equal(fetched, false);
  assert.equal(messaging.batches.length, 0);
});

test("tip writes for the current competition request a targeted count", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "current-comp",
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/AllTippersTokens/tipper-1": {
      "token-1": "2026-08-04T12:00:00Z",
    },
  });
  const messaging = new FakeMessaging();
  let requestBody: unknown;

  await handleTipWrittenAppBadge(
    {
      before: new FakeSnapshot(null),
      after: new FakeSnapshot({tip: "home"}),
    },
    {params: {compKey: "current-comp", tipperId: "tipper-1"}},
    {
      db,
      messaging,
      commandUrl: "https://example.com/appBadgeCount",
      commandSecret: "secret-1",
      fetchImpl: async (_url, init) => {
        requestBody = JSON.parse(init.body);
        return new Response(JSON.stringify({
          compKey: "current-comp",
          calculatedAt: "2026-08-04T12:00:00Z",
          counts: {"tipper-1": 1},
        }), {status: 200});
      },
      logger: silentLogger,
    },
  );

  assert.deepEqual(requestBody, {
    compKey: "current-comp",
    tipperIds: ["tipper-1"],
  });
  assert.equal(messaging.batches.length, 1);
});

test("syncAppBadges requests counts, sends tokens, and prunes invalid ones", async () => {
  const db = new FakeDatabase({
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/AllTippersTokens/tipper-1": {
      "token-good": "2026-08-04T12:00:00Z",
      "token-bad": "2026-08-04T12:00:00Z",
    },
  });
  const messaging = new FakeMessaging();
  messaging.responseCodes = [
    undefined,
    "messaging/registration-token-not-registered",
  ];
  let requestBody: unknown;
  let requestHeaders: unknown;

  await syncAppBadges("comp-1", ["tipper-1"], {
    db,
    messaging,
    commandUrl: "https://example.com/appBadgeCount",
    commandSecret: "secret-1",
    fetchImpl: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      requestHeaders = init.headers;
      return new Response(JSON.stringify({
        compKey: "comp-1",
        calculatedAt: "2026-08-04T12:00:00Z",
        counts: {"tipper-1": 2},
      }), {status: 200});
    },
    logger: silentLogger,
  });

  assert.deepEqual(requestBody, {
    compKey: "comp-1",
    tipperIds: ["tipper-1"],
  });
  assert.deepEqual(requestHeaders, {
    "Content-Type": "application/json",
    "x-app-badge-secret": "secret-1",
  });
  assert.equal(messaging.batches[0].length, 2);
  assert.deepEqual(db.removedPaths, [
    "/AllTippersTokens/tipper-1/token-bad",
  ]);
});

test("a newly-created token receives only its own current count", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "comp-1",
    "/AppConfig/outstandingTipsPushEnabled": true,
  });
  const messaging = new FakeMessaging();

  await handleTipperTokenCreatedAppBadge(
    new FakeSnapshot("2026-08-04T12:00:00Z"),
    {params: {tipperId: "tipper-1", token: "new-token"}},
    {
      db,
      messaging,
      commandUrl: "https://example.com/appBadgeCount",
      commandSecret: "secret-1",
      fetchImpl: async () => new Response(JSON.stringify({
        compKey: "comp-1",
        calculatedAt: "2026-08-04T12:00:00Z",
        counts: {"tipper-1": 4},
      }), {status: 200}),
      logger: silentLogger,
    },
  );

  assert.equal(messaging.batches.length, 1);
  assert.equal(
    "token" in messaging.batches[0][0] ?
      messaging.batches[0][0].token : null,
    "new-token",
  );
  assert.equal(messaging.batches[0][0].data?.count, "4");
});

test("bulk sync reads all token owners once and omits targeted ids", async () => {
  const db = new FakeDatabase({
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/AllTippersTokens": {
      "tipper-1": {"token-1": "2026-08-04T12:00:00Z"},
      "tipper-2": {"token-2": "2026-08-04T12:00:00Z"},
    },
  });
  const messaging = new FakeMessaging();
  let requestBody: unknown;

  await syncAppBadges("comp-1", undefined, {
    db,
    messaging,
    commandUrl: "https://example.com/appBadgeCount",
    commandSecret: "secret-1",
    fetchImpl: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return new Response(JSON.stringify({
        compKey: "comp-1",
        calculatedAt: "2026-08-04T12:00:00Z",
        counts: {"tipper-1": 1, "tipper-2": 2},
      }), {status: 200});
    },
    logger: silentLogger,
  });

  assert.deepEqual(requestBody, {compKey: "comp-1"});
  assert.equal(
    db.readPaths.filter((path) => path === "/AllTippersTokens").length,
    1,
  );
  assert.equal(messaging.batches[0].length, 2);
});

test("tipperEligibilityChanged ignores profile-only edits", () => {
  assert.equal(tipperEligibilityChanged(
    {name: "Before", compsParticipatedIn: ["comp-1"]},
    {name: "After", compsParticipatedIn: ["comp-1"]},
  ), false);
  assert.equal(tipperEligibilityChanged(
    {isAnonymous: false, compsParticipatedIn: ["comp-1"]},
    {isAnonymous: true, compsParticipatedIn: ["comp-1"]},
  ), true);
});

test("kickoff sweep does not call the worker without a recent kickoff", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "comp-1",
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/DAUCompsGames/comp-1": {
      future: {DateUtc: "2026-08-04T13:00:00Z"},
    },
  });
  let fetched = false;

  await handleKickoffAppBadgeSweep({
    db,
    now: new Date("2026-08-04T12:00:00Z"),
    fetchImpl: async () => {
      fetched = true;
      return new Response("{}", {status: 200});
    },
    logger: silentLogger,
  });

  assert.equal(fetched, false);
});

test("kickoff sweep performs a bulk refresh after a recent kickoff", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "comp-1",
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/DAUCompsGames/comp-1": {
      started: {DateUtc: "2026-08-04 11:59:00Z"},
    },
    "/AllTippersTokens": {},
  });
  const messaging = new FakeMessaging();
  let requestBody: unknown;

  await handleKickoffAppBadgeSweep({
    db,
    messaging,
    now: new Date("2026-08-04T12:00:00Z"),
    commandUrl: "https://example.com/appBadgeCount",
    commandSecret: "secret-1",
    fetchImpl: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return new Response(JSON.stringify({
        compKey: "comp-1",
        calculatedAt: "2026-08-04T12:00:00Z",
        counts: {},
      }), {status: 200});
    },
    logger: silentLogger,
  });

  assert.deepEqual(requestBody, {compKey: "comp-1"});
});

test("minute sweep refreshes at the 48-hour round activation", async () => {
  const db = new FakeDatabase({
    "/AppConfig/currentDAUComp": "comp-1",
    "/AppConfig/outstandingTipsPushEnabled": true,
    "/DAUCompsGames/comp-1": {},
    "/AllDAUComps/comp-1/combinedRounds2": [
      {
        roundStartDate: "2026-08-06T12:00:00Z",
        roundEndDate: "2026-08-08T12:00:00Z",
      },
    ],
    "/AllTippersTokens": {},
  });
  let requestBody: unknown;

  await handleKickoffAppBadgeSweep({
    db,
    now: new Date("2026-08-04T12:00:00Z"),
    commandUrl: "https://example.com/appBadgeCount",
    commandSecret: "secret-1",
    fetchImpl: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return new Response(JSON.stringify({
        compKey: "comp-1",
        calculatedAt: "2026-08-04T12:00:00Z",
        counts: {},
      }), {status: 200});
    },
    logger: silentLogger,
  });

  assert.deepEqual(requestBody, {compKey: "comp-1"});
});
