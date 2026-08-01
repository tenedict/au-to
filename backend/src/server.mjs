import { createApp } from "./app.mjs";
import { OpenAIClient } from "./openai-client.mjs";

const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.error("OPENAI_API_KEY가 필요합니다. backend/.env.example을 확인해 주세요.");
  process.exit(1);
}

const model = process.env.OPENAI_MODEL ?? "gpt-5.6-luna";
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
