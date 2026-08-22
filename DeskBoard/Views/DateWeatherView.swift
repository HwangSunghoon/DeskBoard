import SwiftUI

struct DateWeatherView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var weather: WeatherService
    @AppStorage("clockStyle") private var clockStyle = "digital"

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            if clockStyle == "analog" {
                HStack(alignment: .bottom, spacing: 9) {
                    AnalogClockView(date: model.now)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.now.formatted(.dateTime.weekday(.wide)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(model.now.formatted(.dateTime.month(.wide).day()))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.bottom, 7)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.now.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.now.formatted(.dateTime.month(.wide).day()))
                        .font(.system(size: 17, weight: .medium))
                    Text(model.now.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 25, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(temperature)
                    .font(.system(size: 22, weight: .light))
                Text(condition)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let value = weather.snapshot {
                    Text("H \(value.high, specifier: "%.0f")°   L \(value.low, specifier: "%.0f")°")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Rain \(value.precipitationProbability)%")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var temperature: String {
        weather.snapshot.map { String(format: "%.0f°", $0.temperature) } ?? "—°"
    }

    private var condition: String {
        guard let code = weather.snapshot?.weatherCode else { return "Weather unavailable" }
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Conditions unavailable"
        }
    }
}

private struct AnalogClockView: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1

            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color.primary.opacity(0.32)),
                lineWidth: 1
            )

            for mark in 0..<12 {
                let angle = Double(mark) * .pi / 6 - .pi / 2
                let outer = point(center: center, radius: radius - 4, angle: angle)
                let inner = point(center: center, radius: radius - (mark.isMultiple(of: 3) ? 10 : 7), angle: angle)
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path, with: .color(Color.primary.opacity(mark.isMultiple(of: 3) ? 0.58 : 0.28)), lineWidth: 1)
            }

            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            let minute = Double(components.minute ?? 0) + Double(components.second ?? 0) / 60
            let second = Double(components.second ?? 0)
            hand(&context, center: center, radius: radius * 0.50, angle: hour * .pi / 6 - .pi / 2, width: 2.8, opacity: 0.82)
            hand(&context, center: center, radius: radius * 0.72, angle: minute * .pi / 30 - .pi / 2, width: 1.8, opacity: 0.72)
            hand(&context, center: center, radius: radius * 0.80, angle: second * .pi / 30 - .pi / 2, width: 0.8, opacity: 0.4)
        }
        .accessibilityLabel(date.formatted(date: .omitted, time: .complete))
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }

    private func hand(
        _ context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        angle: Double,
        width: CGFloat,
        opacity: Double
    ) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: angle))
        context.stroke(path, with: .color(Color.primary.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
