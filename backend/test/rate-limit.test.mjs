import assert from "node:assert/strict";
import test from "node:test";
import { clientKeyFor, createRateLimiter } from "../src/rate-limit.mjs";

/** 시계를 직접 움직입니다. 테스트가 실제로 1분을 기다리지 않게. */
function fakeClock(start = 1_000_000) {
  let at = start;
  return {
    now: () => at,
    advance(ms) {
      at += ms;
    },
  };
}

test("한도 안에서는 통과시킨다", () => {
  const limiter = createRateLimiter({ perMinutePerClient: 3, now: fakeClock().now });

  for (let i = 0; i < 3; i += 1) {
    assert.equal(limiter.check("1.2.3.4").allowed, true, `${i + 1}번째`);
  }
});

test("분당 한도를 넘으면 막고 언제 다시 되는지 알린다", () => {
  const limiter = createRateLimiter({ perMinutePerClient: 2, now: fakeClock().now });
  limiter.check("1.2.3.4");
  limiter.check("1.2.3.4");

  const verdict = limiter.check("1.2.3.4");

  assert.equal(verdict.allowed, false);
  assert.ok(verdict.retryAfterSeconds > 0 && verdict.retryAfterSeconds <= 60);
});

test("1분이 지나면 다시 열린다", () => {
  const clock = fakeClock();
  const limiter = createRateLimiter({ perMinutePerClient: 1, now: clock.now });
  limiter.check("1.2.3.4");
  assert.equal(limiter.check("1.2.3.4").allowed, false);

  clock.advance(60_001);

  assert.equal(limiter.check("1.2.3.4").allowed, true);
});

/** 한 사람이 한도를 채웠다고 다른 사람까지 막히면 안 됩니다. */
test("클라이언트마다 따로 센다", () => {
  const limiter = createRateLimiter({ perMinutePerClient: 1, now: fakeClock().now });
  limiter.check("1.1.1.1");

  assert.equal(limiter.check("1.1.1.1").allowed, false);
  assert.equal(limiter.check("2.2.2.2").allowed, true);
});

/**
 * **금액 상한입니다.** IP 를 바꿔 가며 들어와도 이 선은 넘지 못합니다.
 * 비밀키가 새는 순간 이것만 남습니다.
 */
test("하루 총량은 IP 를 바꿔도 넘지 못한다", () => {
  const limiter = createRateLimiter({
    perMinutePerClient: 100,
    perDayTotal: 3,
    now: fakeClock().now,
  });

  assert.equal(limiter.check("1.1.1.1").allowed, true);
  assert.equal(limiter.check("2.2.2.2").allowed, true);
  assert.equal(limiter.check("3.3.3.3").allowed, true);

  const verdict = limiter.check("4.4.4.4");
  assert.equal(verdict.allowed, false);
  assert.match(verdict.reason, /하루/);
});

test("하루가 지나면 총량이 초기화된다", () => {
  const clock = fakeClock();
  const limiter = createRateLimiter({ perDayTotal: 1, now: clock.now });
  limiter.check("1.1.1.1");
  assert.equal(limiter.check("1.1.1.1").allowed, false);

  clock.advance(24 * 60 * 60_000 + 1);

  assert.equal(limiter.check("1.1.1.1").allowed, true);
});

/** 요청이 들어올 때만 훑습니다. 안 치우면 Map 이 무한히 자랍니다. */
test("오래된 클라이언트를 치운다", () => {
  const clock = fakeClock();
  const limiter = createRateLimiter({
    perMinutePerClient: 5,
    perDayTotal: 100_000,
    now: clock.now,
  });

  for (let i = 0; i < 1_100; i += 1) {
    limiter.check(`10.0.${Math.floor(i / 256)}.${i % 256}`);
  }
  const before = limiter.snapshot().trackedClients;

  clock.advance(60_001);
  limiter.check("정리를 일으키는 요청");

  assert.ok(before > 1_000, `치우기 전 ${before}`);
  assert.ok(limiter.snapshot().trackedClients < before, "오래된 것이 치워져야 합니다");
});

// ── 누가 보냈는지 ───────────────────────────────────────────

/**
 * 프록시 뒤에서는 socket 주소가 언제나 프록시입니다.
 * **맨 앞** 항목이 원래 클라이언트입니다 — 뒤를 쓰면 모든 사용자가 한 사람으로 묶여
 * 한 명이 한도를 채우는 순간 전부 막힙니다.
 */
test("X-Forwarded-For 의 맨 앞을 클라이언트로 본다", () => {
  const key = clientKeyFor({
    headers: { "x-forwarded-for": "203.0.113.9, 70.41.3.18, 150.172.238.178" },
    socket: { remoteAddress: "10.0.0.1" },
  });

  assert.equal(key, "203.0.113.9");
});

test("헤더가 없으면 소켓 주소를 쓴다", () => {
  assert.equal(clientKeyFor({ headers: {}, socket: { remoteAddress: "10.0.0.1" } }), "10.0.0.1");
});

test("아무것도 없어도 터지지 않는다", () => {
  assert.equal(clientKeyFor({ headers: {} }), "unknown");
});
