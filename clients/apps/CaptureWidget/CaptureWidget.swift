import SwiftUI
import WidgetKit

private let quickCaptureURL = URL(string: "capture://quick-capture")!

private struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [QuickCaptureEntry(date: Date())], policy: .never))
    }
}

private struct CaptureWidgetView: View {
    var entry: QuickCaptureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.18))

            Text("Capture")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Tap to open the instant inbox.")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .widgetURL(quickCaptureURL)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.08),
                    Color(red: 0.12, green: 0.10, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct CaptureQuickCaptureWidget: Widget {
    let kind = "CaptureQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            CaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Capture")
        .description("Open Capture straight into the fast-entry field.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct CaptureWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureQuickCaptureWidget()
    }
}
