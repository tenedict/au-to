# 온디바이스 LLM — 무엇을 쓸지 비교 분석

> **아직 구현하지 않았습니다.** 무엇을 쓸지 정하기 위한 조사 문서입니다.
> 설정 화면의 "온디바이스 모델"은 자리만 잡아 두고 비활성 상태입니다.
>
> 조사 시점 2026-08-01 · 이 분야는 분기 단위로 바뀝니다. 구현 직전에 다시 확인하세요.

관련 — [ADR-10](../engineering/10-ARCHITECTURE-SPINE.md) · [`AnalysisEngine`](../../core/swift/Models/AnalysisEngine.swift)

---

## 0. 세 줄 요약

1. **Apple Foundation Models 프레임워크가 1순위입니다.** 모델 다운로드 0MB, 한국어 공식 지원,
   guided generation 이 우리 스키마를 그대로 강제합니다.
2. 다만 **iPhone 15 Pro 이상에서만** 돕니다. 그 아래 기기에는 백엔드가 계속 필요합니다.
3. 직접 모델을 싣는 길(MLX + Qwen3)은 **품질보다 앱 용량과 발열이 먼저 문제**가 됩니다.
   1.5GB 를 더 받게 하는 대가로 얻는 것이 무엇인지 먼저 답해야 합니다.

---

## 1. 우리가 시키려는 일

비교 전에 우리 과제부터 정확히 적습니다. "LLM 성능"이 아니라 **이 과제의 성능**이 기준입니다.

```
입력   OCR 로 뽑은 한국어 텍스트 (보통 20~300자, 예약 문자·공지·안내)
출력   { title, notes, due_at, has_explicit_time, confidence, evidence, ambiguities }
```

| 요구 | 왜 중요한가 |
| --- | --- |
| **한국어 상대 날짜 추론** | "다음 주 화요일", "이번 달 말일", "내일모레". 여기서 틀리면 제품이 무너집니다 |
| **구조화 출력** | 스키마를 못 지키면 앱이 파싱을 못 합니다 |
| **모른다고 말하기** | 날짜가 모호하면 `due_at: null` + `ambiguities`. **지어내면 안 됩니다** |
| **짧은 지연** | 공유 → 확인 완료 15초 목표 (NFR-PERF-04) |
| 긴 문맥 | ❌ 필요 없습니다. 300자면 충분합니다 |
| 세상 지식 | ❌ 필요 없습니다. 원문에 없는 사실을 만들면 안 됩니다 |

**이 과제는 추출·분류입니다.** 큰 모델이 필요한 종류의 일이 아닙니다.
그래서 3B급이 현실적인 후보가 됩니다.

---

## 2. 후보

### A. Apple Foundation Models 프레임워크 ⭐ 1순위

| | |
| --- | --- |
| 무엇 | iOS 에 내장된 ~3B 모델을 Swift API 로 직접 부르기 |
| 모델 다운로드 | **0MB** — OS 에 이미 있습니다 |
| 한국어 | ✅ 공식 지원 (PFIGSCJK 에 한국어 포함) |
| 구조화 출력 | ✅ guided generation — 제약 디코딩으로 Swift 타입을 보장 |
| 기기 요구 | **iPhone 15 Pro 이상 (A17 Pro+)**, Apple Intelligence 켜짐 |
| 지연 (iPhone 15 Pro) | TTFT ≈ 0.6ms/토큰, 생성 ≈ 30 토큰/초 |
| 비용 | 0 |

**왜 1순위인가**

우리 과제가 Apple 이 이 모델의 강점이라고 못 박은 것과 정확히 겹칩니다 —
*summarization, entity extraction, text understanding, classification, short-form generation.*
그리고 guided generation 이 우리의 `TaskDraft` 스키마를 **그대로** 강제합니다.
지금 백엔드에서 `strict: true` 로 하는 일을 프레임워크가 대신합니다.

**한계 — 이게 결정적입니다**

| | |
| --- | --- |
| 기기 | iPhone 14 이하에서는 `LanguageModelSession` 생성 자체가 실패합니다 |
| 상태 | `.unavailable(.deviceNotEligible)` · `.appleIntelligenceNotEnabled` · `.modelNotReady` |
| 문맥 | 긴 문맥 모드가 사실상 없습니다 (우리에겐 문제 없음) |
| 지식 | 범용 챗봇용이 아닙니다 (우리에겐 문제 없음) |

> **그래서 "온디바이스로 전환"이 아니라 "온디바이스를 추가"입니다.**
> 백엔드는 못 쓰는 기기를 위해 계속 남아야 합니다. 지금 `AnalysisEngine` 을
> 세 갈래로 둔 구조가 그대로 맞습니다.

**2026 년에 바뀐 것** — WWDC 2026 에서 프레임워크가 **아무 LLM 백엔드나 받도록 열렸습니다.**
`LanguageModel` · `LanguageModelExecutor` 두 프로토콜을 구현하면 됩니다.
`MLXLanguageModel` 이 함께 나와서 HuggingFace 의 MLX 포맷 모델을 같은 API 로 부를 수 있습니다.

이게 우리에게 주는 의미가 큽니다. **Foundation Models API 하나에 붙여 두면
나중에 모델을 바꿔도 우리 코드는 그대로입니다.** 아래 B·C 도 같은 API 뒤로 들어옵니다.

### B. MLX + 직접 고른 모델 (Qwen3 계열)

| | |
| --- | --- |
| 무엇 | Apple 의 배열 프레임워크. 모델을 앱이 직접 싣거나 받습니다 |
| 성능 | 14B 미만에서 llama.cpp 대비 **20~87% 빠름**. MLX-Swift 디코드 1.4~1.8배 |
| 검증 | 2026-03-30 Ollama 가 Apple Silicon 추론 엔진을 MLX 로 전환 |
| 한국어 | Qwen3 1.7B 가 35개 언어 학습 — 한국어 포함, 이 크기대에서 다국어 최강으로 꼽힘 |
| 기기 요구 | 넓음 (모델 크기에 달림) |

**비용이 여기 있습니다**

| 모델 크기 | 4비트 양자화 | 런타임 RAM |
| --- | --- | --- |
| 1.7B | ~1.0GB | ~1.5GB |
| 3B | ~1.5~2.0GB | ~2GB |
| 4B | ~2.5GB | ~3GB |

8GB iPhone 에서 실사용 가능한 여유는 **4~5GB** 정도입니다. 3B 급까지가 현실적입니다.

> **앱 용량 1.5GB 를 더 받게 하는 대가로 무엇을 얻는지** 먼저 답해야 합니다.
> Foundation Models 를 쓸 수 있는 기기라면 0MB 로 같은 일을 합니다.
> B 가 의미 있는 경우는 **Foundation Models 를 못 쓰는 기기까지 오프라인으로 덮고 싶을 때**뿐입니다.

### C. llama.cpp

| | |
| --- | --- |
| 강점 | 넓은 모델 호환, 긴 문맥, 크로스 플랫폼, 안정성 |
| 약점 | Apple Silicon 에서 MLX 보다 느림 (27B 이상에서 수렴) |
| 우리 판단 | **크로스 플랫폼 계획이 없고 긴 문맥도 안 씁니다.** MLX 대비 이점이 없습니다 |

### D. 서버 그대로 (현재)

| | |
| --- | --- |
| 강점 | 가장 정확, 앱 용량 0, 모델 교체가 서버 설정 한 줄 |
| 약점 | 네트워크 필요, 호출 비용, **인식한 글자가 기기를 떠남** |

---

## 3. 한 줄 비교

| | Foundation Models | MLX + Qwen3 3B | llama.cpp | 백엔드 (현재) |
| --- | --- | --- | --- | --- |
| 앱 용량 추가 | **0MB** | ~1.5GB | ~1.5GB | 0MB |
| 한국어 | ✅ 공식 | ✅ 강함 | 모델 나름 | ✅ |
| 구조화 출력 | ✅ guided generation | 직접 구현 | 직접 구현 | ✅ strict schema |
| 글자가 기기를 떠나나 | ❌ | ❌ | ❌ | **✅ 떠남** |
| 오프라인 | ✅ | ✅ | ✅ | ❌ |
| 호출 비용 | 0 | 0 | 0 | 있음 |
| 기기 제약 | **15 Pro+** | RAM 6GB+ | RAM 6GB+ | 없음 |
| 정확도 (예상) | 중상 | 중 | 중 | **상** |
| 구현 난이도 | **낮음** | 높음 | 높음 | (완료) |

---

## 4. 권고

### 순서

```
1단계  Foundation Models 를 "추가"한다        ← 다음에 할 것
       · 쓸 수 있는 기기에서만 고를 수 있게
       · 못 쓰는 기기에는 왜 못 쓰는지 적는다 (CLAUDE 규칙 12)
       · 백엔드는 기본으로 남는다

2단계  같은 평가셋으로 백엔드와 나란히 돌린다 (shadow mode)
       · 날짜 정확도 · 제목 무수정률 · p95 지연

3단계  기준을 넘으면 기본값을 바꾼다
       · 넘지 못하면 그대로 둔다. 바꾸는 게 목표가 아니다

보류   MLX + 자체 모델
       · Foundation Models 를 못 쓰는 기기까지 오프라인으로 덮어야 할 때만
       · 그 전에 "1.5GB 를 받게 할 만한가"에 답이 있어야 한다
```

### 전환 조건 (ADR-10 과 동일)

1. 익명화 평가셋 50건과 기대 JSON 이 있다 (`S-2.3`)
2. 날짜 정확도가 백엔드 대비 **95% 이상**
3. p95 지연 **3초 이내**

> **지금은 2·3번을 판단할 기준선 자체가 없습니다.** `S-2.3` 이 먼저입니다.
> 평가셋 없이 온디바이스로 옮기면 "좋아졌는지 나빠졌는지" 를 아무도 말할 수 없습니다.

### 코드에 미리 해 둔 것

```swift
// AnalysisEngine.swift — 고르는 지점이 여기 하나뿐입니다
enum AnalysisEngine { case backend, ruleBased, onDevice }

// ContextUnderstandingService.swift
static func make(_ engine: AnalysisEngine) -> any ContextUnderstandingService
```

붙일 때 건드릴 파일은 **둘**입니다 — `AnalysisEngine.isAvailable` 을 기기 판정으로 바꾸고,
`make(_:)` 에 구현 한 줄을 넣습니다. 화면·저장소·테스트는 그대로입니다.

---

## 5. 붙일 때 주의할 것

| | |
| --- | --- |
| **기기 판정을 하드코딩하지 않는다** | `SystemLanguageModel.availability` 를 묻습니다. 기종 문자열로 판정하면 새 기기마다 고쳐야 합니다 |
| **조용히 백엔드로 떨어지지 않는다** | INV-AI-1. 품질이 말없이 바뀌면 사용자는 AI 가 나빠졌다고 생각하고 우리는 원인을 모릅니다 |
| **Share Extension 에서 돌리지 않는다** | ADR-2. 모델 로딩은 Extension 이 죽는 가장 빠른 길입니다 |
| **`confidence` 를 그대로 믿지 않는다** | 온디바이스 모델의 자기 신뢰도는 백엔드와 눈금이 다릅니다. 임계값을 다시 재야 합니다 |
| **첫 호출의 모델 로딩 시간을 잰다** | 콜드 스타트가 NFR-PERF-04(15초)를 먹을 수 있습니다 |
| **발열과 배터리를 잰다** | 여러 장을 연달아 분석할 때 드러납니다 |

---

## 6. 출처

조사 2026-08-01. 이 분야는 분기 단위로 바뀝니다.

- [Apple Intelligence Foundation Language Models (Tech Report 2025)](https://arxiv.org/html/2507.13575v3)
- [Introducing Apple's On-Device and Server Foundation Models — Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models)
- [Updates to Apple's On-Device and Server Foundation Language Models](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Exploring the Foundation Models framework](https://www.createwithswift.com/exploring-the-foundation-models-framework/)
- [WWDC 2026 — Apple Just Opened the Foundation Models Framework to Any LLM Provider](https://dev.to/arshtechpro/wwdc-2026-apple-just-opened-the-foundation-models-framework-to-any-llm-provider-5ejn)
- [How to Fall Back Gracefully When Apple Intelligence Isn't Available](https://dev.to/arshtechpro/how-to-fall-back-gracefully-when-apple-intelligence-isnt-available-48j)
- [Apple Core AI vs Foundation Models vs MLX: Which iOS 27 AI Framework](https://andrew.ooo/answers/apple-core-ai-vs-foundation-models-vs-mlx-ios-27-framework-june-2026/)
- [MLX vs llama.cpp on Apple Silicon: Benchmarks, M5 Neural Accelerators, and Why Ollama Switched](https://yage.ai/share/mlx-apple-silicon-en-20260331.html)
- [apple-silicon-llm-bench — 재현 가능한 벤치마크 (MLX · llama.cpp · CoreML · Foundation Models)](https://github.com/john-rocky/apple-silicon-llm-bench)
- [MLX vs llama.cpp on Apple Silicon: Which Runtime to Use](https://groundy.com/articles/mlx-vs-llamacpp-on-apple-silicon-which-runtime-to-use-for-local-llm-inference/)
- [Best Mobile LLM 2026: Phi-4 Mini vs Gemma 3 vs SmolLM](https://www.promptquorum.com/power-local-llm/mobile-llm-models-phi4-gemma-smollm)
- [The Best Open-Source Small Language Models (SLMs) in 2026 — BentoML](https://www.bentoml.com/blog/the-best-open-source-small-language-models)
- [How to Run LLMs Locally on Your iPhone in 2026](https://dev.to/alichherawalla/how-to-run-llms-locally-on-your-iphone-in-2026-completely-offline-no-subscription-4b3a)
- [Two Entitlements to Boost Memory Allocation for iOS Apps](https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en)
