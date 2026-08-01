import { taskDraftSchema, validateTaskDraft } from "./task-draft-schema.mjs";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

export class OpenAIClient {
  constructor({
    apiKey,
    model = "gpt-5.6-luna",
    fetchImpl = globalThis.fetch,
  }) {
    if (!apiKey) {
      throw new Error("OPENAI_API_KEY가 필요합니다.");
    }
    if (typeof fetchImpl !== "function") {
      throw new Error("fetch 구현이 필요합니다.");
    }
    this.apiKey = apiKey;
    this.model = model;
    this.fetchImpl = fetchImpl;
  }

  async analyzeCapture({ recognizedText, locale, timezone, now }) {
    const body = makeResponsesRequest({
      model: this.model,
      recognizedText,
      locale,
      timezone,
      now,
    });
    const response = await this.fetchImpl(OPENAI_RESPONSES_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    const payload = await readJSON(response);
    if (!response.ok) {
      const message =
        payload?.error?.message ?? `OpenAI 요청이 실패했습니다. (${response.status})`;
      throw new OpenAIRequestError(message, response.status);
    }

    return parseTaskDraftResponse(payload);
  }
}

export function makeResponsesRequest({
  model,
  recognizedText,
  locale,
  timezone,
  now,
}) {
  return {
    model,
    store: false,
    reasoning: { effort: "none" },
    instructions: [
      "Role: OCR 텍스트를 사용자가 실행할 수 있는 하나의 할 일 후보로 바꾼다.",
      "Goal: 제목, 메모, 날짜/시간, 보수적인 신뢰도와 근거를 반환한다.",
      "Constraints:",
      "- OCR에 없는 사실을 만들지 않는다.",
      "- 날짜가 명확하지 않으면 due_at은 null이다.",
      "- 연도나 오전/오후가 모호하면 ambiguities에 적고 confidence를 낮춘다.",
      "- has_explicit_time은 원문에 구체적인 시간이 있을 때만 true다.",
      "- 출력 언어는 한국어다.",
      "Success: 모든 스키마 필드를 채우고 evidence는 원문 구절만 포함한다.",
    ].join("\n"),
    input: JSON.stringify({
      recognized_text: recognizedText,
      context: { locale, timezone, now },
    }),
    text: {
      format: {
        type: "json_schema",
        name: "capture_task_draft",
        strict: true,
        schema: taskDraftSchema,
      },
      verbosity: "low",
    },
  };
}

export function parseTaskDraftResponse(payload) {
  const outputText = payload?.output
    ?.filter((item) => item?.type === "message")
    .flatMap((item) => item.content ?? [])
    .find((content) => content?.type === "output_text")?.text;

  if (typeof outputText !== "string" || outputText.length === 0) {
    throw new Error("OpenAI 응답에 구조화된 텍스트가 없습니다.");
  }

  let parsed;
  try {
    parsed = JSON.parse(outputText);
  } catch {
    throw new Error("OpenAI 응답 JSON을 해석할 수 없습니다.");
  }
  return validateTaskDraft(parsed);
}

async function readJSON(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

export class OpenAIRequestError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "OpenAIRequestError";
    this.status = status;
  }
}
