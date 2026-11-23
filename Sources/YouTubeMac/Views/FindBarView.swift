import AppKit
import SwiftUI

/// Compact top-right floating Liquid Glass in-page Find pill backed by native `WKWebView.find(_:configuration:)`.
/// Positioned strictly at `.topTrailing` so the rest of `TabWebViewHost` and the bottom 64pt player scrubber remain 100% clear.
struct FindBarView: View {
    @Bindable var controller: AppController
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppleTheme.accent)

            TextField("Find on page…", text: $controller.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 170)
                .focused($isFieldFocused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        controller.findPreviousOnPage()
                    } else {
                        controller.findNextOnPage()
                    }
                }
                .onExitCommand {
                    controller.dismissFindBar()
                }

            if !controller.findQuery.isEmpty, let matched = controller.findMatchFound {
                Text(matched ? "Found" : "Not found")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(matched ? Color.secondary : AppleTheme.accent)
                    .fixedSize()
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 14)

            Button {
                controller.findPreviousOnPage()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.findQuery.isEmpty)
            .help("Previous Match (⇧Return)")

            Button {
                controller.findNextOnPage()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.findQuery.isEmpty)
            .help("Next Match (⌘G or Return)")

            Button {
                controller.dismissFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Find Bar (Esc)")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .appleGlass(in: Capsule(style: .continuous), interactive: true)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .onAppear {
            focusFieldAndSelectAll()
        }
        .onChange(of: controller.findFocusTrigger) { _, _ in
            focusFieldAndSelectAll()
        }
        .onChange(of: controller.findQuery) { _, _ in
            controller.scheduleDebouncedFindOnPage()
        }
    }

    private func focusFieldAndSelectAll() {
        isFieldFocused = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            if isFieldFocused {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }
}
