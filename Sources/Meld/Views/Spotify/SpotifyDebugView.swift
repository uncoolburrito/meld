import SwiftUI

// MARK: - SpotifyBenchmarkResult

struct SpotifyBenchmarkResult: Sendable, Equatable {
    let samples: [Double]
    let minMs: Double
    let p50Ms: Double
    let p90Ms: Double
    let p99Ms: Double
    let maxMs: Double

    init(samples: [Double]) {
        let sorted = samples.sorted()
        self.samples = sorted
        self.minMs = sorted.first ?? 0.0
        self.maxMs = sorted.last ?? 0.0
        if sorted.isEmpty {
            self.p50Ms = 0.0
            self.p90Ms = 0.0
            self.p99Ms = 0.0
        } else {
            let idx50 = min(sorted.count - 1, Int(Double(sorted.count) * 0.50))
            let idx90 = min(sorted.count - 1, Int(Double(sorted.count) * 0.90))
            let idx99 = min(sorted.count - 1, Int(Double(sorted.count) * 0.99))
            self.p50Ms = sorted[idx50]
            self.p90Ms = sorted[idx90]
            self.p99Ms = sorted[idx99]
        }
    }
}

// MARK: - SpotifyDebugView

/// Dedicated debug and diagnostic view for testing Phase 2 Spotify integration.
struct SpotifyDebugView: View {
    @Bindable var spotifySource: SpotifySource

    @State private var benchmarkResult: SpotifyBenchmarkResult?
    @State private var isRunningBenchmark = false
    @State private var eventLog: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                self.statusCard
                self.nowPlayingCard
                self.controlsCard
                self.benchmarkCard
                self.eventLogCard
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 600)
        .navigationTitle("Spotify Diagnostic Panel")
    }

    // MARK: - Subviews

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Status")
                .font(.headline)

            HStack(spacing: 16) {
                self.badge(
                    title: "Installed",
                    isActive: self.spotifySource.isInstalled,
                    activeColor: .green,
                    inactiveColor: .red
                )
                self.badge(
                    title: "Running",
                    isActive: self.spotifySource.isRunning,
                    activeColor: .green,
                    inactiveColor: .orange
                )
                self.badge(
                    title: "State",
                    text: "\(self.spotifySource.transportState)",
                    color: .blue
                )
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Track & Playback")
                .font(.headline)

            if let track = self.spotifySource.currentTrack {
                HStack(alignment: .top, spacing: 16) {
                    if let artworkURL = track.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.2)
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 32))
                            .frame(width: 80, height: 80)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.title3.bold())
                        Text(track.artist)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if let album = track.album {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(track.sourceID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.quaternary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(
                        value: self.spotifySource.playbackPosition,
                        total: max(1.0, self.spotifySource.playbackDuration)
                    )
                    HStack {
                        Text(self.formatTime(self.spotifySource.playbackPosition))
                        Spacer()
                        Text(self.formatTime(self.spotifySource.playbackDuration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No track loaded or Spotify stopped.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transport Controls")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Previous") {
                    self.executeAction { try await self.spotifySource.previous() }
                }
                Button(self.spotifySource.transportState == .playing ? "Pause" : "Play") {
                    self.executeAction { try await self.spotifySource.toggle() }
                }
                Button("Next") {
                    self.executeAction { try await self.spotifySource.next() }
                }
                Button("Launch Hidden") {
                    self.executeAction { try await self.spotifySource.launchHidden() }
                }
                Button("Refresh") {
                    Task { await self.spotifySource.refreshState() }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var benchmarkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("20-Sample p99 Latency Measurement")
                    .font(.headline)
                Spacer()
                Button(self.isRunningBenchmark ? "Measuring..." : "Run Benchmark") {
                    self.runLatencyBenchmark()
                }
                .disabled(self.isRunningBenchmark || !self.spotifySource.isRunning)
            }

            if let result = self.benchmarkResult {
                HStack(spacing: 20) {
                    self.metric(label: "Min", value: String(format: "%.1f ms", result.minMs))
                    self.metric(label: "p50", value: String(format: "%.1f ms", result.p50Ms))
                    self.metric(label: "p90", value: String(format: "%.1f ms", result.p90Ms))
                    self.metric(label: "p99", value: String(format: "%.1f ms", result.p99Ms))
                    self.metric(label: "Max", value: String(format: "%.1f ms", result.maxMs))
                }
            } else {
                Text("Measures 20 consecutive AppleScript state queries to confirm roundtrip latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Diagnostics")
                .font(.headline)

            if self.eventLog.isEmpty {
                Text("No events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(self.eventLog.suffix(5).reversed(), id: \.self) { entry in
                    Text(entry)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func badge(title: String, isActive: Bool, activeColor: Color, inactiveColor: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? activeColor : inactiveColor)
                .frame(width: 8, height: 8)
            Text("\(title): \(isActive ? "Yes" : "No")")
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func badge(title: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title): \(text)")
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func executeAction(_ action: @escaping () async throws -> Void) {
        self.errorMessage = nil
        Task {
            do {
                try await action()
                self.log("Executed action successfully at \(Date())")
            } catch {
                self.errorMessage = error.localizedDescription
                self.log("Action failed: \(error.localizedDescription)")
            }
        }
    }

    private func runLatencyBenchmark() {
        self.isRunningBenchmark = true
        self.errorMessage = nil

        Task.detached(priority: .userInitiated) {
            var samples: [Double] = []
            let controller = SpotifyScriptController.shared

            for _ in 0 ..< 20 {
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = try? await controller.fetchPlaybackSnapshot()
                let t1 = CFAbsoluteTimeGetCurrent()
                samples.append((t1 - t0) * 1000.0)
            }

            let result = SpotifyBenchmarkResult(samples: samples)
            await MainActor.run {
                self.benchmarkResult = result
                self.isRunningBenchmark = false
                self.log("Benchmark: p50=\(String(format: "%.1f", result.p50Ms))ms, p99=\(String(format: "%.1f", result.p99Ms))ms")
            }
        }
    }

    private func log(_ message: String) {
        self.eventLog.append("\(Date().formatted(date: .omitted, time: .standard)): \(message)")
    }
}
