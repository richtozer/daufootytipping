import {strict as assert} from "node:assert";
import {test} from "node:test";
import {
  forwardScheduledFixtureDownload,
  ScheduledFixtureDownloadLoggerLike,
} from "./fixture_download_scheduler";

class FakeLogger implements ScheduledFixtureDownloadLoggerLike {
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

test("forwardScheduledFixtureDownload posts a compact secret-protected request", async () => {
  const logger = new FakeLogger();
  const fetchCalls: Array<{
    url: RequestInfo | URL;
    init: Parameters<typeof fetch>[1];
  }> = [];

  const fetchImpl: typeof fetch = async (url, init) => {
    fetchCalls.push({url, init});
    return new Response(JSON.stringify({ok: true}), {status: 200});
  };

  await forwardScheduledFixtureDownload({
    fetchImpl,
    commandUrl: "https://example.com/scheduledFixtureDownload",
    commandSecret: "secret-123",
    logger,
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "https://example.com/scheduledFixtureDownload");
  assert.equal(fetchCalls[0].init?.method, "POST");
  assert.deepEqual(fetchCalls[0].init?.headers, {
    "Content-Type": "application/json",
    "x-backend-scoring-secret": "secret-123",
  });
  assert.equal(fetchCalls[0].init?.body, "{}");
  assert.equal(logger.errors.length, 0);
});

test("forwardScheduledFixtureDownload routes to local Dart endpoint in emulator", async () => {
  const logger = new FakeLogger();
  const fetchCalls: Array<{
    url: RequestInfo | URL;
    init: Parameters<typeof fetch>[1];
  }> = [];

  const fetchImpl: typeof fetch = async (url, init) => {
    fetchCalls.push({url, init});
    return new Response(JSON.stringify({ok: true}), {status: 200});
  };

  await forwardScheduledFixtureDownload({
    fetchImpl,
    commandSecret: "secret-123",
    logger,
    environment: {
      FUNCTIONS_EMULATOR: "true",
      GCLOUD_PROJECT: "demo-project",
      DART_FIXTURE_DOWNLOAD_COMMAND_URL: "https://backend.example.com",
    },
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(
    fetchCalls[0].url,
    "http://127.0.0.1:9229/demo-project/asia-southeast1/scheduled-fixture-download",
  );
  assert.equal(logger.errors.length, 0);
});

test("forwardScheduledFixtureDownload fails when url is missing", async () => {
  await assert.rejects(
    forwardScheduledFixtureDownload({
      fetchImpl: async () => new Response("{}", {status: 200}),
      commandSecret: "secret-123",
    }),
  );
});

test("forwardScheduledFixtureDownload fails when secret is missing", async () => {
  await assert.rejects(
    forwardScheduledFixtureDownload({
      fetchImpl: async () => new Response("{}", {status: 200}),
      commandUrl: "https://example.com/scheduledFixtureDownload",
    }),
  );
});

test("forwardScheduledFixtureDownload throws on non-2xx responses", async () => {
  await assert.rejects(
    forwardScheduledFixtureDownload({
      fetchImpl: async () => new Response("backend error", {status: 500}),
      commandUrl: "https://example.com/scheduledFixtureDownload",
      commandSecret: "secret-123",
    }),
  );
});
