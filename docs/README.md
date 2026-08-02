# CaptureTask — 문서 인덱스

**스크린샷 한 장이 할 일이 되는 iOS 앱** · 2026-08-01

이 폴더는 [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)의 산출물 구성과
[Superpowers](https://github.com/obra/superpowers)의 개발 규율을 이 프로젝트 크기(Level 2)에 맞게 적용한 결과다.

---

## 폴더 구성

번호는 읽는 순서다 (00 → 21). 폴더는 **누가 읽는가**로 나눈다.

| 폴더 | 무엇이 | 누가 |
| --- | --- | --- |
| [`product/`](product) | 00~08 — 무엇을 왜 만드나 | 제품·디자인·처음 온 사람 |
| [`engineering/`](engineering) | 09~16, 19~21 — 어떻게 만들고 무엇으로 판정하나 | 코드를 고치는 사람 |
| [`platform/`](platform) | 17~18 — 플랫폼별 조사와 기록 | 그 플랫폼을 만지는 사람 |
| [`plans/`](plans) | 스토리별 2~5분 태스크 계획 | 그 스토리를 하는 사람 |

Windows·Android 가 붙으면 `platform/` 에 문서가 하나씩 늘어난다.
번호는 계속 이어 붙인다 — 폴더가 갈려도 읽는 순서는 하나여야 한다.

---

## 어디부터 읽나

| 상황 | 읽을 것 |
| --- | --- |
| **처음 왔다** | [project-context.md](project-context.md) — 5분 요약 |
| 전체 기획을 한 번에 본다 | [통합 HTML](CaptureTask-Development-Plan.html) · [원문](INTEGRATED-DEVELOPMENT-PLAN.md) · [PDF](../output/pdf/CaptureTask-Development-Plan.pdf) |
| 제품을 이해하고 싶다 | [00-PRODUCT-BRIEF.md](product/00-PRODUCT-BRIEF.md) → [01-PRD.md](product/01-PRD.md) |
| 코드를 고치려 한다 | [09-SPEC.md](engineering/09-SPEC.md) + [10-ARCHITECTURE-SPINE.md](engineering/10-ARCHITECTURE-SPINE.md) + [16-ENGINEERING-PLAYBOOK.md](engineering/16-ENGINEERING-PLAYBOOK.md) |
| 파일이 어디 있는지 모르겠다 | [20-REPO-LAYOUT.md](engineering/20-REPO-LAYOUT.md) |
| **플랫폼을 하나 더 붙인다** | [20-REPO-LAYOUT.md §4](engineering/20-REPO-LAYOUT.md) |
| 화면을 고치려 한다 | [05-IA.md](product/05-IA.md) + [06-화면설계서.md](product/06-화면설계서.md) + [08-와이어프레임.md](product/08-와이어프레임.md) |
| 다음에 뭘 할지 알고 싶다 | [14-SPRINT.md](engineering/14-SPRINT.md) + [11-EPICS-STORIES.md](engineering/11-EPICS-STORIES.md) |
| 릴리스해도 되는지 판단한다 | [12-IMPLEMENTATION-READINESS.md](engineering/12-IMPLEMENTATION-READINESS.md) |
| 왜 이렇게 짰는지 궁금하다 | [15-RETROSPECTIVE.md](engineering/15-RETROSPECTIVE.md) |

---

## BMAD 워크플로 맵 대응

### Phase 1 — Analysis

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-product-brief` | [00-PRODUCT-BRIEF.md](product/00-PRODUCT-BRIEF.md) |

### Phase 2 — Planning

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-prd` | [01-PRD.md](product/01-PRD.md) |
| ↳ 기능 요구사항 | [02-SRS-기능요구사항.md](product/02-SRS-기능요구사항.md) |
| ↳ 비기능 요구사항 | [03-SRS-비기능요구사항.md](product/03-SRS-비기능요구사항.md) |
| ↳ 기능 명세 (MVP 우선순위·AC) | [04-SRS-기능명세서.md](product/04-SRS-기능명세서.md) |
| `bmad-ux` → `DESIGN.md` | [05-IA.md](product/05-IA.md) · [06-화면설계서.md](product/06-화면설계서.md) |
| `bmad-ux` → `EXPERIENCE.md` | [07-유저플로우.md](product/07-유저플로우.md) |
| ↳ 와이어프레임 ↔ 구현 대응 | [08-와이어프레임.md](product/08-와이어프레임.md) |
| `bmad-spec` → `SPEC.md` | [09-SPEC.md](engineering/09-SPEC.md) |

### Phase 3 — Solutioning

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-architecture` | [10-ARCHITECTURE-SPINE.md](engineering/10-ARCHITECTURE-SPINE.md) |
| `bmad-create-epics-and-stories` | [11-EPICS-STORIES.md](engineering/11-EPICS-STORIES.md) |
| `bmad-check-implementation-readiness` | [12-IMPLEMENTATION-READINESS.md](engineering/12-IMPLEMENTATION-READINESS.md) |

### Phase 4 — Implementation

| BMAD 워크플로 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-sprint-planning` → `sprint-status.yaml` | [sprint-status.yaml](sprint-status.yaml) |
| ↳ 사람이 읽는 쪽 | [14-SPRINT.md](engineering/14-SPRINT.md) |
| `bmad-retrospective` | [15-RETROSPECTIVE.md](engineering/15-RETROSPECTIVE.md) |
| **TEA** (Test Architect) | [13-TEST-STRATEGY.md](engineering/13-TEST-STRATEGY.md) |

### 보조

| BMAD 도구 | 이 프로젝트의 산출물 |
| --- | --- |
| `bmad-generate-project-context` | [project-context.md](project-context.md) |

---

## Superpowers 규율 대응

BMAD 가 **무엇을 만들지**를 정한다면, Superpowers 는 **어떻게 만들지**를 정한다.

| Superpowers 스킬 | 이 프로젝트에 적용된 곳 |
| --- | --- |
| `brainstorming` | [16 §1](engineering/16-ENGINEERING-PLAYBOOK.md) — 코드 전에 되묻기 |
| `writing-plans` | [16 §2](engineering/16-ENGINEERING-PLAYBOOK.md) — 2~5분 태스크. 실물은 [plans/](plans/) |
| `test-driven-development` | [16 §3](engineering/16-ENGINEERING-PLAYBOOK.md) + [13 §4](engineering/13-TEST-STRATEGY.md) |
| `systematic-debugging` | [16 §4](engineering/16-ENGINEERING-PLAYBOOK.md) — 재현 → 좁히기 → 근본 원인 → 증명 |
| `verification-before-completion` | [16 §5](engineering/16-ENGINEERING-PLAYBOOK.md) · [`.claude/skills/verify`](../.claude/skills/verify/SKILL.md) |
| `requesting-code-review` | [16 §6](engineering/16-ENGINEERING-PLAYBOOK.md) — 명세 준수 / 코드 품질 2단계 |
| `finishing-a-development-branch` | [16 §7](engineering/16-ENGINEERING-PLAYBOOK.md) |
| `subagent-driven-development` | [16 §8](engineering/16-ENGINEERING-PLAYBOOK.md) — AI에게 맡길 때의 규칙 |
| (요약본) | 저장소 루트 [`CLAUDE.md`](../CLAUDE.md) |

---

## 전체 문서 목록

| # | 문서 | 한 줄 |
| --- | --- | --- |
| — | [project-context.md](project-context.md) | 새 세션·새 에이전트가 먼저 읽는 5분 요약 |
| 00 | [Product Brief](product/00-PRODUCT-BRIEF.md) | 왜 만드는가 · 누구를 위한 것인가 |
| 01 | [PRD](product/01-PRD.md) | 제품 원칙 · MVP 범위 · 성공 기준 |
| 02 | [기능 요구사항 정의서](product/02-SRS-기능요구사항.md) | FR 64건 + 불변 조건 14건 |
| 03 | [비기능 요구사항 정의서](product/03-SRS-비기능요구사항.md) | 성능·프라이버시·접근성·유지보수 |
| 04 | [기능 명세서](product/04-SRS-기능명세서.md) | P0~P3 우선순위 · 수용 기준 78건 |
| 05 | [IA](product/05-IA.md) | 사이트맵 · 내비게이션 · 용어 사전 |
| 06 | [화면 설계서](product/06-화면설계서.md) | 화면 6개 · 디자인 시스템 |
| 07 | [유저 플로우 · 유스케이스](product/07-유저플로우.md) | 플로우 4개 · 유스케이스 6건 · 상태 전이도 |
| 08 | [와이어프레임 ↔ 구현](product/08-와이어프레임.md) | 화면↔코드 대응 · 남은 어긋남 5건 |
| 09 | [SPEC](engineering/09-SPEC.md) | 도메인·묶음·알림·저장·API 계약 + 추적 매트릭스 |
| 10 | [Architecture Spine](engineering/10-ARCHITECTURE-SPINE.md) | ADR 10건 · 모듈 구조 · 다음 과제 |
| 11 | [Epics & Stories](engineering/11-EPICS-STORIES.md) | 에픽 10 · 스토리 87 |
| 12 | [Implementation Readiness](engineering/12-IMPLEMENTATION-READINESS.md) | PASS / CONCERNS / FAIL 판정 |
| 13 | [Test Strategy](engineering/13-TEST-STRATEGY.md) | 위험 26건 · 자동화율 · 릴리스 게이트 |
| 14 | [Sprint](engineering/14-SPRINT.md) | 스프린트 계획 · 완료 정의 |
| 15 | [Retrospective](engineering/15-RETROSPECTIVE.md) | Sprint 1~2 회고 · 규칙으로 승격한 것 9건 |
| 16 | [Engineering Playbook](engineering/16-ENGINEERING-PLAYBOOK.md) | TDD · 디버깅 · 검증 · 리뷰 규율 |
| 17 | [온디바이스 LLM 리서치](platform/17-ONDEVICE-LLM-RESEARCH.md) | 어떤 모델을 쓸지 비교 분석 (구현 전 조사) |
| 18 | [macOS 앱](platform/18-MACOS.md) | 물방울 · 바로 넣기와 되돌리기 · 샌드박스 · 앱 아이콘 |
| 19 | [분석 품질 평가](engineering/19-EVAL.md) | 평가셋 · 첫 측정 · confidence 정정 |
| 20 | [저장소 구조](engineering/20-REPO-LAYOUT.md) | 무엇이 어디에 · **플랫폼이 하나 더 붙을 때** |
| 21 | [API 명세서](engineering/21-API.md) | **엔드포인트 · 인증 · 요청 한도 · 오류 · 스키마** |
| — | [sprint-status.yaml](sprint-status.yaml) | **기계가 읽는 스프린트 상태 (숫자의 원본)** |
| — | [plans/](plans/) | 스토리별 2~5분 태스크 계획 |
| — | [INTEGRATED-DEVELOPMENT-PLAN.md](INTEGRATED-DEVELOPMENT-PLAN.md) | HTML/PDF 생성의 기준 원문 |
| — | [report/template.html](report/template.html) | **개발 보고서** 원본 — `python3 scripts/build-report.py` 로 [한 파일 HTML](../output/report/CaptureTask-Report.html) 을 만든다 |
| — | [report/design-research.html](report/design-research.html) | **디자인 연구 보고서** 원본 — Apple 지갑·미리 알림·캘린더·일기 분석 → [한 파일 HTML](../output/report/CaptureTask-Design-Research.html) |

### 프로젝트 루트

| 파일 | 용도 |
| --- | --- |
| [`../CLAUDE.md`](../CLAUDE.md) | 작업 규칙 (사람·AI 공용) — **규칙의 원본** |
| [`../AGENTS.md`](../AGENTS.md) | CLAUDE.md 로 가는 이정표 |
| [`../server/README.md`](../server/README.md) | **백엔드 구조와 API 키를 넣는 곳** |
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
| 스토리 | 78 / 87 (90%) |
| iOS 테스트 | ✅ 130 / 130 |
| 백엔드 테스트 | ✅ 46 / 46 |
| 프로젝트 규칙 | ✅ 12건 |
| 빌드 | ✅ 경고 0 |
| R1 게이트 | ⚠️ CONCERNS — 실기기 서명 · 실제 키 E2E |
| R2 게이트 | ⛔ FAIL — 백엔드 인증 · 평가셋 (접근성 3건 해소) |

> 숫자가 [sprint-status.yaml](sprint-status.yaml) 과 어긋나면 **그쪽이 맞다.**
