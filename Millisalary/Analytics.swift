import AmplitudeSwift
import AppKit
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
    @ObservationIgnored private let barrier = QueueBarrier()
    /// Events held back while a value is still being stepped (a time field's
    /// stepper sends a change per click); the last one goes out, at once
    /// when the app quits
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
        amplitude?.add(plugin: barrier)
        NotificationCenter.default.observe(NSApplication.willTerminateNotification) { [weak self] in
            self?.sendPendingNow()
        }
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

    /// The app is quitting, so the held-back events go out now. The SDK's
    /// `track` only queues an event: its own serial queue stores it on disk
    /// (what isn't uploaded by then goes at the next launch), and the
    /// process exits right after this without waiting for that queue. So
    /// this waits, up to a second, for a marker tracked after them to come
    /// through. A flush wouldn't help: it's queued the same way, and its
    /// upload couldn't finish before the exit
    private func sendPendingNow() {
        guard let amplitude, !pending.isEmpty else { return }
        let sends = pending.values
        pending.removeAll()
        for send in sends {
            send.perform()
            send.cancel()
        }
        amplitude.track(event: QueueBarrier.marker())
        _ = barrier.reached.wait(timeout: .now() + 1)
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

/// Tells when the SDK's queue has got past the events tracked so far: it
/// runs every plugin for one event, the destination that writes it to disk
/// included, before it starts on the next, so once the marker reaches this
/// plugin every earlier event is stored. The marker goes no further, and
/// its session id of -1 and its own event id keep it out of the session and
/// the event numbering
private nonisolated final class QueueBarrier: BeforePlugin {
    private static let eventType = "millisalary_queue_barrier"
    let reached = DispatchSemaphore(value: 0)

    static func marker() -> BaseEvent {
        BaseEvent(eventId: 0, sessionId: -1, eventType: eventType)
    }

    override func execute(event: BaseEvent) -> BaseEvent? {
        guard event.eventType == Self.eventType else { return event }
        reached.signal()
        return nil
    }
}
