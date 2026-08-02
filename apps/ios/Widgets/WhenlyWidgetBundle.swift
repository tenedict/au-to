import SwiftUI
import WidgetKit

/// 위젯 확장의 입구.
///
/// 위젯이 둘이고 하는 일이 다르다.
///
/// | `NextTaskWidget` | 홈 화면 — **읽는다.** 다음 일정이 무엇인지 |
/// | `CaptureLockWidget` | 잠금화면 — **담는다.** 눌러서 곧바로 찍기 |
///
/// 둘을 하나로 합치지 않는다. 홈 화면 위젯을 눌러도 카메라가 열리면, 일정을
/// 확인하려고 누른 사용자가 매번 카메라를 닫아야 한다.
@main
struct WhenlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextTaskWidget()
        CaptureLockWidget()
    }
}
