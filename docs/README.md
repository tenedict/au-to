# CaptureTask 문서 인덱스

`travel_together`의 BMAD 산출물 구조와 Superpowers 개발 규율을 이 프로젝트의
크기와 위험에 맞게 가져왔다.

| 상황 | 읽을 문서 |
| --- | --- |
| 처음 왔다 | [project-context.md](project-context.md) |
| 전체 기획을 한 번에 본다 | [통합 HTML](CaptureTask-Development-Plan.html) · [통합 원문](08-INTEGRATED-DEVELOPMENT-PLAN.md) · [PDF](../output/pdf/CaptureTask-Development-Plan.pdf) |
| 왜/무엇을 만드는지 | [00-PRODUCT-BRIEF.md](00-PRODUCT-BRIEF.md) → [01-PRD.md](01-PRD.md) |
| 코드를 바꾸려 한다 | [02-SPEC.md](02-SPEC.md) + [03-ARCHITECTURE-SPINE.md](03-ARCHITECTURE-SPINE.md) |
| 다음 작업 | [04-EPICS-STORIES.md](04-EPICS-STORIES.md) + [06-SPRINT-READINESS.md](06-SPRINT-READINESS.md) |
| 검증 | [05-TEST-STRATEGY.md](05-TEST-STRATEGY.md) |
| 작업 규율 | [07-ENGINEERING-PLAYBOOK.md](07-ENGINEERING-PLAYBOOK.md) |

통합 HTML과 PDF는 다음 명령으로 같은 원문에서 다시 생성한다.

```bash
python3 -m pip install -r requirements-docs.txt
python3 scripts/build_development_plan.py
```
