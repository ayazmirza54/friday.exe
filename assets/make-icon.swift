// Draws Bol's app icon: Bol itself, in pixel art on a dark squircle. Usage: swift assets/make-icon.swift <out.png> [--light]
// The pixel map is the same one as website/public/assets/bol.svg; keep them in sync.
import AppKit

let args = CommandLine.arguments.dropFirst()
let out = args.first { !$0.hasPrefix("--") } ?? "icon_1024.png"
let isLight = args.contains("--light")
let S: CGFloat = 1024

let bol = [
	".......VV.......",
	"........VV......",
	".....VVVVVV.....",
	"....VVVVVVVV....",
	"...VVVVVVWEVOO..",
	"...VVVVVVEEVOOO.",
	"...VVVVVVVVVOOOO",
	"...VVVVVVVPVooOO",
	"...VVVVVVVVVVo.O",
	"...VVDDDVVVVVV..",
	"...VDDDDDVVVVV..",
	"...DDDDDDVVVVV..",
	"..PDDDDDVVVVVV..",
	".PPDDDDVVVVVV...",
	".PPPDDVVVVVV....",
	"PPO....F..F.....",
	"PO....FF.FF.....",
]
let palette: [Character: UInt32] = [
	"V": 0x8C5CF5, "D": 0x6B3FD6, "O": 0xFA923D, "o": 0xD9701F, "F": 0xFA923D,
	"E": 0x161616, "W": 0xFFFFFF, "P": 0xED4A99,
]

let rep = NSBitmapImageRep(
	bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
	samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
	bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
	NSColor(
		srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255, blue: CGFloat(h & 0xff) / 255,
		alpha: a)
}

// macOS icon grid: 824pt squircle centered in 1024, with a soft drop shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
hex(isLight ? 0xFFF7EE : 0x161616).setFill()
tilePath.fill()
ctx.restoreGState()

// Background: near-black (or warm cream) with the brand's violet → pink glow behind Bol.
ctx.saveGState()
tilePath.addClip()
NSGradient(colors: isLight ? [hex(0xFFFBF6), hex(0xFDEBDD)] : [hex(0x232026), hex(0x0E0D10)])!
	.draw(in: tile, angle: -90)
let glow = NSGradient(colors: [hex(0x8C5CF5, isLight ? 0.22 : 0.42), hex(0xED4A99, isLight ? 0.08 : 0.16), hex(0xED4A99, 0)])!
glow.draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 440, options: [])
// Hairline inner border so the dark tile holds its edge on a dark Dock.
if !isLight {
	NSColor.white.withAlphaComponent(0.09).setStroke()
	let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
	edge.lineWidth = 3
	edge.stroke()
}
ctx.restoreGState()

// Bol, perched on a voice bar (its HUD), slightly right of center so the tail balances the beak.
let px: CGFloat = 32
let cols = CGFloat(bol[0].count)
let rows = CGFloat(bol.count)
let barHeight: CGFloat = 26
let originX = (S - cols * px) / 2 + 16
let top = (S + rows * px + barHeight) / 2 + 10  // y of the first row's top edge (AppKit is bottom-up)

// The perch: a rounded bar in the brand gradient, under Bol's feet.
let perch = NSRect(x: 262, y: top - rows * px - barHeight, width: 500, height: barHeight)
let perchPath = NSBezierPath(roundedRect: perch, xRadius: barHeight / 2, yRadius: barHeight / 2)
ctx.saveGState()
perchPath.addClip()
NSGradient(colors: [hex(0x8C5CF5), hex(0xED4A99), hex(0xFA923D)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
	.draw(in: perch, angle: 0)
ctx.restoreGState()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(isLight ? 0.18 : 0.5).cgColor)
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
for (y, row) in bol.enumerated() {
	for (x, ch) in row.enumerated() {
		guard let color = palette[ch] else { continue }
		hex(color).setFill()
		// Overlap by half a pixel so no seams show between cells when the icon is scaled down.
		NSRect(x: originX + CGFloat(x) * px, y: top - CGFloat(y + 1) * px, width: px + 0.5, height: px + 0.5).fill()
	}
}
ctx.endTransparencyLayer()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
