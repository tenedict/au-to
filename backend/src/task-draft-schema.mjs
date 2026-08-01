export const taskDraftSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: {
      type: "string",
      minLength: 1,
      maxLength: 120,
      description: "사용자가 실행할 수 있는 간결한 한국어 할 일 제목",
    },
    notes: {
      type: "string",
      maxLength: 4000,
      description: "판단에 필요한 원문 맥락과 세부 내용",
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
      minimum: 0,
      maximum: 1,
      description: "제목과 날짜 해석 전체에 대한 보수적인 신뢰도",
    },
    evidence: {
      type: "array",
      maxItems: 8,
      items: { type: "string", maxLength: 300 },
      description: "각 판단을 뒷받침하는 짧은 원문 구절",
    },
    ambiguities: {
      type: "array",
      maxItems: 8,
      items: { type: "string", maxLength: 300 },
      description: "사용자가 확인해야 하는 모호한 점",
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

export function validateTaskDraft(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("OpenAI가 객체 형식의 결과를 반환하지 않았습니다.");
  }
  if (typeof value.title !== "string" || value.title.trim().length === 0) {
    throw new Error("OpenAI 결과의 title이 비어 있습니다.");
  }
  if (typeof value.notes !== "string") {
    throw new Error("OpenAI 결과의 notes가 문자열이 아닙니다.");
  }
  if (value.due_at !== null && typeof value.due_at !== "string") {
    throw new Error("OpenAI 결과의 due_at 형식이 잘못되었습니다.");
  }
  if (typeof value.has_explicit_time !== "boolean") {
    throw new Error("OpenAI 결과의 has_explicit_time 형식이 잘못되었습니다.");
  }
  if (
    typeof value.confidence !== "number" ||
    value.confidence < 0 ||
    value.confidence > 1
  ) {
    throw new Error("OpenAI 결과의 confidence 범위가 잘못되었습니다.");
  }
  if (!Array.isArray(value.evidence) || !value.evidence.every(isString)) {
    throw new Error("OpenAI 결과의 evidence 형식이 잘못되었습니다.");
  }
  if (!Array.isArray(value.ambiguities) || !value.ambiguities.every(isString)) {
    throw new Error("OpenAI 결과의 ambiguities 형식이 잘못되었습니다.");
  }
  if (value.due_at === null && value.has_explicit_time) {
    throw new Error("날짜 없이 명시적 시간을 설정할 수 없습니다.");
  }
  if (value.due_at !== null && Number.isNaN(Date.parse(value.due_at))) {
    throw new Error("OpenAI 결과의 due_at을 날짜로 해석할 수 없습니다.");
  }
  return value;
}

function isString(value) {
  return typeof value === "string";
}
