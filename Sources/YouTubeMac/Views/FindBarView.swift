import AppKit
import SwiftUI

/// Compact top-right floating Liquid Glass in-page Find pill backed by native `WKWebView.find(_:configuration:)`.
/// Positioned strictly at `.topTrailing` so the rest of `TabWebViewHost` and the bottom 64pt player scrubber remain 100% clear.
struct FindBarView: View {
    @Bindable var controller: AppController
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppIconFont.md(weight: .medium))
                .foregroundStyle(AppleTheme.accentText)

            TextField("Find on page…", text: $controller.findQuery)
                .textFieldStyle(.plain)
                .font(AppFont.body)
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
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(matched ? AppleTheme.textSecondary : AppleTheme.accentText)
                    .fixedSize()
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 14)

            Button {
                controller.findPreviousOnPage()
            } label: {
                Image(systemName: "chevron.up")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(controller.findQuery.isEmpty ? AppleTheme.textMuted.opacity(0.45) : .primary)
                    .minHitTarget(24, shape: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.findQuery.isEmpty)
            .help("Previous Match (⇧Return)")

            Button {
                controller.findNextOnPage()
            } label: {
                Image(systemName: "chevron.down")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(controller.findQuery.isEmpty ? AppleTheme.textMuted.opacity(0.45) : .primary)
                    .minHitTarget(24, shape: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.findQuery.isEmpty)
            .help("Next Match (⌘G or Return)")

            Button {
                controller.dismissFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(AppIconFont.xs(weight: .bold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .minHitTarget(24, shape: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Find Bar (Esc)")
        }
        .padding(.horizontal, AppSpacing.lg)
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
