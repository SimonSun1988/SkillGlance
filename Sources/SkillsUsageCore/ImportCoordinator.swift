import Foundation

public actor ImportCoordinator {
  let home: URL
  let store: UsageStore
  private var busy = false
  public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, store: UsageStore) {
    self.home = home
    self.store = store
  }
  public func scan(
    rebuild: Bool = false, progress: @Sendable (String, Double) async -> Void = { _, _ in }
  ) async throws -> Snapshot {
    guard !busy else { throw StoreError(message: "正在匯入中") }
    busy = true
    defer { busy = false }
    var snapshot = try await store.load()
    let previousSources = snapshot.sources
    var checkpoints = rebuild ? [:] : try await store.checkpoints()
    var events = Dictionary(snapshot.events.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    if rebuild {
      events = [:]
      snapshot.lastScan = nil
    }
    // Issues and notices describe this scan only; lasting facts live in checkpoints.
    snapshot.issues = []
    snapshot.notices = []
    var blocked: [String: Date] = [:]
    let now = Date()
    var hardFailures = 0
    var roots = [
      ".agents/skills", ".claude/skills", ".codex/skills", ".codex/plugins", ".gemini/skills", ".gemini/config/skills", ".gemini/extensions",
      ".gemini/antigravity/skills", ".gemini/antigravity-cli/skills",
      ".gemini/antigravity-cli/plugins", ".cursor/skills", ".cursor/skills-cursor",
      ".cursor/plugins",
    ].map { home.appendingPathComponent($0) }
    for project in snapshot.projectRoots {
      for relative in [
        ".agents/skills", ".agent/skills", ".claude/skills", ".codex/skills", ".cursor/skills",
        ".gemini/skills",
      ] {
        roots.append(URL(fileURLWithPath: project).appendingPathComponent(relative))
      }
    }
    let discovered = SkillInventory.scan(roots: roots)
    var catalog = Dictionary(snapshot.skills.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    for key in catalog.keys { catalog[key]?.installed = false }
    for item in discovered {
      let id = stableID(item.path)
      if var previous = catalog[id] {
        if !snapshot.skills.contains(where: { $0.id == id && $0.installed }) || rebuild {
          previous.observedAt = now
        }
        previous.managed = item.managed
        previous.declaredName = item.declaredName
        previous.cacheOnly = item.cacheOnly
        previous.installed = true
        previous.aliases = item.aliases
        catalog[id] = previous
      } else {
        catalog[id] = Skill(item, now: now)
      }
    }
    snapshot.skills = catalog.values.sorted { $0.name < $1.name }
    snapshot.scanIncomplete = true
    if !rebuild { try await store.save(snapshot, checkpoints: checkpoints) }
    let desktopIDs = desktopSessionIDs()
    let sourceRoots: [(Platform, [URL])] = [
      (
        .codex,
        [
          home.appendingPathComponent(".codex/sessions"),
          home.appendingPathComponent(".codex/archived_sessions"),
        ]
      ), (.claudeDesktop, [home.appendingPathComponent(".claude/projects")]),
    ]
    var statuses: [SourceStatus] = []
    let allFiles = sourceRoots.map { ($0.0, $0.1.flatMap { Self.files($0, extension: "jsonl") }) }
    let total = max(allFiles.reduce(0) { $0 + $1.1.count }, 1)
    var processed = 0
    var modifiedFiles = 0
    var lastProgress = Date.distantPast
    var locations: [String: ProjectLocation] = [:]
    for (platform, files) in allFiles {
      var status = SourceStatus(
        id: platform.rawValue, platform: platform, files: files.count, bytes: 0, issues: 0,
        message: "本機可讀紀錄",
        requiredForAssessment: sourceRoots.first(where: { $0.0 == platform })!.1.contains {
          FileManager.default.fileExists(atPath: $0.path)
        } || snapshot.events.contains { $0.platform == platform })
      if files.isEmpty && status.requiredForAssessment == true {
        hardFailures += 1
        status.issues += 1
        status.message = "找不到可讀紀錄"
      } else if files.isEmpty {
        status.message = "尚未偵測到本機紀錄"
      }
      for file in files.sorted(by: { $0.path < $1.path }) {
        try Task.checkCancellation()
        if Date().timeIntervalSince(lastProgress) > 0.15 {
          await progress(
            "\(platform.label) · \(processed + 1) / \(total)", Double(processed) / Double(total))
          lastProgress = Date()
        }
        do {
          let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
          let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
          status.bytes += Int64(size)
          let identity = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
          var checkpoint = checkpoints[file.path] ?? Checkpoint()
          let previousOffset = checkpoint.offset
          var changedAnchor = false
          if let anchor = checkpoint.anchor, checkpoint.offset <= size {
            changedAnchor = try JSONLReader.anchor(file, offset: checkpoint.offset) != anchor
          }
          if checkpoint.offset > size
            || (!checkpoint.identity.isEmpty && checkpoint.identity != identity) || changedAnchor
          {
            // Event IDs are stable, so re-reading this file alone cannot double count.
            checkpoint = Checkpoint()
            Self.addNotice("紀錄輪替、截斷或改寫：\(platform.label)，已重新讀取該檔案", to: &snapshot)
          }
          // Replay old parser checkpoints without rebuilding statistics or observation periods.
          if checkpoint.state.parserRevision < ParseState.currentRevision {
            checkpoint = Checkpoint()
          }
          let linkedDesktop = desktopIDs.contains(file.deletingPathExtension().lastPathComponent)
          if platform == .claudeDesktop && linkedDesktop && !checkpoint.state.desktop
            && checkpoint.state.explicitCLI != true && checkpoint.offset > 0
          {
            checkpoint = Checkpoint()
          }
          if platform == .claudeDesktop
            && file.deletingLastPathComponent().lastPathComponent == "subagents"
          {
            let parent = file.deletingLastPathComponent().deletingLastPathComponent()
              .lastPathComponent
            if let parentState = checkpoints.values.first(where: {
              $0.state.session == parent && $0.state.desktop && checkpoint.state.explicitCLI != true
            })?.state {
              if !checkpoint.state.desktop && checkpoint.state.explicitCLI != true
                && checkpoint.offset > 0
              {
                checkpoint = Checkpoint()
              }
              checkpoint.state.desktop = true
              checkpoint.state.group = parentState.group
            }
          }
          checkpoint.identity = identity
          if platform == .claudeDesktop && checkpoint.offset == 0 {
            checkpoint.state.desktop = checkpoint.state.desktop || linkedDesktop
          }
          let baseline = checkpoint.line
          var consumed = 0
          checkpoint.offset = try JSONLReader.read(file, offset: checkpoint.offset) {
            data, localLine in
            consumed = localLine
            guard !data.isEmpty else { return }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
              checkpoint.state.malformedLines += 1
              return
            }
            for parsedEvent in LogParser.consume(
              object, platform: platform, source: file.path, line: baseline + localLine,
              state: &checkpoint.state, catalog: snapshot.skills)
            {
              var event = parsedEvent
              if locations[event.cwd] == nil {
                locations[event.cwd] = ProjectResolver.resolve(
                  event.cwd, roots: snapshot.projectRoots)
              }
              event.project = locations[event.cwd]?.repository
              event.worktree = locations[event.cwd]?.worktree
              if Self.merge(event, into: &events) {
                Self.addNotice("同一事件存在互相衝突的結果", to: &snapshot)
              }
            }
          }
          checkpoint.anchor = try JSONLReader.anchor(file, offset: checkpoint.offset)
          checkpoint.line += consumed
          checkpoints[file.path] = checkpoint
          if previousOffset != checkpoint.offset { modifiedFiles += 1 }
          if checkpoint.state.malformedLines > 0 {
            hardFailures += checkpoint.state.malformedLines
            status.issues += checkpoint.state.malformedLines
            Self.addIssue("\(platform.label) 有無法解析的完整紀錄行", to: &snapshot)
          }
        } catch is CancellationError { throw CancellationError() } catch {
          hardFailures += 1
          status.issues += 1
          Self.addIssue("\(platform.label) 部分檔案無法讀取（\(type(of:error))）", to: &snapshot)
        }
        processed += 1
        if modifiedFiles >= 8 && !rebuild {
          modifiedFiles = 0
          snapshot.events = Array(events.values)
          try await store.save(snapshot, checkpoints: checkpoints)
        }
      }
      // Tools delete old sessions; keep their events and forget only the read position.
      let current = Set(files.map(\.path))
      let platformRoots = sourceRoots.first(where: { $0.0 == platform })!.1.flatMap {
        [$0.path, Self.realPath($0)]
      }
      for path in checkpoints.keys where !files.isEmpty && !current.contains(path)
        && platformRoots.contains(where: { path.hasPrefix($0 + "/") })
      {
        checkpoints[path] = nil
      }
      if platform == .claudeDesktop {
        let desktopFiles = files.filter { checkpoints[$0.path]?.state.desktop == true }
        status.files = desktopFiles.count
        status.bytes = desktopFiles.reduce(0) { total, file in
          total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        status.requiredForAssessment =
          !desktopFiles.isEmpty || !desktopIDs.isEmpty
          || snapshot.events.contains { $0.platform == .claudeDesktop }
          || previousSources.contains {
            $0.platform == .claudeDesktop && $0.requiredForAssessment == true
          }
        if status.requiredForAssessment == false {
          status.issues = 0
          status.message = "尚未偵測到本機紀錄"
        } else if desktopFiles.isEmpty {
          status.issues += 1
          status.message = "找不到可讀紀錄"
        }
      }
      statuses.append(status)
    }
    let provenDesktopIDs = desktopIDs.union(
      checkpoints.values.filter { $0.state.desktop }.map { $0.state.session })
    let cli = try ClaudeCodeSource.scan(
      home: home, catalog: snapshot.skills, desktopIDs: provenDesktopIDs)
    for file in cli.handledFiles {
      checkpoints[file]?.state.unconfirmedSource = [:]
    }
    let additional = [
      cli,
      try GeminiSource.scan(home: home, catalog: snapshot.skills),
      try AntigravitySource.scan(home: home, catalog: snapshot.skills),
      try CursorSource.scan(home: home, catalog: snapshot.skills),
    ]
    for var scan in additional {
      if scan.status.requiredForAssessment == false,
        snapshot.events.contains(where: { $0.platform == scan.status.platform })
          || previousSources.contains(where: {
            $0.platform == scan.status.platform && $0.requiredForAssessment == true
          })
      {
        scan.issue("已匯入的來源目前無法讀取")
      }
      hardFailures += scan.status.issues
      for event in scan.events where Self.merge(event, into: &events) {
        scan.note("同一事件存在互相衝突的結果")
      }
      statuses.append(scan.status)
      if scan.status.issues > 0 { Self.addIssue("部分工具來源證據不完整，請查看資料來源", to: &snapshot) }
      blocked.merge(scan.blockedNames, uniquingKeysWith: max)
      for notice in scan.notices { Self.addNotice(notice, to: &snapshot) }
    }
    if rebuild && hardFailures > 0 { throw StoreError(message: "重建未完成：部分來源不存在、無法讀取或格式損壞。舊統計已保留。") }
    snapshot.sources = statuses
    snapshot.sourceCoverageRevision = 1
    for state in checkpoints.values.map(\.state) {
      blocked.merge(state.blockedNames, uniquingKeysWith: max)
      blocked.merge(state.unconfirmedSource, uniquingKeysWith: max)
      if state.unparsedReads > 0 {
        Self.addNotice("部分提及 SKILL.md 的紀錄無法解析，且未指出特定 Skill", to: &snapshot)
      }
    }
    snapshot.blockedNames = blocked
    let parents = Dictionary(
      checkpoints.values.filter { !$0.state.session.isEmpty }.map {
        ($0.state.session, $0.state.group)
      }, uniquingKeysWith: { a, b in a == b ? a : (a.isEmpty ? b : a) })
    let identity = SkillIdentity.Index(snapshot.skills)
    var resolved: [String: String?] = [:]
    snapshot.events = events.values.map { original in
      var event = original
      if resolved[event.target] == nil { resolved[event.target] = identity.resolve(event.target) }
      event.skillID = event.conflicted == true ? nil : resolved[event.target]!
      if locations[event.cwd] == nil {
        locations[event.cwd] = ProjectResolver.resolve(event.cwd, roots: snapshot.projectRoots)
      }
      event.project = locations[event.cwd]?.repository
      event.worktree = locations[event.cwd]?.worktree
      var seen: Set<String> = []
      while let parent = parents[event.group], !parent.isEmpty, parent != event.group,
        !seen.contains(parent)
      {
        seen.insert(event.group)
        event.group = parent
      }
      return event
    }.sorted { $0.time > $1.time }
    for i in snapshot.skills.indices
    where snapshot.lastScan == nil || snapshot.skills[i].observedAt > snapshot.lastScan! {
      snapshot.skills[i].observedAt = Date()
    }
    snapshot.lastScan = Date()
    snapshot.scanIncomplete = false
    try Task.checkCancellation()
    try await store.save(snapshot, checkpoints: checkpoints)
    await progress("更新完成", 1)
    return snapshot
  }
  public func setImportant(_ id: String, value: Bool) async throws {
    guard !busy else { throw StoreError(message: "匯入完成後可變更重要標記") }
    busy = true
    defer { busy = false }
    var snapshot = try await store.load()
    if let index = snapshot.skills.firstIndex(where: { $0.id == id }) {
      snapshot.skills[index].important = value
    }
    try await store.save(snapshot, checkpoints: store.checkpoints())
  }
  public func addProject(_ path: String) async throws {
    guard !busy else { throw StoreError(message: "匯入完成後可新增專案") }
    busy = true
    defer { busy = false }
    var snapshot = try await store.load()
    let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    if !snapshot.projectRoots.contains(path) { snapshot.projectRoots.append(path) }
    try await store.save(snapshot, checkpoints: store.checkpoints())
  }
  public func removeProject(_ path: String) async throws {
    guard !busy else { throw StoreError(message: "匯入完成後可移除掃描範圍") }
    busy = true
    defer { busy = false }
    var snapshot = try await store.load()
    snapshot.projectRoots.removeAll { $0 == path }
    for i in snapshot.skills.indices where snapshot.skills[i].path.hasPrefix(path + "/") {
      snapshot.skills[i].observedAt = Date()
    }
    try await store.save(snapshot, checkpoints: store.checkpoints())
  }
  private func desktopSessionIDs() -> Set<String> {
    let root = home.appendingPathComponent(
      "Library/Application Support/Claude/claude-code-sessions")
    return Set(
      Self.files(root, extension: "json").compactMap { url in
        guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["cliSessionId"] as? String
      })
  }
  static func files(_ root: URL, extension suffix: String) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == suffix }
  }
  // The file enumerator reports real paths, e.g. /private/var for /var.
  static func realPath(_ url: URL) -> String {
    guard let resolved = realpath(url.path, nil) else { return url.path }
    defer { free(resolved) }
    return String(cString: resolved)
  }
  static func addIssue(_ text: String, to snapshot: inout Snapshot) {
    if !snapshot.issues.contains(text) { snapshot.issues.append(text) }
  }
  static func addNotice(_ text: String, to snapshot: inout Snapshot) {
    if !(snapshot.notices ?? []).contains(text) { snapshot.notices = (snapshot.notices ?? []) + [text] }
  }
  // Returns true when the copies disagree; the event then stays unknown and unattributed.
  static func merge(_ incoming: UsageEvent, into events: inout [String: UsageEvent]) -> Bool {
    var event = incoming
    guard var old = events[event.id] else {
      events[event.id] = event
      return false
    }
    let epoch = Date(timeIntervalSince1970: 0)
    if old.time == epoch && event.time != epoch {
      old.time = event.time
      events[event.id] = old
    } else if event.time == epoch {
      event.time = old.time
    }
    if old.conflicted == true { return false }
    if old.outcome != .unknown
      && (event.outcome == .unknown
        || (old.confirmed && !event.confirmed && old.outcome == event.outcome))
    {
      return false
    }
    let conflict =
      old.outcome != .unknown && event.outcome != .unknown && old.outcome != event.outcome
    if conflict {
      event.outcome = .unknown
      event.confirmed = false
      event.conflicted = true
    }
    events[event.id] = event
    return conflict
  }
}
