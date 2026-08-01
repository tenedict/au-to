import { taskDraftSchema, validateTaskDraft } from "./task-draft-schema.mjs";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

/**
 * 기본 모델.
 *
 * 실재하지 않는 이름을 기본값에 두면 키를 넣은 첫 호출이 404 로 죽는다.
 * 그때 사용자에게는 "분석 서버에 연결하지 못했어요" 만 보이고, 원인은 키가 아니라
 * 모델 이름이다 — 가장 오래 헤매는 종류의 오류다. 바꾸려면 `OPENAI_MODEL` 을 쓴다.
 */
export const DEFAULT_MODEL = "gpt-4.1-mini";

/** OpenAI 호출이 이보다 오래 걸리면 끊는다. iOS 쪽 요청 타임아웃(20초)보다 짧게 둔다. */
export const REQUEST_TIMEOUT_MS = 15_000;

export class OpenAIClient {
  constructor({
    apiKey,
    model = DEFAULT_MODEL,
    fetchImpl = globalThis.fetch,
    timeoutMs = REQUEST_TIMEOUT_MS,
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
    this.timeoutMs = timeoutMs;
  }

  async analyzeCapture({ recognizedText, locale, timezone, now }) {
    const body = makeResponsesRequest({
      model: this.model,
      recognizedText,
      locale,
      timezone,
      now,
    });

    let response;
    try {
      response = await this.fetchImpl(OPENAI_RESPONSES_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        // 타임아웃이 없으면 OpenAI 가 응답하지 않을 때 이 요청이 영원히 남고,
        // 앱은 화면에 회전자만 띄운 채 아무 말도 못 한다.
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (error) {
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        throw new OpenAIRequestError(
          `OpenAI 응답이 ${Math.round(this.timeoutMs / 1000)}초 안에 오지 않았습니다.`,
          504
        );
      }
      throw new OpenAIRequestError(
        error?.message ?? "OpenAI에 연결하지 못했습니다.",
        502
      );
    }

    const payload = await readJSON(response);
    if (!response.ok) {
      const message =
        payload?.error?.message ?? `OpenAI 요청이 실패했습니다. (${response.status})`;
      throw new OpenAIRequestError(message, response.status);
    }

    return parseTaskDraftResponse(payload);
  }
}

/**
 * 추론 모델인가.
 *
 * `reasoning` 과 `text.verbosity` 는 추론 계열에만 있다. gpt-4.1 계열에 그대로 보내면
 * 400 이 난다. 반대로 추론 모델에 빼면 기본 추론량이 붙어 느려지고 비싸진다.
 */
export function isReasoningModel(model) {
  return /^(gpt-5|o[1-9])/.test(model ?? "");
}

export function makeResponsesRequest({
  model,
  recognizedText,
  locale,
  timezone,
  now,
}) {
  const request = {
    model,
    // 스크린샷 원문이 OpenAI 쪽에 남지 않게 한다.
    store: false,
    instructions: [
      "Role: OCR 텍스트를 사용자가 실행할 수 있는 하나의 할 일 후보로 바꾼다.",
      "Goal: 제목, 메모, 날짜/시간, 보수적인 신뢰도와 근거를 반환한다.",
      "Constraints:",
      "- OCR에 없는 사실을 만들지 않는다.",
      "- 날짜가 명확하지 않으면 due_at은 null이다.",
      "- 연도나 오전/오후가 모호하면 ambiguities에 적고 confidence를 낮춘다.",
      "- has_explicit_time은 원문에 구체적인 시간이 있을 때만 true다.",
      "- due_at은 context.timezone 기준의 오프셋을 포함한다.",
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
    },
  };

  if (isReasoningModel(model)) {
    // 구조화 추출은 긴 추론이 필요 없다. 지연과 비용을 최소로 둔다.
    request.reasoning = { effort: "minimal" };
    request.text.verbosity = "low";
  }

  return request;
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
