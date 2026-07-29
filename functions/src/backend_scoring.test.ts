import {strict as assert} from "node:assert";
import {test} from "node:test";
import {
  BackendScoringFetchLike,
  BackendScoringCommandLoggerLike,
  BackendScoringFetchResponseLike,
  BackendScoringCommandPayload,
  TipWriteChangeLike,
  TipWriteSnapshotLike,
  buildBackendScoringCommandId,
  buildLiveScoreWrittenBackendScoringCommand,
  buildOfficialScoreWrittenBackendScoringCommand,
  buildTipWrittenBackendScoringCommand,
  handleLiveScoreWrittenBackendScoringWrite,
  handleOfficialScoreWrittenBackendScoringWrite,
  handleTipWrittenBackendScoringWrite,
  resolveBackendScoringCommandUrl,
} from "./backend_scoring";

class FakeSnapshot implements TipWriteSnapshotLike {
  constructor(
    private readonly existsValue: boolean,
    private readonly value: unknown,
  ) {}

  exists(): boolean {
    return this.existsValue;
  }

  val(): unknown {
    return this.value;
  }
}

class FakeLogger implements BackendScoringCommandLoggerLike {
  public readonly logs: string[] = [];
  public readonly warns: string[] = [];
  public readonly errors: string[] = [];

  log(message: string): void {
    this.logs.push(message);
  }

  warn(message: string): void {
    this.warns.push(message);
  }

  error(message: string): void {
    this.errors.push(message);
  }
}

function createChange(
  beforeValue: unknown,
  afterValue: unknown,
): TipWriteChangeLike {
  return {
    before: new FakeSnapshot(beforeValue != null, beforeValue),
    after: new FakeSnapshot(afterValue != null, afterValue),
  };
}

test("buildTipWrittenBackendScoringCommand constructs the expected payload", () => {
  const command = buildTipWrittenBackendScoringCommand(
    "comp2026",
    "tipper-1",
    "nrl-01-001",
    "mFbon+KFfeNZAx38IYGNz1uL6fk=",
  );

  assert.deepEqual(command, {
    commandType: "tipWritten",
    compKey: "comp2026",
    tipperId: "tipper-1",
    gameKey: "nrl-01-001",
    sourceEventId: "mFbon+KFfeNZAx38IYGNz1uL6fk=",
    sourcePath: "/AllTips/comp2026/tipper-1/nrl-01-001",
    scopeKey: "comp:comp2026/game:nrl-01-001/tipper:tipper-1",
    commandId: "event_bUZib24rS0ZmZU5aQXgzOElZR056MXVMNmZrPQ",
  });
});

test("buildOfficialScoreWrittenBackendScoringCommand constructs the expected payload", () => {
  const command = buildOfficialScoreWrittenBackendScoringCommand(
    "comp2026",
    "nrl-01-001",
    "event-456",
  );

  assert.deepEqual(command, {
    commandType: "officialScoreWritten",
    compKey: "comp2026",
    gameKey: "nrl-01-001",
    sourceEventId: "event-456",
    sourcePath: "/DAUCompsGames/comp2026/nrl-01-001",
    scopeKey: "comp:comp2026/game:nrl-01-001",
    commandId: "event_ZXZlbnQtNDU2",
  });
});

test("buildLiveScoreWrittenBackendScoringCommand builds payload", () => {
  const command = buildLiveScoreWrittenBackendScoringCommand(
    "comp2026",
    "nrl-01-001",
    "event-789",
  );

  assert.deepEqual(command, {
    commandType: "liveScoreWritten",
    compKey: "comp2026",
    gameKey: "nrl-01-001",
    sourceEventId: "event-789",
    sourcePath: "/Stats/comp2026/live_scores_backend_v1/nrl-01-001/current",
    scopeKey: "comp:comp2026/game:nrl-01-001",
    commandId: "event_ZXZlbnQtNzg5",
  });
});

test("buildBackendScoringCommandId encodes unsafe RTDB key characters", () => {
  assert.equal(
    buildBackendScoringCommandId("mFbon+KFfeNZAx38IYGNz1uL6fk="),
    "event_bUZib24rS0ZmZU5aQXgzOElZR056MXVMNmZrPQ",
  );
});

test("resolveBackendScoringCommandUrl prefers local Dart endpoint in emulator", () => {
  assert.equal(
    resolveBackendScoringCommandUrl(undefined, {
      FUNCTIONS_EMULATOR: "true",
      GCLOUD_PROJECT: "demo-project",
      BACKEND_SCORING_COMMAND_URL: "https://backend.example.com",
    }),
    "http://127.0.0.1:9229/demo-project/asia-southeast1/backend-scoring-command",
  );
});

test("handleTipWrittenBackendScoringWrite posts a compact command payload", async () => {
  const change = createChange(null, {
    tip: "home",
    submittedAtUTC: "2026-01-03T12:00:00Z",
  });
  const logger = new FakeLogger();

  const fetchCalls: Array<{
    url: string;
    init: Parameters<BackendScoringFetchLike>[1];
  }> = [];
  const fetchImpl: BackendScoringFetchLike = async (url, init) => {
    fetchCalls.push({url, init});
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({status: "completed"});
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleTipWrittenBackendScoringWrite(
    change,
    {
      eventId: "event-123",
      params: {
        compKey: "comp2026",
        tipperId: "tipper-1",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "https://backend.example.com/backendScoringCommand");
  assert.equal(fetchCalls[0].init.method, "POST");
  assert.deepEqual(fetchCalls[0].init.headers, {
    "Content-Type": "application/json",
    "x-backend-scoring-secret": "secret-123",
  });

  const parsedBody = JSON.parse(fetchCalls[0].init.body) as {
    command: BackendScoringCommandPayload;
  };
  assert.deepEqual(parsedBody.command, {
    commandType: "tipWritten",
    compKey: "comp2026",
    tipperId: "tipper-1",
    gameKey: "nrl-01-001",
    sourceEventId: "event-123",
    sourcePath: "/AllTips/comp2026/tipper-1/nrl-01-001",
    scopeKey: "comp:comp2026/game:nrl-01-001/tipper:tipper-1",
    commandId: "event_ZXZlbnQtMTIz",
  });
  assert.equal(logger.warns.length, 0);
  assert.equal(logger.errors.length, 0);
});

test("handleTipWrittenBackendScoringWrite routes to local Dart worker in emulator", async () => {
  const change = createChange(null, {
    tip: "home",
    submittedAtUTC: "2026-01-03T12:00:00Z",
  });
  const logger = new FakeLogger();

  const fetchCalls: Array<{
    url: string;
    init: Parameters<BackendScoringFetchLike>[1];
  }> = [];
  const fetchImpl: BackendScoringFetchLike = async (url, init) => {
    fetchCalls.push({url, init});
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({status: "completed"});
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleTipWrittenBackendScoringWrite(
    change,
    {
      eventId: "event-123",
      params: {
        compKey: "comp2026",
        tipperId: "tipper-1",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandSecret: "secret-123",
      logger,
      environment: {
        FUNCTIONS_EMULATOR: "true",
        GCLOUD_PROJECT: "demo-project",
        BACKEND_SCORING_COMMAND_URL: "https://backend.example.com",
      },
    },
  );

  assert.equal(fetchCalls.length, 1);
  assert.equal(
    fetchCalls[0].url,
    "http://127.0.0.1:9229/demo-project/asia-southeast1/backend-scoring-command",
  );
  assert.equal(logger.errors.length, 0);
});

test("handleTipWrittenBackendScoringWrite skips no-op writes", async () => {
  const logger = new FakeLogger();
  const fetchImpl: BackendScoringFetchLike = async () => {
    throw new Error("fetch should not be called");
  };

  await handleTipWrittenBackendScoringWrite(
    createChange(
      {
        tip: "home",
        submittedAtUTC: "2026-01-03T12:00:00Z",
      },
      {
        tip: "home",
        submittedAtUTC: "2026-01-03T12:00:00Z",
      },
    ),
    {
      eventId: "event-123",
      params: {
        compKey: "comp2026",
        tipperId: "tipper-1",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(logger.errors.length, 0);
});

test("handleTipWrittenBackendScoringWrite throws on retryable worker failures", async () => {
  const change = createChange(null, {
    tip: "home",
    submittedAtUTC: "2026-01-03T12:00:00Z",
  });
  const logger = new FakeLogger();

  const fetchImpl: BackendScoringFetchLike = async () => ({
    ok: false,
    status: 500,
    async text() {
      return "internal error";
    },
  });

  await assert.rejects(
    handleTipWrittenBackendScoringWrite(
      change,
      {
        eventId: "event-123",
        params: {
          compKey: "comp2026",
          tipperId: "tipper-1",
          gameKey: "nrl-01-001",
        },
      },
      {
        fetchImpl,
        commandUrl: "https://backend.example.com/backendScoringCommand",
        commandSecret: "secret-123",
        logger,
      },
    ),
    /worker responded with 500/,
  );
});

test("handleOfficialScoreWrittenBackendScoringWrite posts a compact command payload", async () => {
  const change = createChange(
    {
      HomeTeamScore: 12,
      AwayTeamScore: 8,
      DateUtc: "2026-01-03T12:00:00Z",
    },
    {
      HomeTeamScore: 14,
      AwayTeamScore: 8,
      DateUtc: "2026-01-03T12:00:00Z",
    },
  );
  const logger = new FakeLogger();

  const fetchCalls: Array<{
    url: string;
    init: Parameters<BackendScoringFetchLike>[1];
  }> = [];
  const fetchImpl: BackendScoringFetchLike = async (url, init) => {
    fetchCalls.push({url, init});
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({status: "completed"});
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleOfficialScoreWrittenBackendScoringWrite(
    change,
    {
      eventId: "event-456",
      params: {
        compKey: "comp2026",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "https://backend.example.com/backendScoringCommand");
  assert.equal(fetchCalls[0].init.method, "POST");
  assert.deepEqual(fetchCalls[0].init.headers, {
    "Content-Type": "application/json",
    "x-backend-scoring-secret": "secret-123",
  });

  const parsedBody = JSON.parse(fetchCalls[0].init.body) as {
    command: BackendScoringCommandPayload;
  };
  assert.deepEqual(parsedBody.command, {
    commandType: "officialScoreWritten",
    compKey: "comp2026",
    gameKey: "nrl-01-001",
    sourceEventId: "event-456",
    sourcePath: "/DAUCompsGames/comp2026/nrl-01-001",
    scopeKey: "comp:comp2026/game:nrl-01-001",
    commandId: "event_ZXZlbnQtNDU2",
  });
  assert.equal(logger.warns.length, 0);
  assert.equal(logger.errors.length, 0);
});

test("handleLiveScoreWrittenBackendScoringWrite posts payload", async () => {
  const change = createChange(
    {
      homeInterimScore: 12,
      awayInterimScore: 8,
    },
    {
      homeInterimScore: 12,
      awayInterimScore: 14,
    },
  );
  const logger = new FakeLogger();

  const fetchCalls: Array<{
    url: string;
    init: Parameters<BackendScoringFetchLike>[1];
  }> = [];
  const fetchImpl: BackendScoringFetchLike = async (url, init) => {
    fetchCalls.push({url, init});
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({status: "completed"});
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleLiveScoreWrittenBackendScoringWrite(
    change,
    {
      eventId: "event-789",
      params: {
        compKey: "comp2026",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "https://backend.example.com/backendScoringCommand");
  assert.equal(fetchCalls[0].init.method, "POST");
  assert.deepEqual(fetchCalls[0].init.headers, {
    "Content-Type": "application/json",
    "x-backend-scoring-secret": "secret-123",
  });

  const parsedBody = JSON.parse(fetchCalls[0].init.body) as {
    command: BackendScoringCommandPayload;
  };
  assert.deepEqual(parsedBody.command, {
    commandType: "liveScoreWritten",
    compKey: "comp2026",
    gameKey: "nrl-01-001",
    sourceEventId: "event-789",
    sourcePath: "/Stats/comp2026/live_scores_backend_v1/nrl-01-001/current",
    scopeKey: "comp:comp2026/game:nrl-01-001",
    commandId: "event_ZXZlbnQtNzg5",
  });
  assert.equal(logger.warns.length, 0);
  assert.equal(logger.errors.length, 0);
});

test("handleLiveScoreWrittenBackendScoringWrite skips material no-ops", async () => {
  const logger = new FakeLogger();
  const fetchImpl: BackendScoringFetchLike = async () => {
    throw new Error("fetch should not be called");
  };

  await handleLiveScoreWrittenBackendScoringWrite(
    createChange(
      {
        homeInterimScore: 12,
        awayInterimScore: 8,
        submittedTimeUTC: "2026-01-03T10:05:00Z",
        tipperID: "tipper-1",
        crowdSourcedScores: [
          {
            submittedTimeUTC: "2026-01-03T10:05:00Z",
            scoreTeam: "home",
            tipperID: "tipper-1",
            interimScore: 12,
            gameComplete: false,
          },
        ],
      },
      {
        homeInterimScore: "12",
        awayInterimScore: "8",
        submittedTimeUTC: "2026-01-03T10:06:00Z",
        tipperID: "tipper-2",
        crowdSourcedScores: [
          {
            submittedTimeUTC: "2026-01-03T10:06:00Z",
            scoreTeam: "home",
            tipperID: "tipper-2",
            interimScore: 12,
            gameComplete: false,
          },
        ],
      },
    ),
    {
      eventId: "event-789",
      params: {
        compKey: "comp2026",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(logger.errors.length, 0);
});

test("handleLiveScoreWrittenBackendScoringWrite posts on score change", async () => {
  const logger = new FakeLogger();
  let fetchCalled = false;
  const fetchImpl: BackendScoringFetchLike = async () => {
    fetchCalled = true;
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({status: "completed"});
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleLiveScoreWrittenBackendScoringWrite(
    createChange(
      {
        homeInterimScore: 12,
        awayInterimScore: 8,
        gameComplete: false,
      },
      {
        homeInterimScore: 12,
        awayInterimScore: 10,
        gameComplete: false,
      },
    ),
    {
      eventId: "event-789",
      params: {
        compKey: "comp2026",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(fetchCalled, true);
  assert.equal(logger.errors.length, 0);
});

test("handleOfficialScoreWrittenBackendScoringWrite skips no-op score writes", async () => {
  const logger = new FakeLogger();
  const fetchImpl: BackendScoringFetchLike = async () => {
    throw new Error("fetch should not be called");
  };

  await handleOfficialScoreWrittenBackendScoringWrite(
    createChange(
      {
        HomeTeamScore: 12,
        AwayTeamScore: 8,
      },
      {
        HomeTeamScore: 12,
        AwayTeamScore: 8,
      },
    ),
    {
      eventId: "event-456",
      params: {
        compKey: "comp2026",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      commandSecret: "secret-123",
      logger,
    },
  );

  assert.equal(logger.errors.length, 0);
});

test("handleTipWrittenBackendScoringWrite logs and skips when command secret is missing", async () => {
  const change = createChange(null, {
    tip: "home",
    submittedAtUTC: "2026-01-03T12:00:00Z",
  });
  const logger = new FakeLogger();
  let fetchCalled = false;
  const fetchImpl: BackendScoringFetchLike = async () => {
    fetchCalled = true;
    return {
      ok: true,
      status: 200,
      async text() {
        return "";
      },
    } satisfies BackendScoringFetchResponseLike;
  };

  await handleTipWrittenBackendScoringWrite(
    change,
    {
      eventId: "event-123",
      params: {
        compKey: "comp2026",
        tipperId: "tipper-1",
        gameKey: "nrl-01-001",
      },
    },
    {
      fetchImpl,
      commandUrl: "https://backend.example.com/backendScoringCommand",
      logger,
    },
  );

  assert.equal(fetchCalled, false);
  assert.equal(logger.errors.length, 1);
  assert.match(
    logger.errors[0],
    /missing command secret configuration/,
  );
});
