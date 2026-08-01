import http from "node:http";

const MAX_BODY_BYTES = 128 * 1024;

export function createApp({ analyzeCapture }) {
  if (typeof analyzeCapture !== "function") {
    throw new Error("analyzeCapture 함수가 필요합니다.");
  }

  return http.createServer(async (request, response) => {
    setCommonHeaders(response);

    if (request.method === "GET" && request.url === "/health") {
      sendJSON(response, 200, { status: "ok" });
      return;
    }

    if (request.method !== "POST" || request.url !== "/v1/analyze-capture") {
      sendJSON(response, 404, { error: { code: "not_found", message: "경로가 없어요." } });
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
  const upstreamStatus = Number.isInteger(error?.status) ? error.status : 502;
  return {
    status: upstreamStatus === 429 ? 429 : 502,
    code: upstreamStatus === 429 ? "rate_limited" : "analysis_failed",
    message: error?.message ?? "분석하지 못했어요.",
  };
}

class ClientInputError extends Error {}

class PayloadTooLargeError extends Error {
  constructor() {
    super("요청 본문이 너무 큽니다.");
  }
}
