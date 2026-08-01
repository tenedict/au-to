import assert from "node:assert/strict";
import test from "node:test";
import {
  makeResponsesRequest,
  OpenAIClient,
  parseTaskDraftResponse,
} from "../src/openai-client.mjs";

test("Responses 요청은 저장을 끄고 strict 스키마를 사용한다", () => {
  const request = makeResponsesRequest({
    model: "gpt-5.6-luna",
    recognizedText: "8월 3일 오후 2시 치과",
    locale: "ko-KR",
    timezone: "Asia/Seoul",
    now: "2026-08-01T12:00:00+09:00",
  });

  assert.equal(request.model, "gpt-5.6-luna");
  assert.equal(request.store, false);
  assert.deepEqual(request.reasoning, { effort: "none" });
  assert.equal(request.text.format.type, "json_schema");
  assert.equal(request.text.format.strict, true);
  assert.equal(request.text.format.schema.additionalProperties, false);
});

test("Responses output_text에서 검증된 draft를 파싱한다", () => {
  const draft = parseTaskDraftResponse(
    responsePayload({
      title: "치과 방문",
      notes: "8월 3일 오후 2시 치과",
      due_at: "2026-08-03T14:00:00+09:00",
      has_explicit_time: true,
      confidence: 0.94,
      evidence: ["8월 3일 오후 2시", "치과"],
      ambiguities: [],
    }),
  );

  assert.equal(draft.title, "치과 방문");
  assert.equal(draft.has_explicit_time, true);
});

test("날짜 없이 명시 시간이 있는 결과를 거절한다", () => {
  assert.throws(
    () =>
      parseTaskDraftResponse(
        responsePayload({
          title: "치과 방문",
          notes: "",
          due_at: null,
          has_explicit_time: true,
          confidence: 0.4,
          evidence: [],
          ambiguities: ["날짜가 없음"],
        }),
      ),
    /날짜 없이/,
  );
});

test("OpenAI 오류 메시지와 상태를 보존한다", async () => {
  const client = new OpenAIClient({
    apiKey: "test-key",
    fetchImpl: async () =>
      new Response(JSON.stringify({ error: { message: "rate limited" } }), {
        status: 429,
        headers: { "Content-Type": "application/json" },
      }),
  });

  await assert.rejects(
    () =>
      client.analyzeCapture({
        recognizedText: "테스트",
        locale: "ko-KR",
        timezone: "Asia/Seoul",
        now: new Date().toISOString(),
      }),
    (error) => error.status === 429 && error.message === "rate limited",
  );
});

function responsePayload(draft) {
  return {
    output: [
      {
        type: "message",
        content: [{ type: "output_text", text: JSON.stringify(draft) }],
      },
    ],
  };
}
