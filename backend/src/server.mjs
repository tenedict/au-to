import { createApp } from "./app.mjs";
import { DEFAULT_MODEL, OpenAIClient } from "./openai-client.mjs";

const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.error("OPENAI_API_KEY가 필요합니다. backend/.env.example을 확인해 주세요.");
  process.exit(1);
}
// 예제 파일의 자리표시자를 그대로 두고 켜는 일이 실제로 잦다.
// 여기서 막지 않으면 첫 호출에서 401 이 나고, 원인은 서버 로그에만 남는다.
if (apiKey.includes("replace-me")) {
  console.error(
    "OPENAI_API_KEY가 아직 자리표시자입니다. backend/.env에 실제 키를 넣어 주세요."
  );
  process.exit(1);
}

const model = process.env.OPENAI_MODEL ?? DEFAULT_MODEL;
const host = process.env.HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "8787", 10);
const client = new OpenAIClient({ apiKey, model });
const app = createApp({
  analyzeCapture: (input) => client.analyzeCapture(input),
});

app.listen(port, host, () => {
  console.log(`CaptureTask backend listening on http://${host}:${port}`);
  console.log(`OpenAI model: ${model}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    app.close(() => process.exit(0));
  });
}
