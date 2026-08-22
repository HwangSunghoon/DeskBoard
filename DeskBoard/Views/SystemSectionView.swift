import SwiftUI

struct SystemSectionView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(text: "System")
            HStack(spacing: 14) {
                metric("CPU", value: percent(monitor.snapshot.cpuUsage), progress: monitor.snapshot.cpuUsage)
                metric("RAM", value: percent(monitor.snapshot.memoryUsage), progress: monitor.snapshot.memoryUsage)
                metric("BAT", value: battery, progress: batteryProgress)
            }
            HStack(spacing: 12) {
                networkMetric("Download", value: rate(monitor.snapshot.downloadBytesPerSecond))
                Spacer()
                networkMetric("Upload", value: rate(monitor.snapshot.uploadBytesPerSecond))
            }
            Text("Uptime \(duration(monitor.snapshot.uptime))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private var battery: String {
        guard let value = monitor.snapshot.batteryPercent else { return "—" }
        return "\(value)%\(monitor.snapshot.isCharging ? " ⚡︎" : "")"
    }
    private var batteryProgress: Double {
        Double(monitor.snapshot.batteryPercent ?? 0) / 100
    }
    private func rate(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes)) + "/s"
    }
    private func duration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h \(minutes)m"
    }

    private func metric(_ label: String, value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(value).monospacedDigit()
            }
            FixedMetricBar(value: progress)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkMetric(_ label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
    }
}

private struct FixedMetricBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .labelColor).opacity(0.14))
                Capsule()
                    .fill(Color(nsColor: .labelColor).opacity(0.62))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
    }
}
