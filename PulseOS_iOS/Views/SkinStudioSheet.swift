import SwiftUI
import PhotosUI

struct SkinStudioSheet: View {
    @EnvironmentObject private var sync: WatchSyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLevelForUpload: BodyStateLevel = .balanced
    @State private var pickerItem: PhotosPickerItem?
    @State private var statusBanner: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("选择一套内置 5 态皮肤，或为 5 个 HRV 状态分别绑定自定义图片并同步至 Apple Watch 复杂功能。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(WatchSkinStyle.allCases) { skin in
                            let isSelected = sync.selectedSkin == skin
                            Button {
                                sync.selectSkin(skin)
                                statusBanner = "已切换为「\(skin.displayName)」并下发手表"
                            } label: {
                                VStack(spacing: 8) {
                                    SkinGraphicView(skin: skin, level: selectedLevelForUpload, size: 46)
                                    Text(skin.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(skin.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    isSelected ? Color.teal.opacity(0.22) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(isSelected ? Color.teal : Color.clear, lineWidth: 1.5)
                                )
                            }
                        }
                    }

                    Divider().overlay(.white.opacity(0.1))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("为单个状态绑定自定义图片")
                            .font(.subheadline.weight(.semibold))

                        Picker("目标状态", selection: $selectedLevelForUpload) {
                            ForEach(BodyStateLevel.allCases) { level in
                                Text(level.shortTitle).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("上传「\(selectedLevelForUpload.title)」图片", systemImage: "photo.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)

                            Button("恢复内置") {
                                SharedStore.shared.removeCustomImage(for: selectedLevelForUpload)
                                sync.selectSkin(sync.selectedSkin)
                                statusBanner = "已恢复「\(selectedLevelForUpload.title)」内置图"
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }

                    if let statusBanner {
                        Text(statusBanner)
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }
                }
                .padding(16)
            }
            .navigationTitle("手表表盘皮肤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let rawData = try? await newItem.loadTransferable(type: Data.self),
                       let resizedPNG = compressForWatchComplication(rawData) {
                        sync.pushCustomImage(resizedPNG, for: selectedLevelForUpload)
                        statusBanner = "已将自定义图片同步到手表（\(selectedLevelForUpload.title)）"
                    }
                }
            }
        }
    }

    private func compressForWatchComplication(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let targetSize = CGSize(width: 140, height: 140)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.pngData()
        #else
        return data
        #endif
    }
}
