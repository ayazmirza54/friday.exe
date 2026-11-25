import SwiftUI

/// Keys drawn as caps, one cap per key, so a combination reads at a glance: ⌥ ⇧ V rather than
/// a run of glyphs where the modifiers come out smaller and thinner than the letter.
struct KeyCaps: View {
	enum Style {
		/// On a window background.
		case standard
		/// On the dark voice bar.
		case onDark
	}

	let glyphs: [KeyGlyph]
	var style = Style.standard
	/// Point size of the key labels; the caps scale with it.
	var size: CGFloat = 11

	init(glyphs: [KeyGlyph], style: Style = .standard, size: CGFloat = 11) {
		self.glyphs = glyphs
		self.style = style
		self.size = size
	}

	init(shortcut: Shortcut, style: Style = .standard, size: CGFloat = 11) {
		self.init(glyphs: shortcut.glyphs, style: style, size: size)
	}

	var body: some View {
		HStack(spacing: size * 0.28) {
			ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
				KeyCapFace(glyph: glyph, style: style, size: size)
			}
		}
		.fixedSize()
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(glyphs.map(\.spoken).joined(separator: " "))
	}
}

private struct KeyCapFace: View {
	let glyph: KeyGlyph
	let style: KeyCaps.Style
	let size: CGFloat
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
		HStack(spacing: size * 0.25) {
			if let text = glyph.text { Text(text) }
			if let symbol = glyph.symbol { Image(systemName: symbol).imageScale(.medium) }
		}
		.font(.system(size: size, weight: .semibold))
		.foregroundStyle(label)
		.lineLimit(1)
		.padding(.horizontal, isWide ? size * 0.5 : 0)
		.frame(minWidth: size * 1.85, minHeight: size * 1.85)
		.background(shape.fill(face))
		// A slightly heavier bottom edge, like a real key.
		.background(shape.fill(edge).offset(y: 1))
		.overlay(shape.strokeBorder(stroke, lineWidth: 0.5))
		.padding(.bottom, 1)
	}

	/// Words ("esc", "Space", "right ⌥") get side padding; single characters stay square.
	private var isWide: Bool { (glyph.text?.count ?? 0) > 1 }

	private var label: Color {
		switch style {
		case .standard: return Color.primary.opacity(0.82)
		case .onDark: return Color.white.opacity(0.72)
		}
	}

	private var face: Color {
		switch style {
		case .standard: return colorScheme == .dark ? Color.white.opacity(0.09) : Color.white
		case .onDark: return Color.white.opacity(0.09)
		}
	}

	private var edge: Color {
		switch style {
		case .standard: return colorScheme == .dark ? Color.black.opacity(0.45) : Color.primary.opacity(0.16)
		case .onDark: return Color.black.opacity(0.45)
		}
	}

	private var stroke: Color {
		switch style {
		case .standard: return Color.primary.opacity(0.12)
		case .onDark: return Color.white.opacity(0.14)
		}
	}
}
