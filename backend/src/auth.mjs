import { timingSafeEqual } from "node:crypto";

/**
 * 클라이언트 인증.
 *
 * 앱이 `X-CaptureTask-Key` 헤더에 공유 비밀을 실어 보냅니다.
 *
 * **이 비밀은 앱 번들을 뜯으면 나옵니다.** 그걸 알고 쓰는 방식입니다.
 * 그래도 의미가 있는 이유:
 *   · 새는 것은 OpenAI 키가 **아니라** 이 값입니다. 교체하면 끝입니다
 *   · 새기 전까지 무작위 스캐너와 크롤러를 전부 막습니다
 *   · 새더라도 요청 한도가 금액 피해를 제한합니다
 *
 * 진짜로 앱만 통과시키려면 App Attest 가 필요합니다 (docs/09-SPEC.md H-3).
 */
export const CLIENT_KEY_HEADER = "x-capturetask-key";

/** 이 값 미만이면 무작위 대입이 현실적으로 가능합니다. */
export const MIN_CLIENT_KEY_LENGTH = 24;

export class ClientKeyError extends Error {}

/**
 * 서버가 켜질 때 한 번 부릅니다.
 *
 * 루프백에 바인딩했을 때만 키 없이 돌 수 있습니다. 외부에 노출되는 순간
 * (`HOST=0.0.0.0`) 키를 **반드시** 요구합니다 — "로컬은 예외"라는 규칙이
 * 그대로 배포로 따라가서 사고를 냅니다.
 */
export function resolveClientKey({ key, host }) {
  const isLoopback = host === "127.0.0.1" || host === "::1" || host === "localhost";

  if (!key) {
    if (isLoopback) return null;
    throw new ClientKeyError(
      `CAPTURETASK_CLIENT_KEY가 필요합니다. HOST가 ${host} 라 외부에서 접근할 수 있습니다.\n` +
        "  만들기: openssl rand -base64 32"
    );
  }

  if (key.length < MIN_CLIENT_KEY_LENGTH) {
    throw new ClientKeyError(
      `CAPTURETASK_CLIENT_KEY가 너무 짧습니다 (${key.length}자). ` +
        `${MIN_CLIENT_KEY_LENGTH}자 이상이어야 합니다.\n` +
        "  만들기: openssl rand -base64 32"
    );
  }

  // OpenAI 키를 여기에 잘못 넣는 사고를 막습니다. 그러면 앱 번들에 OpenAI 키가 실립니다.
  if (key.startsWith("sk-")) {
    throw new ClientKeyError(
      "CAPTURETASK_CLIENT_KEY에 OpenAI 키를 넣으면 안 됩니다. 이 값은 앱 번들에 들어갑니다."
    );
  }

  return key;
}

/**
 * 요청 하나를 검사합니다.
 *
 * 길이가 다르면 곧바로 실패시키되, 같은 길이일 때는 `timingSafeEqual` 로 비교합니다.
 * 단순 `===` 는 앞에서부터 다른 지점까지의 시간이 달라서, 그 차이로 한 글자씩 맞춰 볼 수 있습니다.
 */
export function isAuthorized(request, expectedKey) {
  if (!expectedKey) return true; // 루프백 전용 모드

  const provided = request.headers[CLIENT_KEY_HEADER];
  if (typeof provided !== "string") return false;

  const a = Buffer.from(provided);
  const b = Buffer.from(expectedKey);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
