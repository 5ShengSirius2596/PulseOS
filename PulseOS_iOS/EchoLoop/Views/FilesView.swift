import SwiftUI
import UniformTypeIdentifiers

/// 文件管理与导入页面：支持从 iOS「文件」导入 MP3/M4A/WAV 音频及 SRT/LRC 字幕、合集分组、搜索与删除
struct FilesView: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var library: LibraryManager
    @Binding var selectedTab: Int

    @State private var searchText = ""
    @State private var selectedCollection = "全部"
    @State private var showAudioImporter = false
    @State private var showSubtitleImporter = false
    @State private var subtitleTargetTrackID: UUID?
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var importError: String?
    @State private var transcribeTargetTrack: AudioTrack?

    private var filteredTracks: [AudioTrack] {
        library.tracks.filter { track in
            let matchCollection = (selectedCollection == "全部" || track.collectionName == selectedCollection)
            let matchSearch = searchText.isEmpty || track.title.localizedCaseInsensitiveContains(searchText)
            return matchCollection && matchSearch
        }
    }

    private var subtitleContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let srt = UTType(filenameExtension: "srt") { types.append(srt) }
        if let lrc = UTType(filenameExtension: "lrc") { types.append(lrc) }
        return types
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 合集筛选横向胶囊
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        collectionChip("全部")
                        ForEach(library.collections, id: \.self) { col in
                            collectionChip(col)
                        }
                        Button {
                            newCollectionName = ""
                            showNewCollectionAlert = true
                        } label: {
                            Label("新建合集", systemImage: "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                if filteredTracks.isEmpty {
                    ContentUnavailableView(
                        "暂无音频文件",
                        systemImage: "music.note.list",
                        description: Text("点击右上角「+」从 iPhone 文件、iCloud Drive 或隔空投送导入 MP3 / M4A / WAV 英语听力材料。")
                    )
                } else {
                    List {
                        ForEach(filteredTracks) { track in
                            trackRow(track)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let track = filteredTracks[index]
                                if engine.currentTrack?.id == track.id {
                                    engine.stop()
                                    engine.currentTrack = nil
                                }
                                library.deleteTrack(track)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("音频文件")
            .searchable(text: $searchText, prompt: "搜索音频文件名")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAudioImporter = true
                    } label: {
                        Label("导入音频", systemImage: "plus.circle.fill")
                    }
                }
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let targetCollection = (selectedCollection == "全部") ? "默认合集" : selectedCollection
                    var lastImported: AudioTrack?
                    for url in urls {
                        do {
                            lastImported = try library.importAudioFile(from: url, collection: targetCollection)
                        } catch {
                            importError = "导入失败：\(error.localizedDescription)"
                        }
                    }
                    if let track = lastImported {
                        engine.loadTrack(track, autoPlay: false)
                        selectedTab = 0
                    }
                case .failure(let err):
                    importError = err.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showSubtitleImporter,
                allowedContentTypes: subtitleContentTypes,
                allowsMultipleSelection: false
            ) { result in
                guard let targetID = subtitleTargetTrackID else { return }
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        do {
                            if let updated = try library.attachSubtitleFile(from: url, to: targetID) {
                                if engine.currentTrack?.id == updated.id {
                                    engine.loadTrack(updated, autoPlay: false)
                                    engine.repeatMode = .subtitle
                                }
                            }
                        } catch {
                            importError = "字幕导入失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let err):
                    importError = err.localizedDescription
                }
            }
            .sheet(item: $transcribeTargetTrack) { track in
                GenerateSubtitleSheet(engine: engine, library: library, targetTrack: track)
            }
            .alert("新建学习合集", isPresented: $showNewCollectionAlert) {
                TextField("例如：新概念二、雅思精听", text: $newCollectionName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    library.addCollection(newCollectionName)
                }
            }
            .alert("导入提示", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func collectionChip(_ name: String) -> some View {
        let active = (selectedCollection == name)
        return Button {
            selectedCollection = name
        } label: {
            Text(name)
                .font(.caption.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.blue : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: AudioTrack) -> some View {
        let isCurrent = engine.currentTrack?.id == track.id
        return HStack(spacing: 12) {
            Image(systemName: isCurrent ? "waveform.circle.fill" : "music.note")
                .font(.title2)
                .foregroundStyle(isCurrent ? .blue : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(TimeFormatters.mmss(track.duration))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("· \(track.collectionName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if track.subtitleFileName != nil {
                        Text("字幕")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Spacer()

            Menu {
                Button {
                    engine.pause()
                    transcribeTargetTrack = track
                } label: {
                    Label("语音识别自动生成字幕", systemImage: "sparkles")
                }
                Button {
                    subtitleTargetTrackID = track.id
                    showSubtitleImporter = true
                } label: {
                    Label("导入配套字幕 (.srt / .lrc)", systemImage: "captions.bubble")
                }

                Menu("移动到合集") {
                    ForEach(library.collections, id: \.self) { col in
                        Button(col) {
                            var copy = track
                            copy.collectionName = col
                            library.updateTrack(copy)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            engine.loadTrack(track, autoPlay: true)
            selectedTab = 0
        }
    }
}
