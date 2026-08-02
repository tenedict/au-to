import SwiftUI

/// 분석 엔진과 알림 상태를 보는 자리.
///
/// 엔진을 고르는 화면이 여기 하나뿐인 이유는, 고르는 지점이 여럿이면
/// 나중에 온디바이스로 옮길 때 한 곳이 반드시 남기 때문이다 (ADR-3).
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AnalysisEngine.allCases, id: \.self) { engine in
                        engineRow(engine)
                    }
                } header: {
                    Text("분석 엔진")
                } footer: {
                    Text(
                        "스크린샷에서 글자를 읽는 것은 언제나 기기 안에서 해요. "
                            + "엔진은 그 글자를 할 일로 바꾸는 쪽만 담당해요."
                    )
                }

                Section("알림") {
                    LabeledContent("상태", value: authorizationText)
                    if let explanation = store.reminderAuthorization.explanation {
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if store.reminderAuthorization == .notDetermined {
                        Button("알림 켜기") {
                            Task { await store.enableReminders() }
                        }
                    }
                }

                Section("공유 시트로 담기") {
                    LabeledContent(
                        "상태",
                        value: store.inboxAvailability == .ready ? "쓸 수 있어요" : "쓸 수 없어요"
                    )
                    if let explanation = store.inboxAvailability.explanation {
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func engineRow(_ engine: AnalysisEngine) -> some View {
        let isSelected = store.engine == engine
        let reason = ContextUnderstanding.unavailableReason(for: engine)

        Button {
            store.engine = engine
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: engine.symbolName)
                    .font(.title3)
                    .foregroundStyle(reason == nil ? Palette.water : Palette.ink3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.title)
                        .font(.body)
                        .foregroundStyle(reason == nil ? .primary : .secondary)
                    Text(engine.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // 고를 수 없다면 왜 못 고르는지 함께 보여준다 (CLAUDE 규칙 12).
                    if let reason {
                        Label(reason, systemImage: "hammer")
                            .font(.caption)
                            .foregroundStyle(Palette.past)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                // 선택을 색으로만 알리지 않는다 (CLAUDE 규칙 13).
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.water)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var authorizationText: String {
        switch store.reminderAuthorization {
        case .authorized: return "켜져 있어요"
        case .denied: return "꺼져 있어요"
        case .notDetermined: return "아직 안 물어봤어요"
        }
    }
}
