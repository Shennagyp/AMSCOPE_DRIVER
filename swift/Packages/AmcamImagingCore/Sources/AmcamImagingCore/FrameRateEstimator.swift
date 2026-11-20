/// Computes a smoothed frame-rate estimate from monotonic host timestamps.
public struct FrameRateEstimator: Sendable {
    public let sampleWindow: Int
    private var intervals: [Double] = []
    private var previousTimestamp: Double?

    public init(sampleWindow: Int = 30) {
        self.sampleWindow = max(1, sampleWindow)
    }

    /// Records a timestamp and returns an estimate once at least one valid interval exists.
    /// Non-finite or non-increasing timestamps are ignored and do not corrupt the baseline.
    public mutating func record(timestamp: Double) -> Double? {
        guard timestamp.isFinite else { return nil }
        guard let previousTimestamp else {
            self.previousTimestamp = timestamp
            return nil
        }
        guard timestamp > previousTimestamp else { return nil }

        intervals.append(timestamp - previousTimestamp)
        if intervals.count > sampleWindow {
            intervals.removeFirst(intervals.count - sampleWindow)
        }
        self.previousTimestamp = timestamp

        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard meanInterval.isFinite, meanInterval > 0 else { return nil }
        return 1.0 / meanInterval
    }

    public mutating func reset() {
        intervals.removeAll(keepingCapacity: true)
        previousTimestamp = nil
    }
}
