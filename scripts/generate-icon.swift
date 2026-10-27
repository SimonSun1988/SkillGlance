import AppKit

// Export the approved B artwork unchanged; only crop transparent padding and render native sizes.
guard CommandLine.arguments.count == 4 else {
  fatalError("Usage: generate-icon.swift <iconset> <resources> <approved-source.png>")
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let resources = URL(fileURLWithPath: CommandLine.arguments[2])
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
guard let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)),
  let sourceCG = source.cgImage
else {
  fatalError("Cannot read approved logo source")
}
var minX = source.pixelsWide
var minY = source.pixelsHigh
var maxX = -1
var maxY = -1
for y in 0..<source.pixelsHigh {
  for x in 0..<source.pixelsWide where (source.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
    minX = min(minX, x)
    minY = min(minY, y)
    maxX = max(maxX, x)
    maxY = max(maxY, y)
  }
}
guard maxX > minX, maxY > minY,
  let cropped = sourceCG.cropping(
    to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
else { fatalError("Logo has no visible alpha silhouette") }
let artwork = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))

func render(pixels: Int, appIcon: Bool, logicalSize: Int = 18) throws -> Data {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: pixels * 4, bitsPerPixel: 32),
    let context = NSGraphicsContext(bitmapImageRep: rep)
  else { fatalError("Cannot create bitmap context") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  let edge = CGFloat(pixels)
  let canvas = CGRect(x: 0, y: 0, width: edge, height: edge)
  NSColor.clear.setFill()
  canvas.fill(using: .copy)
  if appIcon {
    NSColor(calibratedRed: 35 / 255, green: 111 / 255, blue: 105 / 255, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: canvas.insetBy(dx: edge / 32, dy: edge / 32),
      xRadius: edge * 0.213, yRadius: edge * 0.213
    ).fill()
  }
  let inset = appIcon ? edge * 0.205 : edge / CGFloat(logicalSize)
  let available = canvas.insetBy(dx: inset, dy: inset)
  let ratio = min(available.width / artwork.size.width, available.height / artwork.size.height)
  let target = CGRect(
    x: (edge - artwork.size.width * ratio) / 2,
    y: (edge - artwork.size.height * ratio) / 2,
    width: artwork.size.width * ratio, height: artwork.size.height * ratio)
  // A separate layer tints only the silhouette, preserving the transparent spaces.
  context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
  artwork.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
  (appIcon ? NSColor.white : NSColor.black).setFill()
  canvas.fill(using: .sourceIn)
  context.cgContext.endTransparencyLayer()
  NSGraphicsContext.restoreGraphicsState()
  guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode brand PNG")
  }
  // The bitmap dimensions must remain exact on both Retina and non-Retina build hosts.
  guard let check = NSBitmapImageRep(data: png), check.pixelsWide == pixels,
    check.pixelsHigh == pixels, check.hasAlpha,
    check.colorAt(x: 0, y: 0)?.alphaComponent == 0
  else { fatalError("Brand export failed dimension/alpha validation") }
  return png
}
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    try render(pixels: size * scale, appIcon: true).write(
      to: iconset.appendingPathComponent(
        "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
  }
}
try render(pixels: 18, appIcon: false).write(
  to: resources.appendingPathComponent("SkillGlanceTemplate.png"))
try render(pixels: 36, appIcon: false).write(
  to: resources.appendingPathComponent("SkillGlanceTemplate@2x.png"))
try render(pixels: 512, appIcon: false).write(
  to: resources.appendingPathComponent("SkillGlanceMark.png"))
for points in [16, 18, 20] {
  try render(pixels: points * 2, appIcon: false, logicalSize: points).write(
    to:
      resources.appendingPathComponent("SkillGlance-\(points)pt@2x.png"))
}
print("Exported approved B logo: app iconset; 18 pt template at 1x/2x; 16/18/20 pt proofs.")
