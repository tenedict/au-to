/**
 * OpenAI Structured Outputs 스키마.
 *
 * `strict: true` 는 지원하는 키워드가 제한적이다. `maxLength` · `minimum` · `maxItems` 같은
 * 제약을 스키마에 넣으면 모델/버전에 따라 400 으로 거절당한다 — 그러면 분석이
 * 통째로 실패하고, 사용자에게는 "이해하지 못했어요" 만 보인다.
 *
 * 그래서 스키마는 **모양(type)** 만 강제하고, **범위**는 아래 `validateTaskDraft` 가
 * 서버에서 직접 확인하고 다듬는다. 한계값은 갈라지지 않도록 여기 한 번만 적는다.
 */
export const LIMITS = {
  titleMaxLength: 120,
  notesMaxLength: 4000,
  listMaxItems: 8,
  listItemMaxLength: 300,
};

/** 한 장에서 뽑을 수 있는 할 일의 최대 개수. */
export const MAX_TASKS = 8;

const singleTaskSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: {
      type: "string",
      description: `사용자가 실행할 수 있는 간결한 한국어 할 일 제목 (${LIMITS.titleMaxLength}자 이내)`,
    },
    notes: {
      type: "string",
      description: `이 할 일에 해당하는 원문 맥락 (${LIMITS.notesMaxLength}자 이내)`,
    },
    due_at: {
      type: ["string", "null"],
      description: "명시된 시각과 오프셋을 포함한 ISO 8601 날짜 또는 null",
    },
    has_explicit_time: {
      type: "boolean",
      description: "원문에 구체적인 시간이 있을 때만 true",
    },
    confidence: {
      type: "number",
      description: "제목과 날짜 해석 전체에 대한 보수적인 신뢰도. 0 이상 1 이하",
    },
    evidence: {
      type: "array",
      items: { type: "string" },
      description: `이 할 일을 뒷받침하는 짧은 원문 구절 (최대 ${LIMITS.listMaxItems}개)`,
    },
    ambiguities: {
      type: "array",
      items: { type: "string" },
      description: `사용자가 직접 고쳐야 하는 모호한 점 (최대 ${LIMITS.listMaxItems}개)`,
    },
  },
  required: [
    "title",
    "notes",
    "due_at",
    "has_explicit_time",
    "confidence",
    "evidence",
    "ambiguities",
  ],
};

/**
 * 한 장에 일정이 여러 개 있을 수 있다.
 *
 * 예약 확정 문자에 "8월 12일 검진, 9월 3일 재방문" 이 함께 오거나, 공지 하나에
 * 접수 마감과 발표일이 같이 적힌다. 하나만 뽑으면 나머지를 사용자가 다시 입력해야 하고,
 * 그러면 이 앱을 쓸 이유가 없다.
 */
export const taskDraftSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    tasks: {
      type: "array",
      items: singleTaskSchema,
      description:
        `원문에서 찾은 할 일 목록. 서로 다른 날짜나 서로 다른 일이면 따로 나눈다. ` +
        `같은 일의 반복 설명이면 하나로 합친다. 최대 ${MAX_TASKS}개.`,
    },
  },
  required: ["tasks"],
};

/**
 * 모델 응답을 검사하고 앱이 쓸 수 있는 모양으로 다듬는다.
 *
 * 모양이 틀린 것은 던지고, 길이만 넘친 것은 잘라 낸다.
 * 제목이 한 글자 길다고 분석 전체를 버리면 사용자만 손해다.
 *
 * **할 일 하나가 틀렸다고 나머지를 버리지 않는다.** 셋 중 하나가 이상하면
 * 나머지 둘은 살린다 — 사용자에게는 두 개라도 들어가는 편이 낫다.
 */
export function validateTaskDrafts(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("OpenAI가 객체 형식의 결과를 반환하지 않았습니다.");
  }
  if (!Array.isArray(value.tasks)) {
    throw new Error("OpenAI 결과에 tasks 배열이 없습니다.");
  }

  const tasks = [];
  const rejected = [];
  for (const candidate of value.tasks.slice(0, MAX_TASKS)) {
    try {
      tasks.push(validateOneTask(candidate));
    } catch (error) {
      rejected.push(error.message);
    }
  }

  // 전부 틀렸으면 그건 응답 자체가 잘못된 것이다.
  if (tasks.length === 0) {
    throw new Error(
      rejected[0] ?? "OpenAI가 할 일을 하나도 반환하지 않았습니다."
    );
  }
  return { tasks, rejected };
}

function validateOneTask(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("할 일이 객체 형식이 아닙니다.");
  }
  if (typeof value.title !== "string" || value.title.trim().length === 0) {
    throw new Error("할 일의 title이 비어 있습니다.");
  }
  if (typeof value.notes !== "string") {
    throw new Error("할 일의 notes가 문자열이 아닙니다.");
  }
  if (value.due_at !== null && typeof value.due_at !== "string") {
    throw new Error("할 일의 due_at 형식이 잘못되었습니다.");
  }
  if (typeof value.has_explicit_time !== "boolean") {
    throw new Error("할 일의 has_explicit_time 형식이 잘못되었습니다.");
  }
  if (
    typeof value.confidence !== "number" ||
    Number.isNaN(value.confidence) ||
    value.confidence < 0 ||
    value.confidence > 1
  ) {
    throw new Error("할 일의 confidence 범위가 잘못되었습니다.");
  }
  if (!Array.isArray(value.evidence) || !value.evidence.every(isString)) {
    throw new Error("할 일의 evidence 형식이 잘못되었습니다.");
  }
  if (!Array.isArray(value.ambiguities) || !value.ambiguities.every(isString)) {
    throw new Error("할 일의 ambiguities 형식이 잘못되었습니다.");
  }
  // 날짜 없이 시간만 명시된 결과는 앱에서 표현할 수 없다.
  // iOS 의 AssistantTask 도 같은 불변 조건을 강제한다.
  if (value.due_at === null && value.has_explicit_time) {
    throw new Error("날짜 없이 명시적 시간을 설정할 수 없습니다.");
  }
  if (value.due_at !== null && Number.isNaN(Date.parse(value.due_at))) {
    throw new Error("할 일의 due_at을 날짜로 해석할 수 없습니다.");
  }

  return {
    title: clamp(value.title.trim(), LIMITS.titleMaxLength),
    notes: clamp(value.notes, LIMITS.notesMaxLength),
    due_at: value.due_at,
    has_explicit_time: value.has_explicit_time,
    confidence: value.confidence,
    evidence: clampList(value.evidence),
    ambiguities: clampList(value.ambiguities),
  };
}

function clampList(list) {
  return list
    .slice(0, LIMITS.listMaxItems)
    .map((item) => clamp(item, LIMITS.listItemMaxLength));
}

function clamp(text, maxLength) {
  return text.length <= maxLength ? text : text.slice(0, maxLength);
}

function isString(value) {
  return typeof value === "string";
}
