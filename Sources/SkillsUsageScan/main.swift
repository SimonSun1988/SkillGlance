import Foundation
import SkillsUsageCore

@main struct Scan {
  static func main() async {
    do {
      let args = CommandLine.arguments
      let directory =
        args.count > 1
        ? URL(fileURLWithPath: args[1])
        : FileManager.default.temporaryDirectory.appendingPathComponent("SkillsUsageSmoke")
      let store = try UsageStore(directory: directory)
      let importer = ImportCoordinator(store: store)
      let start = Date()
      let snapshot = try await importer.scan(rebuild: args.contains("--rebuild")) {
        text, fraction in
        if ProcessInfo.processInfo.environment["SCAN_PROGRESS"] == "1" {
          print("\(Int(fraction*100))% \(text)")
        }
      }
      let rows = UsageMetrics.rows(snapshot)
      let summary = UsageMetrics.summary(snapshot.events)
      let result: [String: Any] = [
        "skills": snapshot.skills.count,
        "installedUserSkills": snapshot.skills.filter { $0.installed && !$0.managed }.count,
        "events": snapshot.events.count, "invocations": summary.invocations,
        "confirmedReads": summary.reads,
        "unresolved": snapshot.events.filter { $0.skillID == nil }.count,
        "candidates": rows.filter(\.candidate).count, "issues": snapshot.issues,
        "notices": snapshot.notices ?? [], "blockedNames": (snapshot.blockedNames ?? [:]).count,
        "seconds": Date().timeIntervalSince(start),
        "sources": snapshot.sources.map {
          [
            "platform": $0.platform.rawValue, "files": $0.files, "bytes": $0.bytes,
            "issues": $0.issues,
          ] as [String: Any]
        },
      ]
      print(
        String(
          data: try JSONSerialization.data(
            withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    } catch {
      fputs("Scan failed: \(error)\n", stderr)
      exit(1)
    }
  }
}
