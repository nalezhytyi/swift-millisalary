import AmplitudeSwift
import Foundation
import MillisalaryCore
import Observation

/// Amplitude (amplitudeClient.ts in the Electron app), through the official
/// Swift SDK, into the Electron app's project with its event names. There
/// is no Session Replay: Amplitude's only runs on iOS and iPadOS, so
/// nothing on screen is recorded. Autocapture is sessions only: on macOS
/// the SDK has no app lifecycle events (installed, opened…), those are
/// iOS-only. The SDK's own diagnostics and remote configuration are off,
/// so the events are all it sends. Release builds send to Amplitude; Debug
/// builds send nothing unless `-debugAnalyticsURL <url>` points them at a
/// test server
@Observable
final class Analytics {
    @ObservationIgnored private let amplitude: Amplitude?
    /// Events held back while a value is still being stepped (a time field's
    /// stepper sends a change per click); the last one goes out
    @ObservationIgnored private var pending: [String: DispatchWorkItem] = [:]

    /// The Electron app's key: a client key, public by design
    private static let apiKey = "919afd003429ad6d69798aacb0c0c0a7"
    private static let settledEvents: Set = [
        "workday_start_time_changed", "workday_end_time_changed", "working_hours_per_day_changed",
    ]
    private static let settleDelay: TimeInterval = 1.5

    init() {
        #if DEBUG
        guard let testServer = UserDefaults.standard.string(forKey: "debugAnalyticsURL") else {
            amplitude = nil
            return
        }
        let serverUrl: String? = testServer
        let flushIntervalMillis = 2000
        #else
        let serverUrl: String? = nil
        let flushIntervalMillis = Configuration.Defaults.flushIntervalMillis
        #endif

        amplitude = Amplitude(configuration: Configuration(
            apiKey: Self.apiKey,
            flushIntervalMillis: flushIntervalMillis,
            serverUrl: serverUrl,
            autocapture: .sessions,
            enableAutoCaptureRemoteConfig: false,
            enableDiagnostics: false
        ))
    }

    func track(_ event: MillisalaryCore.AnalyticsEvent) {
        guard let amplitude else { return }
        if Self.settledEvents.contains(event.name) {
            pending[event.name]?.cancel()
            let send = DispatchWorkItem { [weak self] in
                self?.pending[event.name] = nil
                self?.send(event, with: amplitude)
            }
            pending[event.name] = send
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: send)
        } else {
            send(event, with: amplitude)
        }
    }

    func track(_ name: String, _ properties: [String: MillisalaryCore.AnalyticsEvent.Value] = [:]) {
        track(MillisalaryCore.AnalyticsEvent(name, properties))
    }

    /// The Settings pane's edits, each field's event
    func settingsChanged(from before: MillisalaryCore.Settings, to after: MillisalaryCore.Settings) {
        MillisalaryCore.AnalyticsEvent.settingsChanges(from: before, to: after).forEach(track)
    }

    private func send(_ event: MillisalaryCore.AnalyticsEvent, with amplitude: Amplitude) {
        let properties = event.properties.mapValues { value -> Any in
            switch value {
            case .string(let string): string
            case .number(let number): number
            case .bool(let bool): bool
            }
        }
        amplitude.track(eventType: event.name, eventProperties: properties.isEmpty ? nil : properties)
    }
}
