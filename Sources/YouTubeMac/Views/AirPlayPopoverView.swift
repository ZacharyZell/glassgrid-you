import AppKit
import SwiftUI
import YouTubeMacCore

/// Sleek Liquid Glass AirPlay & TV Display popover (`280pt` wide) supporting:
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
        VStack(alignment: .leading, spacing: 11) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)

                Text("AirPlay & TV Displays")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if controller.isAirPlayActive {
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppleTheme.accent, in: Capsule(style: .continuous))
                }
            }

            // Row 1: AirPlay Video
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    controller.triggerAirPlayVideo()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: isVideoAirPlayActive ? "airplayvideo.circle.fill" : "airplayvideo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isVideoAirPlayActive ? AppleTheme.accent : .primary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("AirPlay Video")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(videoSubtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)

                        if isVideoAirPlayActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AppleTheme.accent)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!activeMediaStatus.hasVideo || controller.isMultiviewActive)
                .opacity((!activeMediaStatus.hasVideo || controller.isMultiviewActive) ? 0.55 : 1.0)

                if let hint = controller.airPlayVideoHint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            Divider()

            // Row 2: Live CoreAudio Output / AirPlay Audio
            HStack(spacing: 9) {
                Image(systemName: isAudioAirPlayActive ? "airplayaudio.circle.fill" : "airplayaudio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isAudioAirPlayActive ? AppleTheme.accent : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Audio Output")
                            .font(.system(size: 12, weight: .semibold))
                        if isAudioAirPlayActive {
                            Text("AirPlay")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppleTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppleTheme.accent.opacity(0.14), in: Capsule(style: .continuous))
                        }
                    }
                    Text(currentAudioOutputName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

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
            VStack(alignment: .leading, spacing: 6) {
                Text("Send Window to Display (Multiview Wall)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                if otherDisplays.isEmpty {
                    Text("Connect an Apple TV or AirPlay 2 TV in Displays to beam your full window or 4-stream Multiview wall wirelessly.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(otherDisplays) { display in
                        Button {
                            controller.moveWindowToDisplay(id: display.id)
                            onDismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: display.name.localizedCaseInsensitiveContains("tv") ? "appletv" : "display")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(AppleTheme.accent)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Move to \(display.name)")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(display.resolutionLabel)
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.anyTabInFullscreen)
                    }
                }

                Button {
                    controller.coordinator?.openDisplaysSettings()
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Connect AirPlay TV in Displays…")
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(width: 320)
        .onAppear {
            controller.coordinator?.refreshConnectedDisplays()
            controller.coordinator?.refreshAudioOutputStatus()
        }
    }
}
