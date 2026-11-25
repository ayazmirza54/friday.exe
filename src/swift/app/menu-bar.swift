import AppKit
import SwiftUI

/// The menu bar icon: five rounded voice bars, drawn as a template image so it matches
/// the menu bar in light and dark mode. Bars are still when idle and animate per state.
enum BarsIcon {
	static let idle: [CGFloat] = [0.32, 0.62, 1.0, 0.62, 0.32]

	static func image(heights: [CGFloat], isDimmed: Bool = false) -> NSImage {
		let size = NSSize(width: 18, height: 16)
		let img = NSImage(size: size, flipped: false) { rect in
			let barW: CGFloat = 2.2
			let gap: CGFloat = 1.6
			let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
			var x = (rect.width - total) / 2
			NSColor.black.withAlphaComponent(isDimmed ? 0.45 : 1).setFill()
			for h in heights {
				let bh = max(barW, min(1, h) * 13)
				let r = NSRect(x: x, y: (rect.height - bh) / 2, width: barW, height: bh)
				NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
				x += barW + gap
			}
			return true
		}
		img.isTemplate = true
		img.accessibilityDescription = "Bol"
		return img
	}
}

/// Drives the status item icon from the controller state.
final class MenuBarIcon {
	private weak var button: NSStatusBarButton?
	private var timer: Timer?
	private var phase: Double = 0
	private var smoothed: [CGFloat] = BarsIcon.idle
	private let level: () -> Float

	init(button: NSStatusBarButton?, level: @escaping () -> Float) {
		self.button = button
		self.level = level
		button?.image = BarsIcon.image(heights: BarsIcon.idle, isDimmed: true)
	}

	func update(state: Controller.State) {
		timer?.invalidate()
		timer = nil
		switch state {
		case .starting:
			button?.image = BarsIcon.image(heights: BarsIcon.idle, isDimmed: true)
		case .idle:
			smoothed = BarsIcon.idle
			button?.image = BarsIcon.image(heights: BarsIcon.idle)
		case .listening:
			animate { [weak self] t in
				let l = CGFloat(min(1, (self?.level() ?? 0) * 1.6))
				return Self.listeningFrame(time: t, level: l)
			}
		case .thinking:
			animate { t in Self.thinkingFrame(time: t) }
		case .speaking:
			animate { t in Self.speakingFrame(time: t) }
		}
	}

	/// Follows the mic: louder speech, taller bars (with a little life when quiet).
	static func listeningFrame(time t: Double, level l: CGFloat) -> [CGFloat] {
		var out: [CGFloat] = []
		for (i, base) in BarsIcon.idle.enumerated() {
			let phase: Double = t * 7.0 + Double(i) * 1.7
			let wobble: CGFloat = 0.12 * CGFloat(sin(phase))
			let h: CGFloat = 0.18 + base * (0.25 + l * 0.85) + wobble * (0.3 + l)
			out.append(h)
		}
		return out
	}

	/// A slow wave travelling across the bars.
	static func thinkingFrame(time t: Double) -> [CGFloat] {
		var out: [CGFloat] = []
		for i in 0..<5 {
			let phase: Double = t * 3.2 - Double(i) * 0.9
			let v: Double = (sin(phase) + 1.0) / 2.0
			out.append(0.25 + 0.6 * CGFloat(v))
		}
		return out
	}

	/// Lively, speech-like motion.
	static func speakingFrame(time t: Double) -> [CGFloat] {
		var out: [CGFloat] = []
		for i in 0..<5 {
			let a: Double = sin(t * 8.5 + Double(i) * 1.3)
			let b: Double = cos(t * 3.1 + Double(i) * 0.7)
			out.append(0.3 + 0.7 * CGFloat(abs(a * b)))
		}
		return out
	}

	private func animate(frame: @escaping (Double) -> [CGFloat]) {
		let start = Date()
		let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
			guard let self else { return }
			let target = frame(Date().timeIntervalSince(start))
			// Ease toward the target so motion looks smooth rather than jittery.
			self.smoothed = zip(self.smoothed, target).map { $0 + ($1 - $0) * 0.45 }
			self.button?.image = BarsIcon.image(heights: self.smoothed)
		}
		RunLoop.main.add(timer, forMode: .common)  // keep animating while the menu is open
		self.timer = timer
	}
}

/// Header shown at the top of the menu: what Bol is doing right now.
struct MenuHeader: View {
	let title: String
	let detail: String
	let color: Color

	var body: some View {
		HStack(spacing: 10) {
			Circle().fill(color).frame(width: 7, height: 7)
			VStack(alignment: .leading, spacing: 1) {
				Text(title).font(.system(size: 13, weight: .semibold))
				if !detail.isEmpty {
					Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
				}
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
		.frame(width: 280, alignment: .leading)
	}
}
