import ActivityKit
import Flutter
import UIKit

// MARK: - Live Activity host bridge
//
// Wave 5E — Dart calls into ActivityKit through the `nightshade/live_activity`
// MethodChannel. ActivityKit landed in iOS 16.1, but
// `NightshadeLiveActivityAttributes` (and therefore every ActivityContent we
// build here) is gated to iOS 16.2 because the `ActivityContent` API itself
// is 16.2+. On devices that fall outside that gate we fail loudly via a
// FlutterError — silent fallbacks would let an operator believe Live
// Activities are running when they are not (per repo policy: errors are a
// feature).
//
// Channel name (`nightshade/live_activity`) and method/argument names MUST
// match `apps/mobile/lib/services/live_activity_service.dart`. Argument names
// here also mirror the field names on
// `NightshadeLiveActivityAttributes.ContentState` 1:1 so the host and the
// widget speak the same vocabulary end to end.

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Tracks running activities so update/end calls can find the right
  /// `Activity` instance. ActivityKit only exposes its own `Activity.activities`
  /// async lookup, but maintaining our own map lets us answer synchronously
  /// from the channel handler. Cleared in `liveActivityEnd(_:)`.
  private var liveActivities: [String: Any] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "nightshade/live_activity",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(
              code: "host_deallocated",
              message: "AppDelegate was released before \(call.method) completed",
              details: nil
            )
          )
          return
        }
        self.handleLiveActivityCall(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Dispatch

  private func handleLiveActivityCall(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
    if #available(iOS 16.2, *) {
      switch call.method {
      case "start":
        liveActivityStart(call.arguments, result: result)
      case "update":
        liveActivityUpdate(call.arguments, result: result)
      case "end":
        liveActivityEnd(call.arguments, result: result)
      case "isSupported":
        // Authoritative answer for Dart: the OS may still refuse if the
        // user has disabled Live Activities globally in Settings or if the
        // app is missing the widget extension. We check
        // `areActivitiesEnabled` rather than just returning true.
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      default:
        result(FlutterMethodNotImplemented)
      }
    } else {
      // Loud failure. iOS 16.1 and below cannot build an `ActivityContent`
      // for our `NightshadeLiveActivityAttributes` (the type itself is
      // 16.2-gated).
      result(
        FlutterError(
          code: "unsupported_ios_version",
          message: "Live Activities require iOS 16.2 or later",
          details: nil
        )
      )
    }
  }

  // MARK: - start

  @available(iOS 16.2, *)
  private func liveActivityStart(_ rawArgs: Any?, result: @escaping FlutterResult) {
    guard let args = rawArgs as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "start() expected a Map argument, got \(type(of: rawArgs))",
          details: nil
        )
      )
      return
    }

    guard let sequenceId = args["sequenceId"] as? String, !sequenceId.isEmpty else {
      result(
        FlutterError(
          code: "missing_sequence_id",
          message: "start() requires a non-empty sequenceId",
          details: nil
        )
      )
      return
    }
    guard let targetName = args["targetName"] as? String else {
      result(
        FlutterError(
          code: "missing_target_name",
          message: "start() requires a targetName",
          details: nil
        )
      )
      return
    }

    let attributes = NightshadeLiveActivityAttributes(
      sequenceId: sequenceId,
      targetName: targetName
    )
    let state = decodeContentState(args)

    // ActivityAuthorizationInfo guards against silently no-op'ing when the
    // user has disabled Live Activities for the app. Surface as a discrete
    // error code so Dart can disambiguate user-denial from API failure.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(
        FlutterError(
          code: "activities_disabled",
          message:
            "Live Activities are disabled in iOS Settings for Nightshade. Enable them in Settings > Nightshade > Live Activities.",
          details: nil
        )
      )
      return
    }

    do {
      let content = ActivityContent(state: state, staleDate: nil)
      let activity = try Activity<NightshadeLiveActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
      liveActivities[activity.id] = activity
      result(activity.id)
    } catch {
      // ActivityKit throws on quota exhaustion, missing entitlements,
      // missing widget extension, etc. Forward the underlying message so
      // the operator-visible log is useful.
      result(
        FlutterError(
          code: "activity_request_failed",
          message: "Activity.request failed: \(error.localizedDescription)",
          details: String(describing: error)
        )
      )
    }
  }

  // MARK: - update

  @available(iOS 16.2, *)
  private func liveActivityUpdate(_ rawArgs: Any?, result: @escaping FlutterResult) {
    guard let args = rawArgs as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "update() expected a Map argument, got \(type(of: rawArgs))",
          details: nil
        )
      )
      return
    }
    guard let activityId = args["activityId"] as? String, !activityId.isEmpty else {
      result(
        FlutterError(
          code: "missing_activity_id",
          message: "update() requires a non-empty activityId",
          details: nil
        )
      )
      return
    }
    guard
      let activity = liveActivities[activityId]
        as? Activity<NightshadeLiveActivityAttributes>
    else {
      result(
        FlutterError(
          code: "unknown_activity",
          message:
            "No live Activity with id \(activityId) is tracked by the host. It may have already ended.",
          details: nil
        )
      )
      return
    }

    let state = decodeContentState(args)
    let content = ActivityContent(state: state, staleDate: nil)

    Task {
      await activity.update(content)
      result(nil)
    }
  }

  // MARK: - end

  @available(iOS 16.2, *)
  private func liveActivityEnd(_ rawArgs: Any?, result: @escaping FlutterResult) {
    guard let args = rawArgs as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "end() expected a Map argument, got \(type(of: rawArgs))",
          details: nil
        )
      )
      return
    }
    guard let activityId = args["activityId"] as? String, !activityId.isEmpty else {
      result(
        FlutterError(
          code: "missing_activity_id",
          message: "end() requires a non-empty activityId",
          details: nil
        )
      )
      return
    }
    guard
      let activity = liveActivities[activityId]
        as? Activity<NightshadeLiveActivityAttributes>
    else {
      // Already ended (or never tracked). Treat as a no-op success — the
      // caller's intent ("this activity should not be running") is met.
      // We log to console so a desync between Dart and host stays
      // visible during development.
      NSLog(
        "[LiveActivity] end() called for unknown activity %@ — already ended?",
        activityId
      )
      result(nil)
      return
    }

    // Optional dismissDate. Default to immediate dismissal so the lock-screen
    // banner clears the moment the sequence finishes — leaving a "completed"
    // banner around for 4 hours (Apple's default) is confusing.
    let dismissDate: Date
    if let dismissMillis = args["dismissDate"] as? NSNumber {
      dismissDate = Date(timeIntervalSince1970: dismissMillis.doubleValue / 1000.0)
    } else {
      dismissDate = Date()
    }

    // If the caller supplied a final state, push it before ending so the
    // lock-screen banner shows the terminal frame count.
    let finalState = decodeContentState(args, fallbackToCurrent: activity.content.state)
    let content = ActivityContent(state: finalState, staleDate: nil)

    Task {
      await activity.end(content, dismissalPolicy: .after(dismissDate))
      liveActivities.removeValue(forKey: activityId)
      result(nil)
    }
  }

  // MARK: - Argument decoding

  /// Decode a `ContentState` payload from the Dart-supplied argument map.
  ///
  /// When `fallbackToCurrent` is provided, missing fields keep the value
  /// from that prior state — useful for `update` calls that only carry
  /// the changed fields. For `start` (no prior state) the defaults below
  /// are used.
  @available(iOS 16.2, *)
  private func decodeContentState(
    _ args: [String: Any],
    fallbackToCurrent fallback: NightshadeLiveActivityAttributes.ContentState? = nil
  ) -> NightshadeLiveActivityAttributes.ContentState {
    let framesCompleted =
      (args["framesCompleted"] as? NSNumber)?.intValue ?? fallback?.framesCompleted ?? 0
    let framesTotal =
      (args["framesTotal"] as? NSNumber)?.intValue ?? fallback?.framesTotal ?? 0
    let elapsedSeconds =
      (args["elapsedSeconds"] as? NSNumber)?.intValue ?? fallback?.elapsedSeconds ?? 0

    // Optional Int — accept JSON's `null` literal (NSNull) as well as a
    // missing key. Otherwise `nil` could never round-trip from Dart.
    let estimatedRemainingSeconds: Int?
    if args["estimatedRemainingSeconds"] is NSNull {
      estimatedRemainingSeconds = nil
    } else if let n = args["estimatedRemainingSeconds"] as? NSNumber {
      estimatedRemainingSeconds = n.intValue
    } else {
      estimatedRemainingSeconds = fallback?.estimatedRemainingSeconds
    }

    let currentFilter =
      (args["currentFilter"] as? String) ?? fallback?.currentFilter ?? ""

    let currentHfr: Double?
    if args["currentHfr"] is NSNull {
      currentHfr = nil
    } else if let n = args["currentHfr"] as? NSNumber {
      currentHfr = n.doubleValue
    } else {
      currentHfr = fallback?.currentHfr
    }

    let currentNodeName =
      (args["currentNodeName"] as? String) ?? fallback?.currentNodeName ?? ""
    let jobState =
      (args["jobState"] as? String) ?? fallback?.jobState ?? "idle"

    return NightshadeLiveActivityAttributes.ContentState(
      framesCompleted: framesCompleted,
      framesTotal: framesTotal,
      elapsedSeconds: elapsedSeconds,
      estimatedRemainingSeconds: estimatedRemainingSeconds,
      currentFilter: currentFilter,
      currentHfr: currentHfr,
      currentNodeName: currentNodeName,
      jobState: jobState
    )
  }

}
