import SwiftUI

struct TaskTile: View {
    let task: TrackedTask
    let time: TimeInterval
    var opensCodex = true

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(statusColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
                    .frame(width: 66, height: 78)

                Text(task.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 57, height: 18)
                    .offset(y: 5)

                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(red: 0.19, green: 0.20, blue: 0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .frame(width: 74, height: 52)
                    .offset(y: 26)

                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(">")
                    Text(cursor).opacity(cursorOpacity)
                }
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: 34)
            }
            .frame(width: 74, height: 78)

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .scaleEffect(dotScale)
        }
        .frame(width: 74)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.title): \(task.state.title)")
        .accessibilityHint(opensCodex ? "Open this task in Codex" : "Demo preview; completed tasks can be acknowledged")
        .accessibilityAddTraits(.isButton)
    }

    private var cursor: String {
        switch task.state {
        case .needsInput: return "?"
        case .ready: return "."
        case .blocked: return "!"
        case .offline, .idle, .running: return "_"
        }
    }

    private var statusColor: Color {
        switch task.state {
        case .offline: return Color(red: 0.78, green: 0.78, blue: 0.79)
        case .idle: return Color(red: 0.69, green: 0.69, blue: 0.70)
        case .running: return Color(red: 0.28, green: 0.62, blue: 1.0)
        case .needsInput: return Color(red: 1.0, green: 0.68, blue: 0.10)
        case .ready: return Color(red: 0.28, green: 0.82, blue: 0.30)
        case .blocked: return Color(red: 1.0, green: 0.68, blue: 0.10)
        }
    }

    private var cursorOpacity: Double {
        switch task.state {
        case .running:
            return sin(time * .pi * 1.6) > 0 ? 1 : 0.22
        case .needsInput:
            let phase = time.truncatingRemainder(dividingBy: 1.8)
            return phase < 0.17 || (phase > 0.31 && phase < 0.48) ? 1 : 0.35
        default:
            return 1
        }
    }

    private var dotScale: Double {
        switch task.state {
        case .running: return 0.92 + 0.08 * (0.5 + 0.5 * sin(time * .pi * 1.2))
        case .needsInput: return cursorOpacity > 0.9 ? 1.12 : 0.94
        default: return 1
        }
    }
}
