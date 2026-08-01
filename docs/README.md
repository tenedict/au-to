# CaptureTask — 문서 인덱스

**스크린샷 한 장이 할 일이 되는 iOS 앱** · 2026-08-01

이 폴더는 [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)의 산출물 구성과
[Superpowers](https://github.com/obra/superpowers)의 개발 규율을 이 프로젝트 크기(Level 2)에 맞게 적용한 결과다.

---

## 어디부터 읽나

| 상황 | 읽을 것 |
| --- | --- |
| **처음 왔다** | [project-context.md](project-context.md) — 5분 요약 |
| 전체 기획을 한 번에 본다 | [통합 HTML](CaptureTask-Development-Plan.html) · [원문](INTEGRATED-DEVELOPMENT-PLAN.md) · [PDF](../output/pdf/CaptureTask-Development-Plan.pdf) |
| 제품을 이해하고 싶다 | [00-PRODUCT-BRIEF.md](00-PRODUCT-BRIEF.md) → [01-PRD.md](01-PRD.md) |
| 코드를 고치려 한다 | [09-SPEC.md](09-SPEC.md) + [10-ARCHITECTURE-SPINE.md](10-ARCHITECTURE-SPINE.md) + [16-ENGINEERING-PLAYBOOK.md](16-ENGINEERING-PLAYBOOK.md) |
| 화면을 고치려 한다 | [05-IA.md](05-IA.md) + [06-화면설계서.md](06-화면설계서.md) + [08-와이어프레임.md](08-와이어프레임.md) |
| 다음에 뭘 할지 알고 싶다 | [14-SPRINT.md](14-SPRINT.md) + [11-EPICS-STORIES.md](11-EPICS-STORIES.md) |
| 릴리스해도 되는지 판단한다 | [12-IMPLEMENTATION-READINESS.md](12-IMPLEMENTATION-READINESS.md) |
| 왜 이렇게 짰는지 궁금하다 | [15-RETROSPECTIVE.md](15-RETROSPECTIVE.md) |

---

## BMAD 워크플로 맵 대응

### Phase 1 — Analysis

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-product-brief` | [00-PRODUCT-BRIEF.md](00-PRODUCT-BRIEF.md) |

### Phase 2 — Planning

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-prd` | [01-PRD.md](01-PRD.md) |
| ↳ 기능 요구사항 | [02-SRS-기능요구사항.md](02-SRS-기능요구사항.md) |
| ↳ 비기능 요구사항 | [03-SRS-비기능요구사항.md](03-SRS-비기능요구사항.md) |
| ↳ 기능 명세 (MVP 우선순위·AC) | [04-SRS-기능명세서.md](04-SRS-기능명세서.md) |
| `bmad-ux` → `DESIGN.md` | [05-IA.md](05-IA.md) · [06-화면설계서.md](06-화면설계서.md) |
| `bmad-ux` → `EXPERIENCE.md` | [07-유저플로우.md](07-유저플로우.md) |
| ↳ 와이어프레임 ↔ 구현 대응 | [08-와이어프레임.md](08-와이어프레임.md) |
| `bmad-spec` → `SPEC.md` | [09-SPEC.md](09-SPEC.md) |

### Phase 3 — Solutioning

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-architecture` | [10-ARCHITECTURE-SPINE.md](10-ARCHITECTURE-SPINE.md) |
| `bmad-create-epics-and-stories` | [11-EPICS-STORIES.md](11-EPICS-STORIES.md) |
| `bmad-check-implementation-readiness` | [12-IMPLEMENTATION-READINESS.md](12-IMPLEMENTATION-READINESS.md) |

### Phase 4 — Implementation

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-sprint-planning` → `sprint-status.yaml` | [sprint-status.yaml](sprint-status.yaml) |
| ↳ 사람이 읽는 쪽 | [14-SPRINT.md](14-SPRINT.md) |
| `bmad-retrospective` | [15-RETROSPECTIVE.md](15-RETROSPECTIVE.md) |
| **TEA** (Test Architect) | [13-TEST-STRATEGY.md](13-TEST-STRATEGY.md) |

### 보조

| BMAD 도구 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-generate-project-context` | [project-context.md](project-context.md) |

---

## Superpowers 규율 대응

BMAD 가 **무엇을 만들지**를 정한다면, Superpowers 는 **어떻게 만들지**를 정한다.

| Superpowers 스킬 | 이 프로젝트에 적용된 곳 |
| --- | --- |
| `brainstorming` | [16 §1](16-ENGINEERING-PLAYBOOK.md) — 코드 전에 되묻기 |
| `writing-plans` | [16 §2](16-ENGINEERING-PLAYBOOK.md) — 2~5분 태스크. 실물은 [plans/](plans/) |
| `test-driven-development` | [16 §3](16-ENGINEERING-PLAYBOOK.md) + [13 §4](13-TEST-STRATEGY.md) |
| `systematic-debugging` | [16 §4](16-ENGINEERING-PLAYBOOK.md) — 재현 → 좁히기 → 근본 원인 → 증명 |
| `verification-before-completion` | [16 §5](16-ENGINEERING-PLAYBOOK.md) · [`.claude/skills/verify`](../.claude/skills/verify/SKILL.md) |
| `requesting-code-review` | [16 §6](16-ENGINEERING-PLAYBOOK.md) — 명세 준수 / 코드 품질 2단계 |
| `finishing-a-development-branch` | [16 §7](16-ENGINEERING-PLAYBOOK.md) |
| `subagent-driven-development` | [16 §8](16-ENGINEERING-PLAYBOOK.md) — AI에게 맡길 때의 규칙 |
| (요약본) | 저장소 루트 [`CLAUDE.md`](../CLAUDE.md) |

---

## 전체 문서 목록

| # | 문서 | 한 줄 |
| --- | --- | --- |
| — | [project-context.md](project-context.md) | 새 세션·새 에이전트가 먼저 읽는 5분 요약 |
| 00 | [Product Brief](00-PRODUCT-BRIEF.md) | 왜 만드는가 · 누구를 위한 것인가 |
| 01 | [PRD](01-PRD.md) | 제품 원칙 · MVP 범위 · 성공 기준 |
| 02 | [기능 요구사항 정의서](02-SRS-기능요구사항.md) | FR 64건 + 불변 조건 14건 |
| 03 | [비기능 요구사항 정의서](03-SRS-비기능요구사항.md) | 성능·프라이버시·접근성·유지보수 |
| 04 | [기능 명세서](04-SRS-기능명세서.md) | P0~P3 우선순위 · 수용 기준 78건 |
| 05 | [IA](05-IA.md) | 사이트맵 · 내비게이션 · 용어 사전 |
| 06 | [화면 설계서](06-화면설계서.md) | 화면 6개 · 디자인 시스템 |
| 07 | [유저 플로우 · 유스케이스](07-유저플로우.md) | 플로우 4개 · 유스케이스 6건 · 상태 전이도 |
| 08 | [와이어프레임 ↔ 구현](08-와이어프레임.md) | 화면↔코드 대응 · 남은 어긋남 5건 |
| 09 | [SPEC](09-SPEC.md) | 도메인·묶음·알림·저장·API 계약 + 추적 매트릭스 |
| 10 | [Architecture Spine](10-ARCHITECTURE-SPINE.md) | ADR 10건 · 모듈 구조 · 다음 과제 |
| 11 | [Epics & Stories](11-EPICS-STORIES.md) | 에픽 10 · 스토리 80 |
| 12 | [Implementation Readiness](12-IMPLEMENTATION-READINESS.md) | PASS / CONCERNS / FAIL 판정 |
| 13 | [Test Strategy](13-TEST-STRATEGY.md) | 위험 26건 · 자동화율 · 릴리스 게이트 |
| 14 | [Sprint](14-SPRINT.md) | 스프린트 계획 · 완료 정의 |
| 15 | [Retrospective](15-RETROSPECTIVE.md) | Sprint 1~2 회고 · 규칙으로 승격한 것 9건 |
| 16 | [Engineering Playbook](16-ENGINEERING-PLAYBOOK.md) | TDD · 디버깅 · 검증 · 리뷰 규율 |
| 17 | [온디바이스 LLM 리서치](17-ONDEVICE-LLM-RESEARCH.md) | 어떤 모델을 쓸지 비교 분석 (구현 전 조사) |
| 18 | [macOS 앱](18-MACOS.md) | 물방울 · 바로 넣기와 되돌리기 · 샌드박스 |
| — | [sprint-status.yaml](sprint-status.yaml) | **기계가 읽는 스프린트 상태 (숫자의 원본)** |
| — | [plans/](plans/) | 스토리별 2~5분 태스크 계획 |
| — | [INTEGRATED-DEVELOPMENT-PLAN.md](INTEGRATED-DEVELOPMENT-PLAN.md) | HTML/PDF 생성의 기준 원문 |

### 프로젝트 루트

| 파일 | 용도 |
| --- | --- |
| [`../CLAUDE.md`](../CLAUDE.md) | 작업 규칙 (사람·AI 공용) — **규칙의 원본** |
| [`../AGENTS.md`](../AGENTS.md) | CLAUDE.md 로 가는 이정표 |
| [`../backend/README.md`](../backend/README.md) | **백엔드 구조와 API 키를 넣는 곳** |
| [`../scripts/verify.sh`](../scripts/verify.sh) | 사람·AI·훅·CI 가 함께 쓰는 검증 |
| [`../scripts/check-project-rules.sh`](../scripts/check-project-rules.sh) | 이 프로젝트만의 규칙 (`--list` 로 목록) |
| [`../.claude/skills/verify/SKILL.md`](../.claude/skills/verify/SKILL.md) | 완료 판정 스킬 |

---

## 문서를 다시 만드는 법

통합 HTML 과 PDF 는 같은 원문에서 생성한다.

```bash
python3 -m pip install -r requirements-docs.txt
python3 scripts/build_development_plan.py
```

---

## 현재 상태

| 항목 | 값 |
| --- | --- |
| 릴리스 단계 | **R0 PASS** · MVP 기능 완성 |
| 스토리 | 72 / 80 (90%) |
| iOS 테스트 | ✅ 102 / 102 |
| 백엔드 테스트 | ✅ 15 / 15 |
| 프로젝트 규칙 | ✅ 11건 |
| 빌드 | ✅ 경고 0 |
| R1 게이트 | ⚠️ CONCERNS — 실기기 서명 · 실제 키 E2E |
| R2 게이트 | ⛔ FAIL — 백엔드 인증 · 평가셋 (접근성 3건 해소) |

> 숫자가 [sprint-status.yaml](sprint-status.yaml) 과 어긋나면 **그쪽이 맞다.**
