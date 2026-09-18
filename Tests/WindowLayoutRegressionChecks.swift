import Foundation

@main struct WindowLayoutRegressionChecks {
    static func main() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1280, height: 584),
            CGRect(x: -1920, y: 25, width: 1920, height: 604),
            CGRect(x: 0, y: -900, width: 1440, height: 624),
            CGRect(x: 80, y: 40, width: 1840, height: 1015),
            CGRect(x: 0, y: 0, width: 300, height: 520)
        ]
        for visible in displays {
            for isLeft in [false, true] {
                let frame = SidebarWindowGeometry.frame(visibleFrame: visible, screenWidth: visible.width, isLeft: isLeft)
                precondition(visible.contains(frame), "Sidebar must stay inside this display's usable area")
                precondition(frame.height == visible.height - 24, "No independent 560/620pt height floor")
                if isLeft { precondition(frame.minX == visible.minX + 12) }
                else { precondition(frame.maxX == visible.maxX - 12) }
            }
        }
        for width: CGFloat in [320, 380, 480] {
            let rowWidth = width - 36
            let textWidth = TodoRowMetrics.textWidth(rowWidth: rowWidth)
            precondition(textWidth + 2 * TodoRowMetrics.controlWidth + 3 * TodoRowMetrics.spacing
                         + TodoRowMetrics.minimumSpacer == rowWidth)
        }
        print("PASS: usable screen bounds, short displays, left/right and external-display origins, fixed Todo control/text widths")
    }
}
