import SwiftUI

/// Remembers the last day the review was offered, so it comes up on the first open of each day only.
enum MorningReviewSchedule {
    static let key = "lastMorningReviewDay"

    static func dayStamp(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// True the first time it is asked each day.
    static func claimToday(now: Date = Date()) -> Bool {
        let today = dayStamp(for: now)
        guard UserDefaults.standard.string(forKey: key) != today else { return false }
        UserDefaults.standard.set(today, forKey: key)
        return true
    }
}

/// Shown in place of Today on the first open of the day when something was left from before.
/// One gentle question per task, and one button to let the whole lot go.
struct MorningReviewCard: View {
    @ObservedObject var store: LibraryStore
    let onFreshStart: ([TaskItem]) -> Void
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var left: [TaskItem] { store.leftFromBefore() }
    private var paused: [TaskItem] { store.pausedRepeating() }

    var body: some View {
        let count = left.count + paused.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Good morning").font(Tokens.TextRole.sectionTitle)
                Text("·  \(count) left from before").font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            .padding(.bottom, Tokens.Spacing.s)
            .accessibilityElement(children: .combine)

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    ForEach(left) { leftRow($0) }
                    ForEach(paused) { pausedRow($0) }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.s)
            }

            HStack {
                Button("Fresh start: let them all go") { onFreshStart(left + paused) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Set every task above aside. ⌘Z brings them back.")
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.brand)
                    .help("Close the review (Esc)")
            }
            .font(Tokens.TextRole.detail)
            .padding(Tokens.Spacing.m)
        }
    }

    private func leftRow(_ task: TaskItem) -> some View {
        row(title: task.title, detail: [task.space?.name, task.dueDate.map { DueLabel.text(for: $0) }].compactMap { $0 }.joined(separator: " · ")) {
            answer("Today") { store.setDue(task, Calendar.current.startOfDay(for: Date())) }
            answer("Later") { store.moveToLater(task) }
            answer("Let go") { store.setAside([task]) }
        }
    }

    private func pausedRow(_ task: TaskItem) -> some View {
        row(title: "Still want ‘\(task.title)’?", detail: "Skipped for two weeks") {
            answer("Keep") { store.keepRepeating(task) }
            answer("Let go") { store.setAside([task]) }
        }
    }

    private func row<Answers: View>(title: String, detail: String, @ViewBuilder answers: () -> Answers) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs + 2) {
            Text(title).font(Tokens.TextRole.row).lineLimit(2)
            if !detail.isEmpty {
                Text(detail).font(Tokens.TextRole.detail).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: Tokens.Spacing.xs) { answers() }
        }
        .padding(Tokens.Spacing.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
        .transition(.opacity)
    }

    private func answer(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Tokens.Motion.quick, action)
        } label: {
            Text(title)
                .font(Tokens.TextRole.detail.weight(.medium))
                .padding(.horizontal, Tokens.Spacing.s + 2)
                .padding(.vertical, Tokens.Spacing.xs)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
