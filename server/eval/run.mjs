/**
 * 평가셋을 돌려 분석 품질을 **숫자로** 만든다.
 *
 *   node eval/run.mjs                    로컬 백엔드
 *   BASE_URL=https://… KEY=… node eval/run.mjs   배포된 서버
 *
 * **이게 없으면 프롬프트를 고쳐도 좋아졌는지 나빠졌는지 말할 수 없다.**
 * 실제 호출에서 confidence 가 0.9~1.0 으로만 나와 임계값이 무력하다는 것을
 * 발견했지만(12장 §3), 기준선이 없어 고치지 못하고 기록만 했다. 이게 그 기준선이다.
 *
 * 실제 OpenAI 를 부르므로 **요금이 나간다.** 15건 × 한 번이면 미미하지만,
 * 자동으로 돌리지 않고 사람이 부를 때만 돈다 (verify.sh 에 넣지 않았다).
 */
import { readFile } from "node:fs/promises";

const BASE_URL = process.env.BASE_URL ?? "http://127.0.0.1:8787";
const CLIENT_KEY = process.env.KEY ?? "";

const suite = JSON.parse(
  await readFile(new URL("./cases.json", import.meta.url), "utf8")
);

/** 날짜만 비교한다. 시각까지 맞을 필요가 없는 경우가 있다. */
function sameDay(iso, expectedDate) {
  if (!iso) return false;
  return iso.slice(0, 10) === expectedDate;
}

function judge(testCase, draft) {
  const expect = testCase.expect;
  const problems = [];

  // ── 날짜 ────────────────────────────────────────────────
  if (expect.due_at !== undefined) {
    if (expect.due_at === null) {
      if (draft.due_at !== null) problems.push(`날짜가 없어야 하는데 ${draft.due_at}`);
    } else if (draft.due_at !== expect.due_at) {
      problems.push(`날짜 ${expect.due_at} 를 기대했는데 ${draft.due_at}`);
    }
  } else if (expect.due_at_date !== undefined) {
    if (!sameDay(draft.due_at, expect.due_at_date)) {
      problems.push(`날짜 ${expect.due_at_date} 를 기대했는데 ${draft.due_at}`);
    }
  }

  if (expect.has_explicit_time !== undefined &&
      draft.has_explicit_time !== expect.has_explicit_time) {
    problems.push(
      `has_explicit_time ${expect.has_explicit_time} 를 기대했는데 ${draft.has_explicit_time}`
    );
  }

  // ── 모호함을 모호하다고 말하는가 ────────────────────────
  //
  // 이게 이 평가의 핵심이다. 앱은 ambiguities 가 비어 있으면
  // **확인 없이 캘린더에 넣는다** (AutoFilePolicy). 모호한데 조용하면 사고가 난다.
  const saidAmbiguous = draft.ambiguities.length > 0;
  if (expect.ambiguous === true && !saidAmbiguous) {
    problems.push(`모호하다고 말했어야 한다 (${expect.why ?? ""})`);
  }
  if (expect.ambiguous === false && saidAmbiguous) {
    problems.push(`분명한데 모호하다고 함: ${draft.ambiguities.join(" / ")}`);
  }

  return problems;
}

// ── 실행 ──────────────────────────────────────────────────

/**
 * 우리 서버의 분당 한도(기본 10회)에 우리가 걸린다. 실제로 한 번 걸려서
 * 15건 중 5건이 429 로 죽었다 — 한도가 실제로 돈다는 증거이기도 하다.
 *
 * 한도를 올리는 대신 **스스로 속도를 맞춘다.** 평가하자고 운영 설정을 만지면
 * 평가가 끝난 뒤 되돌리는 것을 잊는다.
 */
const PACE_MS = Number.parseInt(process.env.PACE_MS ?? "6500", 10);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const results = [];
for (const [index, testCase] of suite.cases.entries()) {
  if (index > 0) await sleep(PACE_MS);
  const started = Date.now();
  let draft = null;
  let error = null;

  try {
    const response = await fetch(`${BASE_URL}/v1/analyze-capture`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(CLIENT_KEY ? { "X-Whenly-Key": CLIENT_KEY } : {}),
      },
      body: JSON.stringify({
        recognized_text: testCase.text,
        locale: suite.locale,
        timezone: suite.timezone,
        now: suite.now,
      }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload?.error?.message ?? `HTTP ${response.status}`);
    draft = payload;
  } catch (caught) {
    error = caught.message;
  }

  results.push({
    testCase,
    draft,
    error,
    problems: draft ? judge(testCase, draft) : [`호출 실패: ${error}`],
    seconds: (Date.now() - started) / 1000,
  });
}

// ── 보고 ──────────────────────────────────────────────────

const passed = results.filter((r) => r.problems.length === 0);
const confidences = results.filter((r) => r.draft).map((r) => r.draft.confidence);
const times = results.map((r) => r.seconds).sort((a, b) => a - b);

console.log(`\n평가셋 ${results.length}건 · ${BASE_URL}\n`);

for (const result of results) {
  const mark = result.problems.length === 0 ? "✓" : "✕";
  const conf = result.draft ? result.draft.confidence.toFixed(2) : "  — ";
  console.log(
    `${mark} ${result.testCase.id.padEnd(13)} conf ${conf}  ${result.testCase.kind}`
  );
  for (const problem of result.problems) console.log(`    ${problem}`);
}

console.log(`\n정확도  ${passed.length}/${results.length} ` +
  `(${Math.round((passed.length / results.length) * 100)}%)`);

if (confidences.length > 0) {
  const min = Math.min(...confidences);
  const max = Math.max(...confidences);
  const mean = confidences.reduce((a, b) => a + b, 0) / confidences.length;
  const belowThreshold = confidences.filter((c) => c < 0.8).length;

  console.log(`confidence  최소 ${min.toFixed(2)} · 평균 ${mean.toFixed(2)} · 최대 ${max.toFixed(2)}`);
  console.log(`  0.80 미만: ${belowThreshold}/${confidences.length}건`);
  if (max - min < 0.25) {
    // 임계값 0.80 은 눈금이 넓게 퍼져야 의미가 있다.
    console.log("  ⚠️ 폭이 좁습니다 — confidence 가 눈금 역할을 못 하고 있습니다");
  }
}

console.log(`지연  중앙값 ${times[Math.floor(times.length / 2)].toFixed(1)}초 ` +
  `· 최대 ${times[times.length - 1].toFixed(1)}초\n`);

process.exit(passed.length === results.length ? 0 : 1);
