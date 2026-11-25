import AppKit
import SwiftUI

/// A reply's markdown, block by block: paragraphs, headings, lists, quotes, code and tables.
struct MarkdownView: View {
	let blocks: [MarkdownBlock]
	let fontSize: CGFloat

	init(text: String, fontSize: CGFloat = 13.5) {
		blocks = MarkdownBlock.parse(text: text)
		self.fontSize = fontSize
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
				view(block: block)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder private func view(block: MarkdownBlock) -> some View {
		switch block {
		case .paragraph(let text):
			Text(Format.markdown(text)).font(.system(size: fontSize)).lineSpacing(3)
				.fixedSize(horizontal: false, vertical: true)
		case .heading(let level, let text):
			Text(Format.markdown(text))
				.font(
					.system(size: level == 1 ? fontSize + 4 : level == 2 ? fontSize + 2 : fontSize, weight: .semibold)
				)
				.padding(.top, 4)
		case .list(let items):
			VStack(alignment: .leading, spacing: 5) {
				ForEach(Array(items.enumerated()), id: \.offset) { _, item in
					HStack(alignment: .firstTextBaseline, spacing: 7) {
						Text(item.marker).font(.system(size: fontSize).monospacedDigit()).foregroundStyle(.secondary)
							.frame(minWidth: 12, alignment: .trailing)
						Text(Format.markdown(item.text)).font(.system(size: fontSize)).lineSpacing(3)
							.fixedSize(horizontal: false, vertical: true)
					}
					.padding(.leading, CGFloat(item.depth) * 18)
				}
			}
		case .quote(let text):
			HStack(alignment: .top, spacing: 10) {
				Capsule().fill(Color.primary.opacity(0.18)).frame(width: 2.5)
				Text(Format.markdown(text)).font(.system(size: fontSize)).foregroundStyle(.secondary).lineSpacing(3)
					.fixedSize(horizontal: false, vertical: true)
			}
		case .code(let language, let text):
			CodeFence(language: language, text: text)
		case .table(let text):
			ScrollView(.horizontal, showsIndicators: false) {
				Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
					.fixedSize()
					.padding(10)
			}
			.background(UI.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.hairline))
		}
	}
}

/// A fenced code block with its language and a copy button.
private struct CodeFence: View {
	let language: String
	let text: String

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text(language.isEmpty ? "code" : language).font(.system(size: 10.5, weight: .medium))
					.foregroundStyle(.tertiary)
				Spacer()
				CopyButton(text: text)
			}
			.padding(.leading, 11).padding(.trailing, 6)
			.frame(height: 26)
			Rectangle().fill(UI.hairline).frame(height: 1)
			ScrollView(.horizontal, showsIndicators: false) {
				Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.primary.opacity(0.85))
					.lineSpacing(2)
					.fixedSize()
					.padding(11)
			}
		}
		.background(UI.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(UI.hairline))
	}
}

/// Copies `text`, and shows a check for a moment.
struct CopyButton: View {
	let text: String
	var help = "Copy"
	@State private var hasCopied = false
	@State private var isHovering = false

	var body: some View {
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(text, forType: .string)
			hasCopied = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { hasCopied = false }
		} label: {
			Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
				.font(.system(size: 10.5, weight: .medium))
				.foregroundStyle(isHovering || hasCopied ? .primary : .secondary)
				.frame(width: 22, height: 20)
				.background(
					RoundedRectangle(cornerRadius: 5, style: .continuous)
						.fill(Color.primary.opacity(isHovering ? 0.08 : 0))
				)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
		.help(hasCopied ? "Copied" : help)
	}
}
