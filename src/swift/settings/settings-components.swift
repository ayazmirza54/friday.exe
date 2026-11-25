import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Design tokens

enum UI {
	static let controlWidth: CGFloat = 280
	static let labelWidth: CGFloat = 240
	static let radius: CGFloat = 8
	static let hairline = Color.primary.opacity(0.08)
	static let surface = Color.primary.opacity(0.035)
	static let fieldFill = Color.primary.opacity(0.05)
	static let fieldStroke = Color.primary.opacity(0.10)
	static let body = Font.system(size: 13)
	static let bodyMedium = Font.system(size: 13, weight: .medium)
	static let caption = Font.system(size: 11.5)
}

// MARK: - Primitives

enum Pane: String, CaseIterable, Identifiable {
	case assistant, voice, listening, dictation, shortcuts, memory, general
	var id: String { rawValue }
	var title: String {
		switch self {
		case .voice: return "Voice"
		case .assistant: return "Assistant"
		case .listening: return "Listening"
		case .dictation: return "Dictation"
		case .shortcuts: return "Shortcuts"
		case .memory: return "Memory"
		case .general: return "General"
		}
	}
	var icon: String {
		switch self {
		case .voice: return "waveform"
		case .assistant: return "sparkle"
		case .listening: return "mic"
		case .dictation: return "text.cursor"
		case .shortcuts: return "keyboard"
		case .memory: return "tray.full"
		case .general: return "gearshape"
		}
	}
}

/// Quiet bordered button with hover and pressed feedback.
struct SubtleButtonStyle: ButtonStyle {
	var isProminent = false
	func makeBody(configuration: Configuration) -> some View {
		SubtleButton(configuration: configuration, isProminent: isProminent)
	}
	private struct SubtleButton: View {
		let configuration: ButtonStyle.Configuration
		let isProminent: Bool
		@State private var isHovering = false
		@Environment(\.isEnabled) private var isEnabled
		var body: some View {
			configuration.label
				.font(UI.bodyMedium)
				.foregroundStyle(isProminent ? Color.white : Color.primary)
				.padding(.horizontal, 12)
				.frame(height: 28)
				.background(
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.fill(
							isProminent
								? Color.accentColor.opacity(configuration.isPressed ? 0.75 : isHovering ? 0.92 : 1)
								: Color.primary.opacity(configuration.isPressed ? 0.16 : isHovering ? 0.11 : 0.07))
				)
				.overlay(
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.strokeBorder(isProminent ? Color.clear : UI.fieldStroke)
				)
				.opacity(isEnabled ? 1 : 0.45)
				.scaleEffect(configuration.isPressed ? 0.985 : 1)
				.animation(.easeOut(duration: 0.12), value: isHovering)
				.animation(.easeOut(duration: 0.08), value: configuration.isPressed)
				.onHover { isHovering = $0 }
				.contentShape(Rectangle())
		}
	}
}

/// Plain icon button with a hover circle.
struct IconButton: View {
	let symbol: String
	var help: String = ""
	var isSpinning = false
	let action: () -> Void
	@State private var isHovering = false
	var body: some View {
		Button(action: action) {
			Group {
				if isSpinning {
					ProgressView().controlSize(.small).scaleEffect(0.7)
				} else {
					Image(systemName: symbol).font(.system(size: 12, weight: .medium))
				}
			}
			.frame(width: 26, height: 26)
			.foregroundStyle(isHovering ? Color.primary : Color.secondary)
			.background(Circle().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
			.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
		.help(help)
		.disabled(isSpinning)
	}
}

/// A titled group of rows separated by hairlines.
struct SettingsGroup<Content: View>: View {
	var title: String? = nil
	var footer: String? = nil
	var trailing: AnyView? = nil
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if title != nil || trailing != nil {
				HStack {
					if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
					Spacer()
					trailing
				}
				.padding(.horizontal, 2)
			}
			VStack(spacing: 0) {
				_VariadicView.Tree(DividedLayout()) { content }
			}
			.background(UI.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(UI.hairline))
			if let footer {
				Text(footer).font(UI.caption).foregroundStyle(.secondary).padding(.horizontal, 2)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

struct DividedLayout: _VariadicView_MultiViewRoot {
	func body(children: _VariadicView.Children) -> some View {
		let last = children.last?.id
		ForEach(children) { child in
			child
			if child.id != last { Rectangle().fill(UI.hairline).frame(height: 1).padding(.leading, 14) }
		}
	}
}

/// Label column + control column.
struct SettingsRow<Content: View>: View {
	let label: String
	var icon: String? = nil
	var help: String? = nil
	@ViewBuilder var content: Content

	init(_ label: String, icon: String? = nil, help: String? = nil, @ViewBuilder content: () -> Content) {
		self.label = label
		self.icon = icon
		self.help = help
		self.content = content()
	}

	var body: some View {
		HStack(alignment: .center, spacing: 14) {
			HStack(alignment: .firstTextBaseline, spacing: 9) {
				if let icon {
					Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 16)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text(label).font(UI.body)
					if let help {
						Text(help).font(UI.caption).foregroundStyle(.secondary).fixedSize(
							horizontal: false, vertical: true)
					}
				}
			}
			.frame(width: UI.labelWidth, alignment: .leading)
			Spacer(minLength: 0)
			content
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.frame(minHeight: 44)
	}
}

struct StatusDot: View {
	let text: String
	let color: Color
	var isSpinning = false
	var body: some View {
		HStack(spacing: 6) {
			if isSpinning { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 6, height: 6) }
			Text(text).font(UI.caption).foregroundStyle(.secondary)
		}
		.transition(.opacity)
	}
}

struct ValueSlider: View {
	@Binding var value: Double
	let range: ClosedRange<Double>
	var step: Double = 0
	let format: (Double) -> String
	var body: some View {
		HStack(spacing: 10) {
			// No `step:` here: stepped sliders draw tick marks. Round in the binding instead.
			Slider(
				value: Binding(
					get: { value },
					set: { v in value = step > 0 ? (v / step).rounded() * step : v }),
				in: range
			)
			.controlSize(.small)
			Text(format(value))
				.font(.system(size: 12).monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(width: 44, alignment: .trailing)
		}
		.frame(width: UI.controlWidth)
	}
}

struct Field: View {
	let placeholder: String
	@Binding var text: String
	var isMonospaced = false
	var onSubmit: () -> Void = {}
	@FocusState private var isFocused: Bool
	var body: some View {
		TextField(placeholder, text: $text)
			.textFieldStyle(.plain)
			.font(isMonospaced ? .system(size: 12, design: .monospaced) : UI.body)
			.focused($isFocused)
			.onSubmit(onSubmit)
			.padding(.horizontal, 9)
			.frame(width: UI.controlWidth, height: 28)
			.background(UI.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.strokeBorder(
						isFocused ? Color.accentColor.opacity(0.8) : UI.fieldStroke, lineWidth: isFocused ? 1.5 : 1)
			)
			.animation(.easeOut(duration: 0.12), value: isFocused)
	}
}

/// API key field with show/hide and a live validity indicator.
struct KeyField: View {
	@Binding var value: String?
	let validation: KeyValidation
	var onRetry: () -> Void = {}
	@State private var isRevealed = false
	@FocusState private var isFocused: Bool

	var body: some View {
		VStack(alignment: .trailing, spacing: 5) {
			HStack(spacing: 6) {
				// APIKeys stores only trimmed, non-empty keys.
				let b = Binding(get: { value ?? "" }, set: { value = $0 })
				Group {
					if isRevealed { TextField("Paste API key", text: b) } else { SecureField("Paste API key", text: b) }
				}
				.textFieldStyle(.plain)
				.font(.system(size: 12, design: .monospaced))
				.focused($isFocused)
				Button {
					isRevealed.toggle()
				} label: {
					Image(systemName: isRevealed ? "eye.slash" : "eye").font(.system(size: 11)).foregroundStyle(
						.secondary)
				}
				.buttonStyle(.plain)
				.help(isRevealed ? "Hide key" : "Show key")
			}
			.padding(.horizontal, 9)
			.frame(width: UI.controlWidth, height: 28)
			.background(UI.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
			)
			.animation(.easeOut(duration: 0.12), value: isFocused)

			Group {
				switch validation {
				case .missing: StatusDot(text: "Not set", color: .secondary.opacity(0.5))
				case .checking: StatusDot(text: "Checking key…", color: .secondary, isSpinning: true)
				case .valid: StatusDot(text: "Key verified", color: .green)
				case .invalid(let reason):
					HStack(spacing: 6) {
						StatusDot(text: reason, color: .red)
						Button("Retry", action: onRetry).buttonStyle(.plain).font(UI.caption).foregroundStyle(
							Color.accentColor)
					}
				}
			}
			.animation(.easeOut(duration: 0.15), value: validation)
		}
	}

	private var borderColor: Color {
		if isFocused { return Color.accentColor.opacity(0.8) }
		if case .invalid = validation { return Color.red.opacity(0.6) }
		return UI.fieldStroke
	}
}

// MARK: - Select

struct SelectOption: Identifiable, Hashable {
	let id: String
	let title: String
	var subtitle: String = ""
	var icon: String? = nil
}

/// Shows only the current choice; opening it reveals the list (with search when useful).
/// Arrow keys move, Return picks, Esc closes.
struct Select: View {
	let options: [SelectOption]
	@Binding var selection: String
	var isSearchable = false
	var prompt = "Search"
	var width: CGFloat = UI.controlWidth
	var isShowingSubtitleInField = false

	@State private var isOpen = false
	@State private var isHovering = false
	private var current: SelectOption? { options.first { $0.id == selection } }

	var body: some View {
		Button {
			isOpen.toggle()
		} label: {
			HStack(spacing: 8) {
				if let icon = current?.icon {
					Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
				}
				Text(current?.title ?? (selection.isEmpty ? "Choose…" : selection)).font(UI.body).lineLimit(1)
				if isShowingSubtitleInField, let sub = current?.subtitle, !sub.isEmpty {
					Text(sub).font(UI.caption).foregroundStyle(.secondary).lineLimit(1)
				}
				Spacer(minLength: 4)
				Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(
					.secondary)
			}
			.padding(.horizontal, 9)
			.frame(width: width, height: 28)
			.background(
				Color.primary.opacity(isOpen ? 0.09 : isHovering ? 0.075 : 0.05),
				in: RoundedRectangle(cornerRadius: 7, style: .continuous)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.strokeBorder(isOpen ? Color.accentColor.opacity(0.7) : UI.fieldStroke, lineWidth: isOpen ? 1.5 : 1)
			)
			.contentShape(Rectangle())
			.animation(.easeOut(duration: 0.12), value: isHovering)
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
		.popover(isPresented: $isOpen, arrowEdge: .bottom) {
			SelectList(
				options: options, selection: $selection, isSearchable: isSearchable, prompt: prompt,
				width: max(width, 280)
			) { isOpen = false }
		}
	}
}

struct SelectList: View {
	let options: [SelectOption]
	@Binding var selection: String
	let isSearchable: Bool
	let prompt: String
	let width: CGFloat
	let dismiss: () -> Void

	@State private var query = ""
	@State private var highlighted = 0
	@State private var hovered: String?
	@FocusState private var isFocused: Bool

	private var filtered: [SelectOption] {
		let q = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !q.isEmpty else { return options }
		return options.filter { ($0.title + " " + $0.subtitle + " " + $0.id).lowercased().contains(q) }
	}

	var body: some View {
		VStack(spacing: 0) {
			if isSearchable {
				HStack(spacing: 7) {
					Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
					TextField(prompt, text: $query)
						.textFieldStyle(.plain)
						.font(UI.body)
						.focused($isFocused)
						.onSubmit(pickHighlighted)
						.onChange(of: query) { _ in highlighted = 0 }
				}
				.padding(.horizontal, 12)
				.frame(height: 38)
				Rectangle().fill(UI.hairline).frame(height: 1)
			}
			ScrollViewReader { proxy in
				ScrollView {
					VStack(spacing: 1) {
						if filtered.isEmpty {
							Text("No results").font(UI.body).foregroundStyle(.secondary).padding(.vertical, 18)
						}
						ForEach(Array(filtered.enumerated()), id: \.element.id) { i, o in
							optionRow(option: o, index: i).id(o.id)
						}
					}
					.padding(5)
				}
				.frame(maxHeight: 300)
				.onChange(of: highlighted) { i in
					if filtered.indices.contains(i) { proxy.scrollTo(filtered[i].id) }
				}
			}
		}
		.frame(width: width)
		.fixedSize(horizontal: false, vertical: true)
		.modifier(KeyNav(up: { move(by: -1) }, down: { move(by: 1) }, enter: pickHighlighted, escape: dismiss))
		.onAppear {
			highlighted = filtered.firstIndex { $0.id == selection } ?? 0
			isFocused = true
		}
	}

	private func optionRow(option o: SelectOption, index: Int) -> some View {
		let active = index == highlighted
		return Button {
			pick(option: o)
		} label: {
			HStack(spacing: 9) {
				if let icon = o.icon {
					Image(systemName: icon).font(.system(size: 12)).foregroundStyle(active ? .primary : .secondary)
						.frame(width: 16)
				}
				VStack(alignment: .leading, spacing: 1) {
					Text(o.title).font(UI.body)
					if !o.subtitle.isEmpty {
						Text(o.subtitle).font(UI.caption).foregroundStyle(.secondary).lineLimit(2)
					}
				}
				Spacer(minLength: 8)
				if o.id == selection {
					Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(
						Color.accentColor)
				}
			}
			.padding(.horizontal, 9)
			.padding(.vertical, 6)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(active ? Color.primary.opacity(0.09) : .clear)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { if $0 { highlighted = index } }
	}

	private func move(by d: Int) {
		guard !filtered.isEmpty else { return }
		highlighted = (highlighted + d + filtered.count) % filtered.count
	}
	private func pickHighlighted() { if filtered.indices.contains(highlighted) { pick(option: filtered[highlighted]) } }
	private func pick(option o: SelectOption) {
		selection = o.id
		dismiss()
	}
}

/// Arrow / Return / Esc handling (macOS 14+; on 13 mouse and search still work).
struct KeyNav: ViewModifier {
	let up: () -> Void, down: () -> Void, enter: () -> Void, escape: () -> Void
	func body(content: Content) -> some View {
		if #available(macOS 14.0, *) {
			content
				.onKeyPress(.upArrow) {
					up()
					return .handled
				}
				.onKeyPress(.downArrow) {
					down()
					return .handled
				}
				.onKeyPress(.return) {
					enter()
					return .handled
				}
				.onKeyPress(.escape) {
					escape()
					return .handled
				}
		} else {
			content
		}
	}
}

// MARK: - Bindings

extension Binding {
	/// A binding to a property of an observable model, for views handed the model rather than `$model`.
	init<Root: AnyObject>(root: Root, keyPath: ReferenceWritableKeyPath<Root, Value>) {
		self.init(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 })
	}
}

extension Binding where Value: RawRepresentable, Value.RawValue == String {
	/// For pickers keyed by string ids; an unknown id leaves the value unchanged.
	var rawValue: Binding<String> {
		Binding<String>(
			get: { wrappedValue.rawValue },
			set: { if let value = Value(rawValue: $0) { wrappedValue = value } })
	}
}

extension Binding where Value == String? {
	/// For pickers whose "automatic" option has the id "": "" <-> nil.
	var emptyAsNil: Binding<String> {
		Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
	}
}
