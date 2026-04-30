//
//  DomainListView.swift
//  defaultsManager
//

import SwiftUI

struct DomainListView: View {
    @EnvironmentObject var store: DefaultsStore
    @Binding var selectedCategory: String?

    var body: some View {
        List(store.categories, id: \.self, selection: $selectedCategory) { category in
            HStack(spacing: 10) {
                Image(systemName: icon(for: category))
                    .foregroundStyle(color(for: category))
                    .imageScale(.medium)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category)
                        .font(.body)
                    Text("\(store.entries(for: category).count) settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(category)
        }
        .navigationTitle("macOS Defaults")
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Dock":               return "dock.rectangle"
        case "Screenshots":        return "camera.viewfinder"
        case "Safari":             return "safari"
        case "Finder":             return "folder"
        case "Desktop":            return "desktopcomputer"
        case "Menu Bar":           return "menubar.rectangle"
        case "Mouse":              return "computermouse"
        case "Trackpad":           return "rectangle.and.hand.point.up.left"
        case "Keyboard":           return "keyboard"
        case "Mission Control":    return "rectangle.3.group"
        case "Feedback Assistant": return "exclamationmark.bubble"
        case "Xcode":              return "hammer"
        case "Simulator":          return "iphone"
        case "TextEdit":           return "doc.text"
        case "Time Machine":       return "clock.arrow.circlepath"
        case "Activity Monitor":   return "chart.bar"
        case "Messages":           return "message"
        case "Miscellaneous":      return "ellipsis.circle"
        case "General":            return "gearshape.2"
        case "Input":              return "hand.point.up.left"
        case "Screen":             return "display"
        case "Mail":               return "envelope"
        case "iTunes":             return "music.note"
        case "Window Manager":     return "rectangle.on.rectangle.angled"
        case "App Store":          return "bag"
        default:                   return "gearshape"
        }
    }

    private func color(for category: String) -> Color {
        switch category {
        case "Dock":               return .blue
        case "Screenshots":        return .purple
        case "Safari":             return .blue
        case "Finder":             return .blue
        case "Desktop":            return .teal
        case "Menu Bar":           return .gray
        case "Mouse":              return .orange
        case "Trackpad":           return .orange
        case "Keyboard":           return .indigo
        case "Mission Control":    return .cyan
        case "Feedback Assistant": return .red
        case "Xcode":              return .blue
        case "Simulator":          return .blue
        case "TextEdit":           return .gray
        case "Time Machine":       return .green
        case "Activity Monitor":   return .green
        case "Messages":           return .green
        case "Miscellaneous":      return .secondary
        case "General":            return .blue
        case "Input":              return .orange
        case "Screen":             return .teal
        case "Mail":               return .blue
        case "iTunes":             return .pink
        case "Window Manager":     return .purple
        case "App Store":          return .blue
        default:                   return .secondary
        }
    }
}
