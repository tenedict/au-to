import assert from "node:assert/strict";
import test from "node:test";
import {
  CLIENT_KEY_HEADER,
  ClientKeyError,
  isAuthorized,
  MIN_CLIENT_KEY_LENGTH,
  resolveClientKey,
} from "../src/auth.mjs";

const GOOD_KEY = "z".repeat(MIN_CLIENT_KEY_LENGTH);

// ── 서버가 켜질 때 ──────────────────────────────────────────

test("루프백에서는 키 없이 켤 수 있다", () => {
  assert.equal(resolveClientKey({ key: undefined, host: "127.0.0.1" }), null);
});

/**
 * "로컬은 예외" 라는 규칙이 그대로 배포로 따라가서 사고를 냅니다.
 * 외부에 노출되는 순간 키를 반드시 요구합니다.
 */
test("외부에 바인딩하면 키 없이 켜지지 않는다", () => {
  assert.throws(
    () => resolveClientKey({ key: undefined, host: "0.0.0.0" }),
    (error) => error instanceof ClientKeyError && /WHENLY_CLIENT_KEY/.test(error.message)
  );
});

test("짧은 키를 거절한다", () => {
  assert.throws(
    () => resolveClientKey({ key: "short", host: "0.0.0.0" }),
    (error) => error instanceof ClientKeyError && /짧습니다/.test(error.message)
  );
});

/**
 * 이 값은 **앱 번들에 들어갑니다.** OpenAI 키를 여기에 잘못 넣으면
 * 백엔드를 둔 이유(ADR-5)가 통째로 무너집니다.
 */
test("OpenAI 키를 클라이언트 키로 쓰려 하면 막는다", () => {
  assert.throws(
    () => resolveClientKey({ key: "sk-proj-" + "a".repeat(40), host: "0.0.0.0" }),
    (error) => error instanceof ClientKeyError && /앱 번들/.test(error.message)
  );
});

// ── 요청 하나 ───────────────────────────────────────────────

function requestWith(headerValue) {
  return { headers: headerValue === undefined ? {} : { [CLIENT_KEY_HEADER]: headerValue } };
}

test("맞는 키를 통과시킨다", () => {
  assert.equal(isAuthorized(requestWith(GOOD_KEY), GOOD_KEY), true);
});

test("틀린 키를 막는다", () => {
  assert.equal(isAuthorized(requestWith("y".repeat(MIN_CLIENT_KEY_LENGTH)), GOOD_KEY), false);
});

test("헤더가 없으면 막는다", () => {
  assert.equal(isAuthorized(requestWith(undefined), GOOD_KEY), false);
});

/** 길이가 다른 값으로 timingSafeEqual 을 부르면 예외가 납니다. 먼저 걸러야 합니다. */
test("길이가 다른 키에서 터지지 않고 막는다", () => {
  assert.equal(isAuthorized(requestWith("짧음"), GOOD_KEY), false);
  assert.equal(isAuthorized(requestWith(GOOD_KEY + "더"), GOOD_KEY), false);
});

test("빈 문자열을 막는다", () => {
  assert.equal(isAuthorized(requestWith(""), GOOD_KEY), false);
});

/** 루프백 전용 모드에서는 헤더가 없어도 통과합니다. */
test("키를 설정하지 않았으면 통과시킨다", () => {
  assert.equal(isAuthorized(requestWith(undefined), null), true);
});
