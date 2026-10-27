import Foundation

public enum ScanPolicy {
  public static let interval: TimeInterval = 3600
  // Allow the next hourly scan three minutes to finish before evidence becomes stale.
  public static let maximumSnapshotAge: TimeInterval = interval + 180
}
