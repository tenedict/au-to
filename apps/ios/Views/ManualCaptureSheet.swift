import SwiftUI

/// 스크린샷 없이 텍스트만으로 할 일을 만들어 보는 입구.
///
/// 공유 시트가 막힌 상황(App Group 미설정, 시뮬레이터)에서도 전체 흐름을 눌러 볼 수 있어야
/// 분석 품질을 검증할 수 있다.
struct ManualCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAnalyze: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("스크린샷 속 문장을 붙여 넣어 보세요") {
                    TextEditor(text: $text)
                        .frame(minHeight: 170)
                        .focused($isFocused)
                }
                Section {
                    Text("예: \"8월 12일 오후 3시 강남점 방문 예약이 확정되었습니다\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("텍스트 분석")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("분석하기") {
                        let value = text
                        dismiss()
                        onAnalyze(value)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
