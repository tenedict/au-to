import Foundation

/// 앱 밖에서 앱 안의 한 자리로 들어오는 길.
///
/// 위젯·바로가기·알림이 전부 여기를 지난다. 문자열을 각자 적으면 위젯 쪽 오타가
/// **아무 오류 없이** 앱을 그냥 열어 버리고, 사용자는 눌렀는데 아무 일도 일어나지
/// 않는 것을 보게 된다. 그 오타는 실행해 보기 전까지 아무도 못 잡는다.
///
/// 값은 `project.yml` 의 `CFBundleURLTypes` 와 같아야 한다.
enum DeepLink {
    static let scheme = "capturetask"

    /// 카메라를 곧바로 연다. 잠금화면 위젯이 쓰는 길이다.
    static let capture = URL(string: "\(scheme)://capture")!

    /// 할 일 목록을 연다.
    static let tasks = URL(string: "\(scheme)://tasks")!

    /// 들어온 URL 이 무엇을 요청하는가.
    enum Destination: Equatable {
        case capture
        case tasks
    }

    /// 모르는 주소는 `nil` 이다. 아무 데나 열지 않는다 —
    /// 오타 난 링크가 조용히 홈으로 가면 위젯이 고장 난 것을 알 방법이 없다.
    static func destination(for url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "capture": return .capture
        case "tasks": return .tasks
        default: return nil
        }
    }
}
