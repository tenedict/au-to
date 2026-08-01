import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "../src/app.mjs";

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

async function startTestServer(context, analyzeCapture) {
  const server = createApp({ analyzeCapture });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const address = server.address();
  return { baseURL: `http://127.0.0.1:${address.port}` };
}
