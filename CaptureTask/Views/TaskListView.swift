import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var manualText = ""
    @State private var showsManualCapture = false
    @State private var reviewDraft: TaskDraft?

    var body: some View {
        NavigationStack {
            Group {
                if store.tasks.isEmpty {
                    ContentUnavailableView {
                        Label("아직 할 일이 없어요", systemImage: "checklist")
                    } description: {
                        Text("스크린샷을 공유하거나 텍스트를 붙여 넣으면 할 일 후보를 만들어요.")
                    } actions: {
                        Button("텍스트로 시험하기") {
                            showsManualCapture = true
                        }
                    }
                } else {
                    List {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task) {
                                store.toggleCompletion(for: task.id)
                            }
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("내 할 일")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.isImporting {
                        ProgressView()
                            .accessibilityLabel("공유한 스크린샷 분석 중")
                    } else if !store.pendingDrafts.isEmpty {
                        Button {
                            reviewDraft = store.pendingDrafts.first
                        } label: {
                            Label(
                                "확인할 할 일 \(store.pendingDrafts.count)개",
                                systemImage: "tray.full"
                            )
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsManualCapture = true
                    } label: {
                        Label("텍스트 추가", systemImage: "plus")
                    }
                }
            }
        }
        .onChange(of: store.pendingDrafts) { _, drafts in
            if reviewDraft == nil {
                reviewDraft = drafts.first
            }
        }
        .sheet(isPresented: $showsManualCapture) {
            NavigationStack {
                Form {
                    Section("스크린샷 속 문장을 붙여 넣어 보세요") {
                        TextEditor(text: $manualText)
                            .frame(minHeight: 160)
                    }
                }
                .navigationTitle("텍스트 분석")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            showsManualCapture = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("분석하기") {
                            let text = manualText
                            showsManualCapture = false
                            manualText = ""
                            Task {
                                await store.analyzeManualText(text)
                            }
                        }
                        .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(item: $reviewDraft) { draft in
            TaskReviewView(draft: draft) { task, sourceCaptureID in
                store.save(task, sourceCaptureID: sourceCaptureID)
                reviewDraft = nil
            } onCalendarSaved: { identifier, taskID in
                store.updateCalendarIdentifier(identifier, for: taskID)
            }
        }
        .alert(
            "처리하지 못했어요",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }

}

private struct TaskRow: View {
    let task: AssistantTask
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.state == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.state == .completed ? "완료 취소" : "완료로 표시")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .strikethrough(task.state == .completed)
                if let dueDate = task.dueDate {
                    Label(
                        dueDate.formatted(
                            date: .abbreviated,
                            time: task.hasExplicitTime ? .shortened : .omitted
                        ),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label("날짜 확인 필요", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if task.calendarEventIdentifier != nil {
                    Label("Apple 캘린더에 추가됨", systemImage: "calendar.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
