import http from "node:http";
import { isAuthorized } from "./auth.mjs";
import { clientKeyFor, createRateLimiter } from "./rate-limit.mjs";

const MAX_BODY_BYTES = 128 * 1024;

/**
 * @param {object} options
 * @param {(input: object) => Promise<object>} options.analyzeCapture
 * @param {string | null} [options.clientKey] null 이면 인증 없이 받습니다 (루프백 전용)
 * @param {ReturnType<typeof createRateLimiter>} [options.rateLimiter]
 */
export function createApp({ analyzeCapture, clientKey = null, rateLimiter }) {
  if (typeof analyzeCapture !== "function") {
    throw new Error("analyzeCapture 함수가 필요합니다.");
  }
  const limiter = rateLimiter ?? createRateLimiter();

  return http.createServer(async (request, response) => {
    setCommonHeaders(response);

    // /health 는 인증 밖에 둡니다. Cloud Run 의 상태 확인이 키를 모르고,
    // 이 응답은 아무 정보도 흘리지 않습니다.
    if (request.method === "GET" && request.url === "/health") {
      sendJSON(response, 200, { status: "ok" });
      return;
    }

    if (request.method !== "POST" || request.url !== "/v1/analyze-capture") {
      sendJSON(response, 404, { error: { code: "not_found", message: "경로가 없어요." } });
      return;
    }

    // 인증을 먼저 봅니다. 본문을 읽기 전에 끊어야 남의 요청으로 메모리를 쓰지 않습니다.
    if (!isAuthorized(request, clientKey)) {
      sendJSON(response, 401, {
        error: { code: "unauthorized", message: "이 서버를 쓸 수 없어요." },
      });
      return;
    }

    const verdict = limiter.check(clientKeyFor(request));
    if (!verdict.allowed) {
      response.setHeader("Retry-After", String(verdict.retryAfterSeconds));
      sendJSON(response, 429, {
        error: { code: "rate_limited", message: verdict.reason },
      });
      return;
    }

    try {
      const body = await readRequestJSON(request);
      const input = validateAnalyzeInput(body);
      const draft = await analyzeCapture(input);
      sendJSON(response, 200, draft);
    } catch (error) {
      const mapped = mapError(error);
      sendJSON(response, mapped.status, {
        error: { code: mapped.code, message: mapped.message },
      });
    }
  });
}

export function validateAnalyzeInput(body) {
  const recognizedText = body?.recognized_text;
  if (typeof recognizedText !== "string" || recognizedText.trim().length === 0) {
    throw new ClientInputError("recognized_text가 필요합니다.");
  }
  if (recognizedText.length > 50_000) {
    throw new ClientInputError("recognized_text가 너무 깁니다.");
  }

  return {
    recognizedText: recognizedText.trim(),
    locale: validString(body.locale, 40) ?? "ko-KR",
    timezone: validString(body.timezone, 80) ?? "Asia/Seoul",
    now: validString(body.now, 80) ?? new Date().toISOString(),
  };
}

async function readRequestJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw new PayloadTooLargeError();
    }
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new ClientInputError("JSON 요청을 해석할 수 없습니다.");
  }
}

function validString(value, maxLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength
    ? value
    : null;
}

function setCommonHeaders(response) {
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("X-Content-Type-Options", "nosniff");
}

function sendJSON(response, status, body) {
  response.writeHead(status);
  response.end(JSON.stringify(body));
}

function mapError(error) {
  if (error instanceof PayloadTooLargeError) {
    return { status: 413, code: "payload_too_large", message: error.message };
  }
  if (error instanceof ClientInputError) {
    return { status: 400, code: "invalid_request", message: error.message };
  }
  // 업스트림 상태를 그대로 흘리지 않는다. 앱은 "다시 시도해도 되는가" 만 알면 되고,
  // OpenAI 의 401 을 그대로 내보내면 앱이 사용자 잘못으로 오해하게 만든다.
  const upstreamStatus = Number.isInteger(error?.status) ? error.status : 502;
  if (upstreamStatus === 429) {
    return { status: 429, code: "rate_limited", message: error.message };
  }
  if (upstreamStatus === 504) {
    return { status: 504, code: "upstream_timeout", message: error.message };
  }
  return {
    status: 502,
    code: "analysis_failed",
    message: error?.message ?? "분석하지 못했어요.",
  };
}

class ClientInputError extends Error {}

class PayloadTooLargeError extends Error {
  constructor() {
    super("요청 본문이 너무 큽니다.");
  }
}
