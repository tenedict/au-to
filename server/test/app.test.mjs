import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "../src/app.mjs";
import { CLIENT_KEY_HEADER } from "../src/auth.mjs";
import { createRateLimiter } from "../src/rate-limit.mjs";

const CLIENT_KEY = "test-client-key-that-is-long-enough";

test("health endpoint", async (context) => {
  const { baseURL } = await startTestServer(context, async () => {
    throw new Error("호출되면 안 됩니다.");
  });
  const response = await fetch(`${baseURL}/health`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});

test("유효한 OCR 요청을 분석 함수에 전달한다", async (context) => {
  let received;
  const { baseURL } = await startTestServer(context, async (input) => {
    received = input;
    return { title: "서류 제출" };
  });

  const response = await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      recognized_text: "8월 5일까지 서류 제출",
      locale: "ko-KR",
      timezone: "Asia/Seoul",
      now: "2026-08-01T12:00:00+09:00",
    }),
  });

  assert.equal(response.status, 200);
  assert.equal(received.recognizedText, "8월 5일까지 서류 제출");
  assert.deepEqual(await response.json(), { title: "서류 제출" });
});

test("빈 OCR 요청을 400으로 거절한다", async (context) => {
  const { baseURL } = await startTestServer(context, async () => ({}));
  const response = await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ recognized_text: "   " }),
  });

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, "invalid_request");
});

test("OpenAI rate limit을 429로 전달한다", async (context) => {
  const { baseURL } = await startTestServer(context, async () => {
    const error = new Error("잠시 후 다시 시도해 주세요.");
    error.status = 429;
    throw error;
  });
  const response = await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ recognized_text: "테스트" }),
  });

  assert.equal(response.status, 429);
  assert.equal((await response.json()).error.code, "rate_limited");
});

test("키를 설정했으면 헤더 없는 요청을 401로 막는다", async (context) => {
  const { baseURL } = await startTestServer(
    context,
    async () => {
      throw new Error("인증을 통과하면 안 됩니다.");
    },
    { clientKey: CLIENT_KEY }
  );

  const response = await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ recognized_text: "테스트" }),
  });

  assert.equal(response.status, 401);
  assert.equal((await response.json()).error.code, "unauthorized");
});

test("맞는 키를 실으면 통과한다", async (context) => {
  const { baseURL } = await startTestServer(context, async () => ({ title: "통과" }), {
    clientKey: CLIENT_KEY,
  });

  const response = await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json", [CLIENT_KEY_HEADER]: CLIENT_KEY },
    body: JSON.stringify({ recognized_text: "테스트" }),
  });

  assert.equal(response.status, 200);
});

/** 상태 확인은 키를 모릅니다. 여기까지 막으면 Cloud Run 이 인스턴스를 죽입니다. */
test("health 는 키 없이도 열려 있다", async (context) => {
  const { baseURL } = await startTestServer(context, async () => ({}), {
    clientKey: CLIENT_KEY,
  });

  assert.equal((await fetch(`${baseURL}/health`)).status, 200);
});

test("한도를 넘으면 429와 Retry-After 를 준다", async (context) => {
  const { baseURL } = await startTestServer(context, async () => ({ title: "ok" }), {
    rateLimiter: createRateLimiter({ perMinutePerClient: 1 }),
  });
  const send = () =>
    fetch(`${baseURL}/v1/analyze-capture`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ recognized_text: "테스트" }),
    });

  assert.equal((await send()).status, 200);
  const blocked = await send();

  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get("Retry-After")) > 0);
  assert.equal((await blocked.json()).error.code, "rate_limited");
});

/** 인증을 본문보다 먼저 봐야 남의 요청으로 메모리를 쓰지 않습니다. */
test("인증 실패는 분석 함수를 부르지 않는다", async (context) => {
  let called = false;
  const { baseURL } = await startTestServer(
    context,
    async () => {
      called = true;
      return {};
    },
    { clientKey: CLIENT_KEY }
  );

  await fetch(`${baseURL}/v1/analyze-capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ recognized_text: "테스트" }),
  });

  assert.equal(called, false);
});

async function startTestServer(context, analyzeCapture, options = {}) {
  const server = createApp({ analyzeCapture, ...options });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const address = server.address();
  return { baseURL: `http://127.0.0.1:${address.port}` };
}
