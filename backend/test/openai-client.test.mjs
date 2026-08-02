import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_MODEL,
  isReasoningModel,
  makeResponsesRequest,
  OpenAIClient,
  parseTaskDraftResponse,
} from "../src/openai-client.mjs";
import { LIMITS, MAX_TASKS } from "../src/task-draft-schema.mjs";

test("Responses 요청은 저장을 끄고 strict 스키마를 사용한다", () => {
  const request = makeResponsesRequest({
    model: DEFAULT_MODEL,
    recognizedText: "8월 3일 오후 2시 치과",
    locale: "ko-KR",
    timezone: "Asia/Seoul",
    now: "2026-08-01T12:00:00+09:00",
  });

  assert.equal(request.model, DEFAULT_MODEL);
  assert.equal(request.store, false);
  assert.equal(request.text.format.type, "json_schema");
  assert.equal(request.text.format.strict, true);
  assert.equal(request.text.format.schema.additionalProperties, false);
});

test("기본 모델은 추론 계열이 아니다", () => {
  // 추론 파라미터를 비추론 모델에 보내면 400 이 난다. 기본값이 바뀌면 여기서 걸린다.
  assert.equal(isReasoningModel(DEFAULT_MODEL), false);
});

test("비추론 모델에는 reasoning·verbosity를 보내지 않는다", () => {
  const request = makeResponsesRequest({
    model: "gpt-4.1-mini",
    recognizedText: "치과",
    locale: "ko-KR",
    timezone: "Asia/Seoul",
    now: "2026-08-01T12:00:00+09:00",
  });

  assert.equal(request.reasoning, undefined);
  assert.equal(request.text.verbosity, undefined);
});

test("추론 모델에는 reasoning·verbosity를 함께 보낸다", () => {
  for (const model of ["gpt-5", "gpt-5-mini", "o3"]) {
    const request = makeResponsesRequest({
      model,
      recognizedText: "치과",
      locale: "ko-KR",
      timezone: "Asia/Seoul",
      now: "2026-08-01T12:00:00+09:00",
    });

    assert.equal(isReasoningModel(model), true, model);
    assert.deepEqual(request.reasoning, { effort: "minimal" }, model);
    assert.equal(request.text.verbosity, "low", model);
  }
});

test("strict 스키마에 지원되지 않는 제약 키워드를 넣지 않는다", () => {
  // maxLength·minimum·maxItems 를 넣으면 모델/버전에 따라 400 으로 거절당한다.
  // 범위 강제는 validateTaskDraft 가 서버에서 한다.
  const serialized = JSON.stringify(
    makeResponsesRequest({
      model: DEFAULT_MODEL,
      recognizedText: "치과",
      locale: "ko-KR",
      timezone: "Asia/Seoul",
      now: "2026-08-01T12:00:00+09:00",
    }).text.format.schema,
  );

  for (const keyword of [
    "minLength",
    "maxLength",
    "minimum",
    "maximum",
    "minItems",
    "maxItems",
    "pattern",
  ]) {
    assert.equal(serialized.includes(`"${keyword}"`), false, keyword);
  }
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

  assert.equal(draft.tasks.length, 1);
  assert.equal(draft.tasks[0].title, "치과 방문");
  assert.equal(draft.tasks[0].has_explicit_time, true);
});

test("길이를 넘긴 결과는 버리지 않고 잘라 낸다", () => {
  const draft = parseTaskDraftResponse(
    responsePayload({
      title: "가".repeat(LIMITS.titleMaxLength + 40),
      notes: "나".repeat(LIMITS.notesMaxLength + 100),
      due_at: null,
      has_explicit_time: false,
      confidence: 0.5,
      evidence: Array.from({ length: LIMITS.listMaxItems + 5 }, (_, i) => `근거 ${i}`),
      ambiguities: ["다".repeat(LIMITS.listItemMaxLength + 30)],
    }),
  );

  const only = draft.tasks[0];
  assert.equal(only.title.length, LIMITS.titleMaxLength);
  assert.equal(only.notes.length, LIMITS.notesMaxLength);
  assert.equal(only.evidence.length, LIMITS.listMaxItems);
  assert.equal(only.ambiguities[0].length, LIMITS.listItemMaxLength);
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

test("응답이 없으면 무한정 기다리지 않고 504로 끊는다", async () => {
  const client = new OpenAIClient({
    apiKey: "test-key",
    timeoutMs: 40,
    // 신호가 끊길 때까지 응답하지 않는 서버를 흉내 낸다.
    // 살아 있는 타이머를 함께 걸어 둔다 — AbortSignal.timeout 의 타이머는 unref 라
    // 이것이 없으면 이벤트 루프가 먼저 비고 테스트가 취소된다.
    fetchImpl: (_url, options) =>
      new Promise((_resolve, reject) => {
        const neverArrives = setTimeout(() => reject(new Error("응답 없음")), 5_000);
        options.signal.addEventListener("abort", () => {
          clearTimeout(neverArrives);
          reject(options.signal.reason ?? new Error("aborted"));
        });
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
    (error) => error.status === 504 && /초 안에/.test(error.message),
  );
});

test("연결 실패는 502로 감싸 원인을 남긴다", async () => {
  const client = new OpenAIClient({
    apiKey: "test-key",
    fetchImpl: async () => {
      throw new TypeError("fetch failed");
    },
  });

  await assert.rejects(
    () =>
      client.analyzeCapture({
        recognizedText: "테스트",
        locale: "ko-KR",
        timezone: "Asia/Seoul",
        now: new Date().toISOString(),
      }),
    (error) => error.status === 502 && /fetch failed/.test(error.message),
  );
});

function responsePayload(...drafts) {
  return {
    output: [
      {
        type: "message",
        content: [{ type: "output_text", text: JSON.stringify({ tasks: drafts }) }],
      },
    ],
  };
}

// ── 한 장에 일정이 여럿일 때 ──────────────────────────────

test("여러 할 일을 모두 돌려준다", () => {
  const result = parseTaskDraftResponse(
    responsePayload(
      task({ title: "정기검진", due_at: "2026-08-12T15:00:00+09:00" }),
      task({ title: "재방문", due_at: "2026-09-03T15:00:00+09:00" }),
    ),
  );

  assert.equal(result.tasks.length, 2);
  assert.deepEqual(result.tasks.map((t) => t.title), ["정기검진", "재방문"]);
});

/**
 * 셋 중 하나가 이상하다고 나머지 둘을 버리면 사용자만 손해다.
 * 두 개라도 들어가는 편이 낫다.
 */
test("일부가 잘못돼도 나머지는 살린다", () => {
  const result = parseTaskDraftResponse(
    responsePayload(
      task({ title: "정상 1" }),
      task({ title: "", due_at: null }), // 제목이 빔 → 거절
      task({ title: "정상 2" }),
    ),
  );

  assert.equal(result.tasks.length, 2);
  assert.equal(result.rejected.length, 1);
  assert.match(result.rejected[0], /title/);
});

test("전부 잘못됐으면 응답 자체를 거절한다", () => {
  assert.throws(
    () => parseTaskDraftResponse(responsePayload(task({ title: "" }))),
    /title/,
  );
});

test("tasks 배열이 없으면 거절한다", () => {
  assert.throws(
    () =>
      parseTaskDraftResponse({
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: JSON.stringify({ title: "옛 형식" }) }],
          },
        ],
      }),
    /tasks/,
  );
});

test("최대 개수를 넘으면 잘라 낸다", () => {
  const many = Array.from({ length: MAX_TASKS + 4 }, (_, i) => task({ title: `할 일 ${i}` }));
  const result = parseTaskDraftResponse(responsePayload(...many));

  assert.equal(result.tasks.length, MAX_TASKS);
});

test("여러 개를 찾으라는 지시가 프롬프트에 있다", () => {
  const request = makeResponsesRequest({
    model: DEFAULT_MODEL,
    recognizedText: "8월 12일 검진, 9월 3일 재방문",
    locale: "ko-KR",
    timezone: "Asia/Seoul",
    now: "2026-08-01T12:00:00+09:00",
  });

  assert.match(request.instructions, /전부\*\* 찾아낸다/);
  assert.match(request.instructions, /따로 나눈다/);
  assert.equal(request.text.format.schema.properties.tasks.type, "array");
});

function task(overrides) {
  return {
    title: "치과 방문",
    notes: "",
    due_at: "2026-08-12T15:00:00+09:00",
    has_explicit_time: true,
    confidence: 0.9,
    evidence: [],
    ambiguities: [],
    ...overrides,
  };
}
