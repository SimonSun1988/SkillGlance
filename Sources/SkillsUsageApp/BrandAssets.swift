import AppKit
import SwiftUI

@MainActor enum BrandAssets {
  // App bundles use shipped resources; SwiftPM development runs use the module resource bundle.
  private static var resources: Bundle {
    Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
  }
  private static func bitmap(_ name: String) -> NSBitmapImageRep {
    guard let url = resources.url(forResource: name, withExtension: "png"),
      let data = try? Data(contentsOf: url), let representation = NSBitmapImageRep(data: data)
    else { preconditionFailure("Missing SkillGlance brand resource: \(name)") }
    return representation
  }
  static let menuBarImage: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    for name in ["SkillGlanceTemplate", "SkillGlanceTemplate@2x"] {
      let representation = bitmap(name)
      representation.size = NSSize(width: 18, height: 18)
      image.addRepresentation(representation)
    }
    image.isTemplate = true
    image.accessibilityDescription = "SkillGlance"
    return image
  }()
  static let mark: NSImage = {
    let image = NSImage(size: NSSize(width: 512, height: 512))
    image.addRepresentation(bitmap("SkillGlanceMark"))
    image.isTemplate = true
    return image
  }()
}
struct BrandMark: View {
  var size: CGFloat = 20
  var body: some View {
    Image(nsImage: BrandAssets.mark).resizable().renderingMode(.template)
      .interpolation(.high).scaledToFit().frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
