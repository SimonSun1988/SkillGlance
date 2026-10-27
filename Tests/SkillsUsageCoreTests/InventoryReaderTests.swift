import Foundation
import Testing

@testable import SkillsUsageCore

func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
@Test func inventoryMergesSymlinksButKeepsCopies() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let a = root.appendingPathComponent("a")
  let b = root.appendingPathComponent("b")
  for url in [a, b] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try "# Instructions".write(
      to: url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  }
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("alias"), withDestinationURL: a)
  let skills = SkillInventory.scan(roots: [root])
  #expect(skills.count == 2)
  #expect(skills.first { $0.path == a.path }?.aliases.count == 2)
}
@Test func readerDefersIncompleteTail() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let file = root.appendingPathComponent("log")
  try Data("{\"a\":1}\n{\"b\":".utf8).write(to: file)
  var lines: [Data] = []
  let offset = try JSONLReader.read(file) { data, _ in lines.append(data) }
  #expect(lines.count == 1)
  #expect(offset == 8)
  let handle = try FileHandle(forWritingTo: file)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data("2}\n".utf8))
  try handle.close()
  let next = try JSONLReader.read(file, offset: offset) { data, _ in lines.append(data) }
  #expect(lines.count == 2)
  #expect(next == 16)
}
@Test func managedAliasProtectsExternalPhysicalSkill() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let physical = root.appendingPathComponent("external/clean-code")
  let cache = root.appendingPathComponent("plugins/cache")
  for url in [physical, cache] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  try "Instructions".write(
    to: physical.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  try FileManager.default.createSymbolicLink(
    at: cache.appendingPathComponent("clean-code"), withDestinationURL: physical)
  let cached = SkillInventory.scan(roots: [cache])
  #expect(cached.first?.managed == true)
  #expect(cached.first?.cacheOnly == true)
  let mixed = SkillInventory.scan(roots: [cache, physical])
  #expect(mixed.first?.managed == true)
  #expect(mixed.first?.cacheOnly == false)
}
