import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Memory

struct MemoryPane: View {
	@ObservedObject var model: SettingsModel
	@State private var query = ""
	/// The memory whose Forget button is armed (second click deletes).
	@State private var armedID: String?

	private var filtered: [MemoryItem] {
		let q = query.lowercased()
		return q.isEmpty
			? model.memories : model.memories.filter { ($0.name + " " + $0.description).lowercased().contains(q) }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("One global memory. Each session loads only the index; individual memories are read when relevant.")
				.font(UI.caption).foregroundStyle(.secondary)
			HStack(spacing: 8) {
				HStack(spacing: 7) {
					Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
					TextField("Search memories", text: $query).textFieldStyle(.plain).font(UI.body)
				}
				.padding(.horizontal, 9)
				.frame(height: 28)
				.background(UI.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
				.overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.fieldStroke))
				Button("Open Folder") { NSWorkspace.shared.open(Constants.memoryDirectory) }.buttonStyle(
					SubtleButtonStyle())
				IconButton(symbol: "arrow.clockwise", help: "Refresh") { withAnimation { model.loadMemories() } }
			}
			SettingsGroup(title: "\(model.memories.count) \(model.memories.count == 1 ? "memory" : "memories")") {
				if filtered.isEmpty {
					HStack {
						Spacer()
						VStack(spacing: 6) {
							Image(systemName: model.memories.isEmpty ? "tray" : "magnifyingglass")
								.font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
							Text(model.memories.isEmpty ? "Nothing remembered yet" : "No matches").font(UI.body)
								.foregroundStyle(.secondary)
							if model.memories.isEmpty {
								Text("Try “Bol, remember that I prefer Chrome.”").font(UI.caption).foregroundStyle(
									.tertiary)
							}
						}
						.padding(.vertical, 28)
						Spacer()
					}
				}
				ForEach(filtered) { m in memoryRow(item: m) }
			}
		}
		.onAppear { model.loadMemories() }
	}

	private func memoryRow(item m: MemoryItem) -> some View {
		HStack(spacing: 10) {
			Image(systemName: icon(type: m.type)).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 16)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(m.name).font(UI.bodyMedium)
					if !m.type.isEmpty {
						Text(m.type).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
							.padding(.horizontal, 5).padding(.vertical, 1)
							.background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
					}
				}
				if !m.description.isEmpty { Text(m.description).font(UI.caption).foregroundStyle(.secondary) }
			}
			Spacer()
			IconButton(symbol: "arrow.up.forward.square", help: "Open file") { NSWorkspace.shared.open(m.url) }
			if armedID == m.id {
				Button("Forget") {
					model.deleteMemory(item: m)
					armedID = nil
				}
				.buttonStyle(SubtleButtonStyle())
				.foregroundStyle(.red)
				.transition(.opacity)
			} else {
				IconButton(symbol: "trash", help: "Forget (moves to Trash)") {
					withAnimation(.easeOut(duration: 0.12)) { armedID = m.id }
					DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
						if armedID == m.id { withAnimation { armedID = nil } }
					}
				}
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
	}

	private func icon(type: String) -> String {
		switch type {
		case "user": return "person"
		case "feedback": return "text.bubble"
		case "project": return "folder"
		case "reference": return "link"
		default: return "doc.text"  // memory types are free text
		}
	}
}
