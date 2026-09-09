import Cocoa

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        let image = BullIcon.appImage(size: base * scale)
        try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
