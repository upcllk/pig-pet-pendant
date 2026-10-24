import Foundation

final class UpdateDriver {
    private(set) var timer: Timer?
    private(set) var interval: TimeInterval = 0
    private(set) var lastTick = ProcessInfo.processInfo.systemUptime
    var onTick: ((TimeInterval) -> Void)?

    func elapsed(at time: TimeInterval) -> TimeInterval {
        let elapsed = time - lastTick
        lastTick = time
        return elapsed
    }

    func resetClock() { lastTick = ProcessInfo.processInfo.systemUptime }

    func schedule(interval: TimeInterval) {
        if timer != nil && self.interval == interval { return }
        stop()
        self.interval = interval
        let ticker = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.onTick?(ProcessInfo.processInfo.systemUptime)
        }
        ticker.tolerance = interval * 0.1
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}
