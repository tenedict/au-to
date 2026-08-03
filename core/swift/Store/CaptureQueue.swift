import Foundation

/// 들어온 캡처를 **뒤에서** 읽고 등록한다.
///
/// ## 왜 화면이 아니라 여기가 들고 있나
///
/// 예전에는 물방울 화면(`DropletView`)이 떨어진 이미지를 직접 처리했다. 그런데
/// 물방울을 누르면 대시보드 창이 뜨고, 그 순간 화면이 다시 그려지면서 처리를 이어
/// 가던 자리가 사라졌다 — 사용자에게는 **끌어다 놓자마자 앱에 들어가면 등록이
/// 취소되는 것**으로 보였다.
///
/// 그래서 일을 화면에서 떼어 앱이 사는 동안 함께 사는 객체로 옮겼다.
/// 창이 열리든 닫히든, 물방울을 감추든, 이 줄은 끊기지 않는다.
///
/// ## 하는 일이 셋이다
///
/// | 받아 두기 | 떨어진 순간 **바이트를 복사**해 둔다. 파인더가 준 파일 URL 의 샌드박스 접근권은 드롭이 끝나면 사라진다 |
/// | 속도 지키기 | 1분에 열 개를 넘기지 않는다 (`IntakeRate`). 앞의 몇 개는 기다리지 않는다 |
/// | 알리기 | 끝나면 알림 하나. 화면에 진행 표시를 두지 않는다 — 사용자는 이미 다른 일을 하고 있다 |
@MainActor
final class CaptureQueue: ObservableObject {

    /// 아직 읽지 못한 것의 개수.
    ///
    /// 물방울은 이 값을 쓰지 않는다 (진행 표시를 없앴다). 대시보드가 아래 상태 줄에서
    /// "몇 장이 남았는지" 만 조용히 말한다 — 물어보는 사람에게만 보이면 된다.
    @Published private(set) var waiting = 0

    private let store: TaskStore
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var pending: [Item] = []
    private var isDraining = false
    private var rate = IntakeRate()

    /// 상자에 담아 둔 캡처인지, 메모리에만 있는 이미지인지.
    private struct Item {
        let imageData: Data
        let captureID: UUID?
    }

    init(
        store: TaskStore,
        now: @escaping () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.store = store
        self.now = now
        self.sleep = sleep
    }

    /// 이미지 한 장을 줄에 세운다. 부르는 쪽은 기다리지 않는다.
    ///
    /// **먼저 상자에 담고** 그 다음에 줄에 세운다. 담기가 먼저여야 도중에 앱이
    /// 죽어도 캡처가 남고, 다음 실행이 이어서 처리한다 (ADR-2).
    /// 상자를 못 쓰면 메모리로라도 처리한다 — App Group 설정 때문에 사용자가
    /// 끌어다 놓은 스크린샷을 버리지는 않는다.
    func enqueue(imageData: Data) {
        var captureID: UUID?
        do {
            captureID = try SharedInbox.enqueue(imageData: imageData).id
        } catch {
            // 담지 못했다는 사실만 알리고 처리는 계속한다.
            store.lastErrorMessage = error.localizedDescription
        }
        enqueue(imageData: imageData, captureID: captureID)
    }

    /// 이미 상자에 담긴 캡처를 줄에 세운다.
    func enqueue(imageData: Data, captureID: UUID?) {
        pending.append(Item(imageData: imageData, captureID: captureID))
        waiting = pending.count
        drain()
    }

    /// 줄을 하나씩 비운다.
    ///
    /// 한 번에 하나씩만 돈다. 병렬로 돌리면 속도 제한을 지켜도 백엔드에는 한꺼번에
    /// 닿고, OCR 이 서로 CPU 를 뺏어 전체가 더 느려진다.
    private func drain() {
        guard !isDraining else { return }
        isDraining = true
        Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        defer { isDraining = false }

        while !pending.isEmpty {
            // 문턱을 넘었으면 기다린다. 앞의 몇 개는 여기서 0 을 받아 곧바로 지나간다.
            let wait = rate.delay(at: now())
            if wait > 0 { await sleep(wait) }

            let item = pending.removeFirst()
            waiting = pending.count
            rate.record(at: now())

            let result = await store.intake(item.imageData, captureID: item.captureID)
            announce(result, captureID: item.captureID)
        }
    }

    /// 무엇이 어떻게 됐는지 알림 **하나로** 말한다.
    ///
    /// 알림이 둘로 갈리던 때가 있었다 — "등록했어요" 와 "확인해 주세요". 그런데
    /// 지금은 애매한 것도 등록되므로 둘은 같은 사건의 두 면이고, 나눠 보내면
    /// 한 번 놓은 스크린샷에 알림이 두 개 온다.
    ///
    /// 그래서 하나에 담는다. "등록했어요 · 무엇이 언제 · (필요하면) 눌러서 확인해 주세요".
    private func announce(_ result: TaskStore.IntakeResult, captureID: UUID?) {
        if result.isEmpty {
            CaptureNotice.postNothingFound(
                captureID: captureID,
                reason: result.errorMessage
            )
        } else {
            CaptureNotice.postFiled(result.filed, captureID: captureID)
        }
    }
}
