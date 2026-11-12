import SwiftUI

/// A date button that opens a Helvetica month calendar in a popover.
/// Days outside `minDay…maxDay` are disabled, which is how the end date is kept
/// from preceding the start date.
struct DayPickerButton: View {
    let day: Day
    var minDay: Day?
    var maxDay: Day?
    let today: Day
    var firstWeekday = 0
    var compact = false
    var showIcon = true
    var accessibilityName: String? = nil
    let onPick: (Day) -> Void
    @ViewState private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                if showIcon {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(compact ? DayFormat.medium(day) : "\(DayFormat.weekdayShort[day.weekday]), \(DayFormat.medium(day))")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityLabel(accessibilityName ?? DayFormat.medium(day))
        .controlMarker(accessibilityName ?? DayFormat.medium(day))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            MonthCalendarView(selected: day, minDay: minDay, maxDay: maxDay, today: today, firstWeekday: firstWeekday) { picked in
                onPick(picked)
                showing = false
            }
        }
    }
}

struct MonthCalendarView: View {
    let selected: Day
    let minDay: Day?
    let maxDay: Day?
    let today: Day
    let firstWeekday: Int
    let onPick: (Day) -> Void
    @ViewState private var month: Day

    init(selected: Day, minDay: Day?, maxDay: Day?, today: Day, firstWeekday: Int = 0, onPick: @escaping (Day) -> Void) {
        self.selected = selected
        self.minDay = minDay
        self.maxDay = maxDay
        self.today = today
        self.firstWeekday = firstWeekday
        self.onPick = onPick
        _month = ViewState(wrappedValue: selected.firstOfMonth)
    }

    private let cell: CGFloat = 32

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                Text(DayFormat.monthYear(month))
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 6)
                navButton("chevron.left") { month = month.addingMonths(-1) }
                Button("Today") { month = today.firstOfMonth }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 22))
                    .font(Theme.font(12))
                navButton("chevron.right") { month = month.addingMonths(1) }
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(DayFormat.weekdayLetter[(i + firstWeekday) % 7])
                        .font(Theme.font(10))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: cell)
                }
            }
            let gridStart = Weeks.start(of: month, firstWeekday: firstWeekday)
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { d in
                            dayCell(gridStart + (week * 7 + d))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: cell * 7 + 24)
        .background(Theme.canvas)
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .regular))
                .frame(width: 14, height: 22)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 22))
    }

    @ViewBuilder
    private func dayCell(_ d: Day) -> some View {
        let enabled = (minDay.map { d >= $0 } ?? true) && (maxDay.map { d <= $0 } ?? true)
        let inMonth = d.month == month.month
        let isSelected = d == selected
        let isToday = d == today
        Button {
            onPick(d)
        } label: {
            Text("\(d.dayOfMonth)")
                .font(Theme.font(12))
                .foregroundStyle(isSelected ? Color.white
                                 : isToday ? Theme.todayAccent
                                 : inMonth ? Theme.text : Theme.tertiaryText)
                .frame(width: cell - 4, height: cell - 6)
                .background(Circle().fill(isSelected ? Theme.accent : Color.clear).frame(width: 24, height: 24))
                .overlay(Circle().strokeBorder(isToday && !isSelected ? Theme.todayAccent.opacity(0.5) : .clear, lineWidth: 1)
                    .frame(width: 24, height: 24))
                .frame(width: cell, height: cell - 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}
