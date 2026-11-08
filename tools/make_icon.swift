// Standalone icon generator — NOT part of the app target.
// Usage (from anywhere): swift tools/make_icon.swift
// Reads idipper_logo.jpg, writes AppIcon.icns (for build.sh) and Assets.xcassets/AppIcon.appiconset (for Xcode).
import Foundation
FileManager.default.changeCurrentDirectoryPath(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path)
import AppKit
import CoreImage
let src = NSImage(contentsOfFile: "idipper_logo.jpg")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = src.width, H = src.height
// find squircle bounds: scan middle row/col for non-white
let rep = NSBitmapImageRep(cgImage: src)
func dark(_ x: Int, _ y: Int) -> Bool { let c = rep.colorAt(x: x, y: y)!; return (c.redComponent + c.greenComponent + c.blueComponent) < 2.4 }
var l = 0; while !dark(l, H/2) { l += 1 }
var r = W-1; while !dark(r, H/2) { r -= 1 }
var t = 0; while !dark(W/2, t) { t += 1 }
var b = H-1; while !dark(W/2, b) { b -= 1 }
print("bounds", l, r, t, b)
let inset = 10
let crop = src.cropping(to: CGRect(x: l+inset, y: t+inset, width: r-l-2*inset, height: b-t-2*inset))!

func squircle(_ rect: CGRect) -> CGPath {
    // superellipse n=5 approximating Apple continuous corners
    let p = CGMutablePath(); let n = 5.0, steps = 720
    let a = rect.width/2, bb = rect.height/2, cx = rect.midX, cy = rect.midY
    for i in 0...steps {
        let th = Double(i) / Double(steps) * 2 * .pi
        let c = cos(th), s = sin(th)
        let x = cx + a * CGFloat(copysign(pow(abs(c), 2/n), c))
        let y = cy + bb * CGFloat(copysign(pow(abs(s), 2/n), s))
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath(); return p
}
func render(_ S: Int, shadow: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(S) / 1024
    ctx.scaleBy(x: k, y: k)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = squircle(body)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.32).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.3, alpha: 1).cgColor); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    // zoom content ~6% so the art fills the body (artwork has generous sky margin)
    let z: CGFloat = 1.06
    let d = body.insetBy(dx: -body.width*(z-1)/2, dy: -body.height*(z-1)/2).offsetBy(dx: 0, dy: -8)
    ctx.draw(crop, in: d)
    ctx.restoreGState()
    var img = ctx.makeImage()!
    if S <= 64 {
        let ci = CIImage(cgImage: img).applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": S <= 32 ? 0.9 : 0.5])
        img = CIContext().createCGImage(ci, from: CGRect(x: 0, y: 0, width: S, height: S))!
    }
    return img
}
let fm = FileManager.default
try? fm.removeItem(atPath: "AppIcon.iconset"); try! fm.createDirectory(atPath: "AppIcon.iconset", withIntermediateDirectories: true)
func save(_ i: CGImage, _ n: String) { try! NSBitmapImageRep(cgImage: i).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: n)) }
for s in [16, 32, 128, 256, 512] {
    save(render(s, shadow: s >= 128), "AppIcon.iconset/icon_\(s)x\(s).png")
    save(render(s*2, shadow: s*2 >= 128), "AppIcon.iconset/icon_\(s)x\(s)@2x.png")
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"]; try! p.run(); p.waitUntilExit()
let set = "Assets.xcassets/AppIcon.appiconset"
for f in (try! fm.contentsOfDirectory(atPath: "AppIcon.iconset")) {
    try? fm.removeItem(atPath: "\(set)/\(f)"); try! fm.copyItem(atPath: "AppIcon.iconset/\(f)", toPath: "\(set)/\(f)")
}
try? fm.removeItem(atPath: "AppIcon.iconset")
