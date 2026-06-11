// iOS App Intents (Siri Shortcuts)
//
// This extension exposes a small set of AppIntents that Siri (and the
// iOS Shortcuts app) can invoke against Nightshade:
//
//   * SequenceStatusIntent  — "What's Nightshade doing?" (read-only)
//   * SequencePauseIntent   — "Pause Nightshade sequence" (confirmation)
//   * SequenceResumeIntent  — "Resume Nightshade sequence"
//   * LastImageIntent       — "Show the last image Nightshade captured"
//
// The read-only status intent answers directly from the JSON snapshot
// the Dart side publishes to the shared App Group UserDefaults suite
// `group.com.nightshade.app` (key `voice_control.snapshot`). No round-
// trip to the running app is required, so Siri can answer the question
// even when Nightshade is suspended in the background.
//
// Control intents (`pause`, `resume`, `open last image`) need to reach
// the running Dart code. They set `openAppWhenRun = true` and post the
// wire id back through the same MethodChannel
// (`nightshade/voice_control`) the snapshot publisher uses. The Dart
// `VoiceControlLifecycleController` translates the action into a call
// on `sequenceExecutorProvider.pause` / `.resume`.
//
// Per repo policy: NO silent fallbacks. Every error path produces a
// dialog Siri can speak — e.g. "Nightshade has no current sequence to
// pause" — rather than a no-op.
//
// Apple's AppIntents framework requires iOS 16.0+. We gate the whole
// file behind that minimum.

#if canImport(AppIntents)
import AppIntents
import Foundation
import UIKit

// MARK: - Shared snapshot reader

/// Mirrors `SequenceStatusSnapshot` in
/// `apps/mobile/lib/services/voice_control_service.dart`. JSON field
/// names are the on-the-wire schema; keep them in lockstep.
@available(iOS 16.0, *)
struct NightshadeStatusSnapshot {
  let sequenceId: String
  let sequenceName: String
  let targetName: String
  let executionState: String
  let framesCompleted: Int
  let framesTotal: Int
  let elapsedSeconds: Int
  let estimatedRemainingSeconds: Int?
  let currentFilter: String
  let currentNodeName: String
  let updatedAtMillis: Int64

  /// Maximum age of the cached snapshot before we consider it stale.
  /// Two hours is a deliberately wide window — sequences run for many
  /// hours unattended; we don't want to refuse to answer the user just
  /// because the throttled publisher hasn't pushed in a while.
  static let staleThreshold: TimeInterval = 7200

  static let appGroupSuite = "group.com.nightshade.app"
  static let snapshotKey = "voice_control.snapshot"

  /// Read + decode the latest snapshot. Returns `nil` when:
  ///   * the App Group container is unreachable (entitlement missing) —
  ///     in that case we want the AppIntent to fail loudly so the
  ///     developer notices, NOT silently return "no sequence".
  ///   * no snapshot has ever been written.
  ///   * the snapshot exists but failed to decode (schema drift bug).
  ///
  /// Throws when the entitlement is missing so we can surface a clear
  /// dialog explaining what to do, instead of an unhelpful generic
  /// "couldn't read your sequence" message.
  static func load() throws -> NightshadeStatusSnapshot? {
    guard let defaults = UserDefaults(suiteName: appGroupSuite) else {
      throw NightshadeIntentError.appGroupUnavailable
    }
    guard let data = defaults.data(forKey: snapshotKey) else {
      return nil
    }
    let raw = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dict = raw as? [String: Any] else {
      throw NightshadeIntentError.snapshotCorrupted(
        "snapshot blob is not a JSON object"
      )
    }
    guard
      let sequenceId = dict["sequenceId"] as? String,
      let sequenceName = dict["sequenceName"] as? String,
      let targetName = dict["targetName"] as? String,
      let executionState = dict["executionState"] as? String,
      let framesCompleted = dict["framesCompleted"] as? Int,
      let framesTotal = dict["framesTotal"] as? Int,
      let elapsedSeconds = dict["elapsedSeconds"] as? Int,
      let currentFilter = dict["currentFilter"] as? String,
      let currentNodeName = dict["currentNodeName"] as? String,
      let updatedAtMillis = (dict["updatedAtMillis"] as? NSNumber)?.int64Value
    else {
      throw NightshadeIntentError.snapshotCorrupted(
        "snapshot is missing a required field; check schema parity with Dart side"
      )
    }
    let etaRaw = dict["estimatedRemainingSeconds"]
    let eta: Int?
    if etaRaw is NSNull {
      eta = nil
    } else if let n = etaRaw as? Int {
      eta = n
    } else if let n = etaRaw as? NSNumber {
      eta = n.intValue
    } else {
      eta = nil
    }
    return NightshadeStatusSnapshot(
      sequenceId: sequenceId,
      sequenceName: sequenceName,
      targetName: targetName,
      executionState: executionState,
      framesCompleted: framesCompleted,
      framesTotal: framesTotal,
      elapsedSeconds: elapsedSeconds,
      estimatedRemainingSeconds: eta,
      currentFilter: currentFilter,
      currentNodeName: currentNodeName,
      updatedAtMillis: updatedAtMillis
    )
  }

  /// True if `updatedAtMillis` is older than [staleThreshold] relative to
  /// now. Stale snapshots are still spoken (the user might be asking
  /// during a long unattended run), but the dialog includes a caveat.
  var isStale: Bool {
    let now = Date().timeIntervalSince1970 * 1000
    return (now - Double(updatedAtMillis)) > (Self.staleThreshold * 1000)
  }

  /// One-line spoken summary. We mirror the wording produced by the Dart
  /// side's `toSpokenSummary()` so the operator hears consistent
  /// language across iOS and Android.
  func toSpokenSummary() -> String {
    switch executionState {
    case "idle":
      return "No sequence is active."
    case "completed":
      return "Sequence finished. \(framesCompleted) of \(framesTotal) frames captured on \(targetName)."
    case "failed":
      return "Sequence failed on target \(targetName)."
    case "paused":
      return "Sequence is paused on target \(targetName). " +
        "\(framesCompleted) of \(framesTotal) frames complete."
    case "stopping":
      return "Sequence is stopping. \(framesCompleted) of \(framesTotal) frames complete on \(targetName)."
    case "recovering":
      return "Sequence is recovering on target \(targetName)."
    case "running":
      let etaPart = Self.formatEta(estimatedRemainingSeconds)
      return "Sequence is running on \(targetName). " +
        "\(framesCompleted) of \(framesTotal) frames complete.\(etaPart)"
    default:
      // Unknown wire value — surface loudly rather than silently degrading.
      return "Nightshade is in an unknown state: \(executionState)."
    }
  }

  static func formatEta(_ secs: Int?) -> String {
    guard let secs = secs, secs > 0 else { return "" }
    if secs < 60 { return " Less than a minute remaining." }
    let mins = Int((Double(secs) / 60.0).rounded())
    if mins < 60 { return " About \(mins) minutes remaining." }
    let hours = mins / 60
    let remMins = mins % 60
    let hourWord = hours == 1 ? "hour" : "hours"
    if remMins == 0 { return " About \(hours) \(hourWord) remaining." }
    return " About \(hours) \(hourWord) \(remMins) minutes remaining."
  }
}

// MARK: - Errors

@available(iOS 16.0, *)
enum NightshadeIntentError: Error, CustomLocalizedStringResourceConvertible {
  case appGroupUnavailable
  case snapshotCorrupted(String)
  case noActiveSequence
  case wrongStateForPause(String)
  case wrongStateForResume(String)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .appGroupUnavailable:
      return "Nightshade cannot access its shared data. " +
        "The App Group entitlement is missing or misconfigured."
    case .snapshotCorrupted(let reason):
      return "Nightshade's status data is corrupted: \(reason)"
    case .noActiveSequence:
      return "Nightshade has no active sequence."
    case .wrongStateForPause(let state):
      return "Cannot pause: the sequence is currently \(state)."
    case .wrongStateForResume(let state):
      return "Cannot resume: the sequence is currently \(state)."
    }
  }
}

// MARK: - Status intent (read-only)

@available(iOS 16.0, *)
struct SequenceStatusIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Nightshade Sequence"
  static var description = IntentDescription(
    "Reports the current state of the running Nightshade imaging sequence, " +
    "including target, frames completed, and estimated time remaining."
  )

  // Read-only: no need to open the app. The intent answers directly
  // from the shared App Group cache so Siri can speak the result with
  // the app suspended.
  static var openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try NightshadeStatusSnapshot.load()
    guard let snapshot = snapshot else {
      return .result(
        dialog: IntentDialog(
          "Nightshade has not reported a sequence yet. Open the app to start one."
        )
      )
    }
    var summary = snapshot.toSpokenSummary()
    if snapshot.isStale {
      summary += " Note: this status may be out of date — Nightshade hasn't reported in over two hours."
    }
    return .result(dialog: IntentDialog(stringLiteral: summary))
  }
}

// MARK: - Pause intent

@available(iOS 16.0, *)
struct SequencePauseIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause Nightshade Sequence"
  static var description = IntentDescription(
    "Pauses the currently running Nightshade imaging sequence."
  )

  // Pausing is destructive enough that the user should confirm before
  // Siri actually triggers it (especially because Siri's voice match
  // can be loose).
  static var isDiscoverable: Bool = true

  // The pause action must reach the live Dart code. We open the app so
  // the MethodChannel handler in AppDelegate is reachable; the App
  // Intents framework will hand control back to the user once `perform`
  // returns.
  static var openAppWhenRun: Bool = true

  static var parameterSummary: some ParameterSummary {
    Summary("Pause Nightshade")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try NightshadeStatusSnapshot.load()
    guard let snapshot = snapshot else {
      throw NightshadeIntentError.noActiveSequence
    }
    guard snapshot.executionState == "running" else {
      throw NightshadeIntentError.wrongStateForPause(snapshot.executionState)
    }

    // Confirm with the user before firing. Apple's
    // `requestConfirmation` shows the IntentDialog in the Siri UI and
    // awaits the user's tap.
    try await requestConfirmation(
      result: .result(
        dialog: IntentDialog(
          "Pause Nightshade on \(snapshot.targetName)?"
        )
      )
    )

    NightshadeAppIntentDispatcher.dispatch("pause_sequence")
    return .result(
      dialog: IntentDialog(
        stringLiteral: "Pausing Nightshade on \(snapshot.targetName)."
      )
    )
  }
}

// MARK: - Resume intent

@available(iOS 16.0, *)
struct SequenceResumeIntent: AppIntent {
  static var title: LocalizedStringResource = "Resume Nightshade Sequence"
  static var description = IntentDescription(
    "Resumes a paused Nightshade imaging sequence."
  )

  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try NightshadeStatusSnapshot.load()
    guard let snapshot = snapshot else {
      throw NightshadeIntentError.noActiveSequence
    }
    guard snapshot.executionState == "paused" else {
      throw NightshadeIntentError.wrongStateForResume(snapshot.executionState)
    }

    NightshadeAppIntentDispatcher.dispatch("resume_sequence")
    return .result(
      dialog: IntentDialog(
        stringLiteral: "Resuming Nightshade on \(snapshot.targetName)."
      )
    )
  }
}

// MARK: - Last-image intent (deep link)

@available(iOS 16.0, *)
struct LastImageIntent: AppIntent {
  static var title: LocalizedStringResource = "Show Last Nightshade Image"
  static var description = IntentDescription(
    "Opens Nightshade to the most recently captured frame."
  )

  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    NightshadeAppIntentDispatcher.dispatch("open_last_image")
    return .result(
      dialog: IntentDialog("Opening the last Nightshade image.")
    )
  }
}

// MARK: - Dispatcher

/// Bridges from the AppIntents extension into the host app's
/// MethodChannel handler. Because `openAppWhenRun = true` brings the
/// host app to the foreground, `UIApplication.shared.delegate` here is
/// the same `AppDelegate` that owns the `nightshade/voice_control`
/// channel. We post the action wire id through it; the Dart side
/// receives a `VoiceControlAction` and routes it into the executor.
///
/// Wire ids MUST match `VoiceControlAction.wireId` in Dart.
@available(iOS 16.0, *)
enum NightshadeAppIntentDispatcher {
  static func dispatch(_ wireId: String) {
    DispatchQueue.main.async {
      let delegate = UIApplication.shared.delegate
      if let nsdelegate = delegate as? NSObject,
         nsdelegate.responds(to: NSSelectorFromString("dispatchVoiceAction:"))
      {
        nsdelegate.perform(
          NSSelectorFromString("dispatchVoiceAction:"),
          with: wireId
        )
      } else {
        // Loud failure (repo policy). If the selector is missing the
        // AppDelegate was modified incorrectly and we'd otherwise no-op.
        NSLog(
          "[NightshadeAppIntents] AppDelegate does not respond to " +
          "dispatchVoiceAction(_:). Voice action %@ dropped.",
          wireId
        )
      }
    }
  }
}

// MARK: - Shortcuts provider

/// Surfaces the intents in the Shortcuts app and as Siri suggestions.
/// Without an `AppShortcutsProvider`, Siri will still match by phrase
/// once the user has set up a custom shortcut, but the intents won't
/// appear in the Shortcuts app's suggestion list automatically.
///
/// `\(.applicationName)` interpolation in phrases requires iOS 16.4+,
/// so we gate this provider to that minimum. On 16.0–16.3, users can
/// still add the shortcuts manually from the Shortcuts app gallery
/// (where the intent definitions surface even without the provider) —
/// they just won't be auto-suggested by Siri.
@available(iOS 16.4, *)
struct NightshadeAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SequenceStatusIntent(),
      phrases: [
        "What's \(.applicationName) doing?",
        "Check my \(.applicationName) sequence",
        "Is my \(.applicationName) sequence still running?",
        "What is \(.applicationName)'s current target?"
      ],
      shortTitle: "Check Sequence",
      systemImageName: "info.circle"
    )
    AppShortcut(
      intent: SequencePauseIntent(),
      phrases: [
        "Pause \(.applicationName)",
        "Pause my \(.applicationName) sequence",
        "Stop \(.applicationName) for now"
      ],
      shortTitle: "Pause Sequence",
      systemImageName: "pause.circle"
    )
    AppShortcut(
      intent: SequenceResumeIntent(),
      phrases: [
        "Resume \(.applicationName)",
        "Continue my \(.applicationName) sequence",
        "Restart \(.applicationName)"
      ],
      shortTitle: "Resume Sequence",
      systemImageName: "play.circle"
    )
    AppShortcut(
      intent: LastImageIntent(),
      phrases: [
        "Show the last \(.applicationName) image",
        "Open the latest frame in \(.applicationName)"
      ],
      shortTitle: "Last Image",
      systemImageName: "photo"
    )
  }
}

#endif // canImport(AppIntents)
