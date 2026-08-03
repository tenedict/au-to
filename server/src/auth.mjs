import { timingSafeEqual } from "node:crypto";

/**
 * 클라이언트 인증.
 *
 * 앱이 `X-Whenly-Key` 헤더에 공유 비밀을 실어 보냅니다.
 *
 * **옛 이름(`X-CaptureTask-Key`)도 받습니다.** 앱과 서버는 함께 배포되지 않습니다.
 * 서버가 새 이름만 받으면, 아직 옛 빌드가 깔린 폰은 전부 401 을 받습니다 —
 * 사용자에게는 "앱을 업데이트해 주세요" 가 뜨는데 스토어에는 아직 새 빌드가 없습니다.
 * 실제로 이름을 바꾸면서 이 사고가 났습니다.
 *
 * **이 비밀은 앱 번들을 뜯으면 나옵니다.** 그걸 알고 쓰는 방식입니다.
 * 그래도 의미가 있는 이유:
 *   · 새는 것은 OpenAI 키가 **아니라** 이 값입니다. 교체하면 끝입니다
 *   · 새기 전까지 무작위 스캐너와 크롤러를 전부 막습니다
 *   · 새더라도 요청 한도가 금액 피해를 제한합니다
 *
 * 진짜로 앱만 통과시키려면 App Attest 가 필요합니다 (docs/09-SPEC.md H-3).
 */
export const CLIENT_KEY_HEADER = "x-whenly-key";

/**
 * 이름을 바꾸기 전에 쓰던 헤더.
 *
 * **앱 쪽에서는 이미 지웠습니다** (2026-08-03). 여기만 남기는 것은 방향이
 * 반대이기 때문입니다 — 서버는 우리가 언제든 배포하지만, **기기에 이미 깔린 앱은
 * 우리가 바꿀 수 없습니다.** 그 앱들은 아직 옛 이름을 보냅니다.
 *
 * **지우는 조건** — 옛 헤더로 들어오는 요청이 없는 것을 로그로 확인한 뒤.
 * 그 전에 지우면 옛 앱을 쓰는 사람이 전부 막힙니다.
 */
export const LEGACY_CLIENT_KEY_HEADER = "x-capturetask-key";

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
      `WHENLY_CLIENT_KEY가 필요합니다. HOST가 ${host} 라 외부에서 접근할 수 있습니다.\n` +
        "  만들기: openssl rand -base64 32"
    );
  }

  if (key.length < MIN_CLIENT_KEY_LENGTH) {
    throw new ClientKeyError(
      `WHENLY_CLIENT_KEY가 너무 짧습니다 (${key.length}자). ` +
        `${MIN_CLIENT_KEY_LENGTH}자 이상이어야 합니다.\n` +
        "  만들기: openssl rand -base64 32"
    );
  }

  // OpenAI 키를 여기에 잘못 넣는 사고를 막습니다. 그러면 앱 번들에 OpenAI 키가 실립니다.
  if (key.startsWith("sk-")) {
    throw new ClientKeyError(
      "WHENLY_CLIENT_KEY에 OpenAI 키를 넣으면 안 됩니다. 이 값은 앱 번들에 들어갑니다."
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

  // 새 이름을 먼저 본다. 없으면 옛 이름을 본다.
  const provided =
    request.headers[CLIENT_KEY_HEADER] ?? request.headers[LEGACY_CLIENT_KEY_HEADER];
  if (typeof provided !== "string") return false;

  const a = Buffer.from(provided);
  const b = Buffer.from(expectedKey);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
