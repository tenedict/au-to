import { createApp } from "./app.mjs";
import { ClientKeyError, resolveClientKey } from "./auth.mjs";
import { createRateLimiter, DEFAULT_LIMITS } from "./rate-limit.mjs";
import { DEFAULT_MODEL, OpenAIClient } from "./openai-client.mjs";

const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.error("OPENAI_API_KEY가 필요합니다. server/.env.example을 확인해 주세요.");
  process.exit(1);
}
// 예제 파일의 자리표시자를 그대로 두고 켜는 일이 실제로 잦습니다.
// 여기서 막지 않으면 첫 호출에서 401 이 나고, 원인은 서버 로그에만 남습니다.
if (apiKey.includes("replace-me")) {
  console.error(
    "OPENAI_API_KEY가 아직 자리표시자입니다. server/.env에 실제 키를 넣어 주세요."
  );
  process.exit(1);
}

const model = process.env.OPENAI_MODEL ?? DEFAULT_MODEL;
// Cloud Run 은 PORT 를 주입하고 0.0.0.0 바인딩을 요구합니다.
const host = process.env.HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "8787", 10);

let clientKey;
try {
  clientKey = resolveClientKey({ key: process.env.CAPTURETASK_CLIENT_KEY, host });
} catch (error) {
  if (error instanceof ClientKeyError) {
    console.error(error.message);
    process.exit(1);
  }
  throw error;
}

const limits = {
  perMinutePerClient: numberFromEnv(
    "CAPTURETASK_RATE_PER_MINUTE",
    DEFAULT_LIMITS.perMinutePerClient
  ),
  perDayTotal: numberFromEnv("CAPTURETASK_RATE_PER_DAY", DEFAULT_LIMITS.perDayTotal),
};

const client = new OpenAIClient({ apiKey, model });
const app = createApp({
  analyzeCapture: (input) => client.analyzeCapture(input),
  clientKey,
  rateLimiter: createRateLimiter(limits),
});

app.listen(port, host, () => {
  console.log(`CaptureTask backend listening on http://${host}:${port}`);
  console.log(`OpenAI model: ${model}`);
  console.log(
    clientKey
      ? "인증: X-CaptureTask-Key 필요"
      : "인증: 없음 (루프백 전용). 외부에 노출하려면 CAPTURETASK_CLIENT_KEY 를 설정하세요."
  );
  console.log(
    `한도: IP 당 분당 ${limits.perMinutePerClient}회 · 인스턴스 당 하루 ${limits.perDayTotal}회`
  );
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    app.close(() => process.exit(0));
  });
}

function numberFromEnv(name, fallback) {
  const parsed = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
