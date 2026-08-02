import Foundation

/// 스크린샷에서 뽑은 텍스트를 할 일로 바꾸는 엔진.
///
/// 고르는 지점이 한 곳이어야 나중에 온디바이스로 옮길 때 화면·저장소·테스트를
/// 건드리지 않는다 (ADR-3). 이 열거형이 그 한 곳이다.
///
/// 비교 분석은 [`docs/17-ONDEVICE-LLM-RESEARCH.md`](../../docs/17-ONDEVICE-LLM-RESEARCH.md).
enum AnalysisEngine: String, CaseIterable, Codable, Sendable {
    /// 기본. OpenAI 키는 백엔드에만 있다.
    case backend
    /// 백엔드 없이 전체 흐름을 눌러 볼 때. 문맥을 모르므로 품질은 낮다.
    case ruleBased
    /// 예정. 자리만 잡아 둔다.
    case onDevice

    static let `default` = AnalysisEngine.backend

    var title: String {
        switch self {
        case .backend: return "OpenAI 백엔드"
        case .ruleBased: return "규칙 기반 (오프라인)"
        case .onDevice: return "온디바이스 모델"
        }
    }

    var detail: String {
        switch self {
        case .backend:
            return "가장 정확해요. 인식한 글자만 서버로 보내고, 스크린샷은 기기에 남아요."
        case .ruleBased:
            return "네트워크 없이 날짜만 찾아요. 문맥을 모르니 제목과 날짜를 꼭 확인해 주세요."
        case .onDevice:
            return "기기 안에서만 분석해요. 인식한 글자도 나가지 않아요."
        }
    }

    var symbolName: String {
        switch self {
        case .backend: return "cloud"
        // textformat.abc 는 로캘에 따라 "가나다" 글리프로 그려져 다른 아이콘과 크기가 어긋난다.
        case .ruleBased: return "function"
        case .onDevice: return "iphone.gen3"
        }
    }

    /// 기기 사정과 무관하게 **언제나** 쓸 수 있는가.
    ///
    /// 온디바이스는 기기에 물어봐야 안다. 그 판정은 `ContextUnderstanding` 이 한다 —
    /// 모델이 서비스를 알면 의존이 거꾸로 서고, 계산을 테스트하려고 프레임워크가 필요해진다 (ADR-1).
    var alwaysAvailable: Bool { self != .onDevice }

    /// 이 엔진이 만든 초안을 확인 없이 캘린더에 넣어도 되는가.
    ///
    /// 규칙 기반은 문맥을 모른다. 신뢰도를 임계값 아래로 두는 것과 별개로,
    /// **엔진 수준에서도** 자동 저장을 막는다 — 임계값 하나에만 기대면
    /// 나중에 그 값을 올리는 순간 규칙 기반 결과가 통과한다.
    var mayEverPrefillCalendar: Bool { self == .backend }
}
