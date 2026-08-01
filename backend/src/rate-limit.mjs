/**
 * 요청 한도.
 *
 * 이게 없으면 비밀키가 새는 순간 **요금이 무한히 나갑니다.** 인증은 "누가"를 막고,
 * 한도는 "얼마나"를 막습니다. 둘 다 있어야 합니다 — 키는 언젠가 샙니다.
 *
 * 시계를 주입받는 이유는 테스트가 실제로 1분을 기다리지 않게 하기 위해서입니다.
 */

/** 이 한도는 **인스턴스 하나 기준**입니다. 아래 주석을 반드시 읽으세요. */
export const DEFAULT_LIMITS = {
  /** IP 하나가 1분에 보낼 수 있는 요청 수. 사람이 스크린샷을 담는 속도를 훨씬 넘습니다. */
  perMinutePerClient: 10,
  /** 인스턴스 하나가 하루에 보낼 수 있는 총 요청 수. **금액 상한**입니다. */
  perDayTotal: 500,
};

/**
 * @param {object} options
 * @param {number} [options.perMinutePerClient]
 * @param {number} [options.perDayTotal]
 * @param {() => number} [options.now] 밀리초. 테스트가 시간을 직접 움직입니다.
 */
export function createRateLimiter({
  perMinutePerClient = DEFAULT_LIMITS.perMinutePerClient,
  perDayTotal = DEFAULT_LIMITS.perDayTotal,
  now = () => Date.now(),
} = {}) {
  const MINUTE = 60_000;
  const DAY = 24 * 60 * 60_000;

  /** @type {Map<string, number[]>} 클라이언트 → 최근 1분 요청 시각 */
  const recentByClient = new Map();
  let dayStartedAt = now();
  let dayCount = 0;

  return {
    /**
     * @returns {{allowed: true} | {allowed: false, reason: string, retryAfterSeconds: number}}
     */
    check(clientKey) {
      const at = now();

      if (at - dayStartedAt >= DAY) {
        dayStartedAt = at;
        dayCount = 0;
      }
      if (dayCount >= perDayTotal) {
        return {
          allowed: false,
          reason: "하루 요청 한도를 넘었습니다.",
          retryAfterSeconds: Math.ceil((dayStartedAt + DAY - at) / 1000),
        };
      }

      const recent = (recentByClient.get(clientKey) ?? []).filter(
        (stamp) => at - stamp < MINUTE
      );
      if (recent.length >= perMinutePerClient) {
        return {
          allowed: false,
          reason: "잠시 후 다시 시도해 주세요.",
          retryAfterSeconds: Math.ceil((recent[0] + MINUTE - at) / 1000),
        };
      }

      recent.push(at);
      recentByClient.set(clientKey, recent);
      dayCount += 1;

      // 오래된 클라이언트를 치우지 않으면 Map 이 무한히 자랍니다.
      // 요청이 들어올 때만 훑으므로 별도 타이머가 필요 없습니다.
      if (recentByClient.size > 1_000) {
        for (const [key, stamps] of recentByClient) {
          if (stamps.every((stamp) => at - stamp >= MINUTE)) {
            recentByClient.delete(key);
          }
        }
      }

      return { allowed: true };
    },

    /** 관측용. 지금까지 오늘 몇 건 나갔는지. */
    snapshot() {
      return { dayCount, trackedClients: recentByClient.size };
    },
  };
}

/**
 * 요청을 보낸 쪽을 식별합니다.
 *
 * Cloud Run 같은 프록시 뒤에서는 socket 주소가 언제나 프록시입니다.
 * `X-Forwarded-For` 의 **맨 앞** 항목이 원래 클라이언트입니다 —
 * 뒤쪽은 중간 프록시들이라, 뒤를 쓰면 모든 사용자가 한 사람으로 묶입니다.
 *
 * 이 헤더는 위조할 수 있습니다. 그래서 한도는 방어의 **전부가 아니라 한 겹**이고,
 * 금액 상한(`perDayTotal`)이 위조와 무관하게 마지막 선을 지킵니다.
 */
export function clientKeyFor(request) {
  const forwarded = request.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return request.socket?.remoteAddress ?? "unknown";
}
