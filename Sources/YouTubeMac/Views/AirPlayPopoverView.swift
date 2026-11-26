import AppKit
import SwiftUI
import YouTubeMacCore

/// Sleek Liquid Glass AirPlay & TV Display popover (`320pt` wide) supporting:
/// 1. Element-level AirPlay Video (`webkitShowPlaybackTargetPicker`) with honest YouTube MSE guidance,
/// 2. Live CoreAudio Output / AirPlay Audio status + 1-click macOS Sound Output picker,
/// 3. 1-click "Send Window to Display (Multiview Wall)" across connected external & AirPlay TV displays.
struct AirPlayPopoverView: View {
    @Bindable var controller: AppController
    let onDismiss: () -> Void

    private var activeMediaStatus: MediaStatus {
        controller.nowPlayingStatus
    }

    private var isVideoAirPlayActive: Bool {
        activeMediaStatus.isAirPlayActive
    }

    private var isAudioAirPlayActive: Bool {
        controller.coordinator?.isAirPlayAudioActive ?? false
    }

    private var currentAudioOutputName: String {
        controller.coordinator?.currentAudioOutputName ?? "System Output"
    }

    private var otherDisplays: [ConnectedDisplayDescriptor] {
        let currentScreenID = controller.currentDisplayID
        let all = controller.coordinator?.connectedDisplays ?? []
        return all.filter { $0.id != currentScreenID }
    }

    private var videoSubtitle: String {
        if isVideoAirPlayActive {
            return "Streaming wirelessly via AirPlay"
        }
        if controller.isMultiviewActive {
            return "Single-stream only — use TV Display below for Multiview"
        }
        if !activeMediaStatus.hasVideo {
            return "Start a video to cast via AirPlay"
        }
        return "Cast video to Apple TV or AirPlay 2 TV"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "airplayvideo")
                    .font(AppIconFont.toolbar(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                    .frame(width: 20, alignment: .center)

                Text("AirPlay & TV Displays")
                    .font(AppFont.body(weight: .semibold))

                Spacer()

                if controller.isAirPlayActive {
                    Text("Active")
                        .font(AppFont.micro(weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                }
            }

            // Row 1: AirPlay Video
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Button {
                    controller.triggerAirPlayVideo()
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: isVideoAirPlayActive ? "airplayvideo.circle.fill" : "airplayvideo")
                            .font(AppIconFont.lg(weight: .semibold))
                            .foregroundStyle(isVideoAirPlayActive ? AppleTheme.accentText : .primary)
                            .frame(width: 20, alignment: .center)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("AirPlay Video")
                                .font(AppFont.callout(weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(videoSubtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(AppleTheme.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: AppSpacing.xs)

                        if isVideoAirPlayActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(AppIconFont.toolbar())
                                .foregroundStyle(AppleTheme.accentText)
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!activeMediaStatus.hasVideo || controller.isMultiviewActive)
                .opacity((!activeMediaStatus.hasVideo || controller.isMultiviewActive) ? 0.55 : 1.0)

                if let hint = controller.airPlayVideoHint {
                    Text(hint)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.xs)
                }
            }

            Divider()

            // Row 2: Live CoreAudio Output / AirPlay Audio
            HStack(spacing: AppSpacing.md) {
                Image(systemName: isAudioAirPlayActive ? "airplayaudio.circle.fill" : "airplayaudio")
                    .font(AppIconFont.lg(weight: .semibold))
                    .foregroundStyle(isAudioAirPlayActive ? AppleTheme.accentText : AppleTheme.textSecondary)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text("Audio Output")
                            .font(AppFont.callout(weight: .semibold))
                        if isAudioAirPlayActive {
                            Text("AirPlay")
                                .font(AppFont.micro(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xxs)
                                .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))
                        }
                    }
                    Text(currentAudioOutputName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)

                Spacer(minLength: AppSpacing.sm)

                Button("Choose Output…") {
                    controller.coordinator?.openSoundOutputSettings()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }

            Divider()

            // Section 3: TV & AirPlay Displays (Multiview Wall)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Send Window to Display (Multiview Wall)")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)

                if otherDisplays.isEmpty {
                    Text("Connect an Apple TV or AirPlay 2 TV in Displays to beam your full window or 4-stream Multiview wall wirelessly.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(otherDisplays) { display in
                        Button {
                            controller.moveWindowToDisplay(id: display.id)
                            onDismiss()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: display.name.localizedCaseInsensitiveContains("tv") ? "appletv" : "display")
                                    .font(AppIconFont.md(weight: .semibold))
                                    .foregroundStyle(AppleTheme.accentText)
                                    .frame(width: 20, alignment: .center)

                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text("Move to \(display.name)")
                                        .font(AppFont.callout(weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(display.resolutionLabel)
                                        .font(AppFont.micro(tabular: true))
                                        .foregroundStyle(AppleTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(AppIconFont.sm())
                                    .foregroundStyle(AppleTheme.textSecondary)
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.anyTabInFullscreen)
                    }
                }

                Button {
                    controller.coordinator?.openDisplaysSettings()
                    onDismiss()
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(AppIconFont.md(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .frame(width: 20, alignment: .center)
                        Text("Connect AirPlay TV in Displays…")
                            .font(AppFont.callout(weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 320)
        .onAppear {
            controller.coordinator?.refreshConnectedDisplays()
            controller.coordinator?.refreshAudioOutputStatus()
        }
    }
}
