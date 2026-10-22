import Foundation
import DotLocalBridge
import CryptoKit
import UserNotifications
import AVFoundation
import SwiftUI

@MainActor final class DotDailyBriefRepository: DailyBriefRepository {
    private var exchangeGeneration = 0
    private let directory: URL
    private let pairing: @MainActor () throws -> RelayPairing?
    private let exchangeInput: @MainActor (RelayPairing, String) async throws -> Data
    private let audioInput: @MainActor (RelayPairing, String) async throws -> Data
    private let ready: (@MainActor (String, String) async -> Void)?
    init(directory: URL = URL.applicationSupportDirectory.appending(path: "DotDailyBrief"),
         pairing: (@MainActor () throws -> RelayPairing?)? = nil,
         exchange: (@MainActor (RelayPairing, String) async throws -> Data)? = nil,
         audio: (@MainActor (RelayPairing, String) async throws -> Data)? = nil,
         ready: (@MainActor (String, String) async -> Void)? = nil) {
        self.exchangeInput = exchange ?? { try await $0.transport().exchangeDailyBrief(inputJSON: $1) }
        self.audioInput = audio ?? { try await $0.transport().fetchDailyAudio(sha256: $1) }
        self.ready = ready
        self.directory = directory
        self.pairing = pairing ?? { try KeychainRelayPairing().load() }
    }
    private func file(_ context: DailyBriefContext, bridgeID: String) -> URL {
        // Pairing identity is part of the cache key: another Mac's prose is never reused.
        directory.appending(path: bridgeID).appending(path: context.date + "-" + context.timeZone.replacingOccurrences(of: "/", with: "_") + ".json")
    }
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
    func cached(for context: DailyBriefContext) throws -> DailyBrief? {
        guard let pair = try pairing() else { return nil }
        let url = file(context, bridgeID: pair.bridgeID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let brief = try decoder().decode(DailyBrief.self, from: Data(contentsOf: url))
        guard brief.date == context.date, brief.timeZone == context.timeZone else { return nil }
        return brief
    }
    func exchange(_ context: DailyBriefContext) async throws -> DailyBrief? {
        exchangeGeneration += 1
        let generation = exchangeGeneration
        guard let pair = try pairing() else { throw BridgeNetworkError.unavailable }
        let input = try context.encodedInput()
        let data = try await exchangeInput(pair, input)
        guard generation == exchangeGeneration, !Task.isCancelled else { throw CancellationError() }
        struct Response: Decodable { let brief: DailyBrief? }
        guard let brief = try decoder().decode(Response.self, from: data).brief else { return nil }
        guard brief.date == context.date, brief.timeZone == context.timeZone,
              ["outlook", "reflection"].contains(brief.kind), !brief.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              brief.text.count <= 2000 else { throw BridgeNetworkError.unexpectedResponse }
        if let audio = brief.audio, let id = brief.briefID {
            guard Self.validID(id), Self.validID(audio.sha256), (44...12 * 1024 * 1024).contains(audio.byteCount),
                  audio.contentType == "audio/wav", audio.duration.isFinite, audio.duration > 0 else { throw BridgeNetworkError.unexpectedResponse }
            let folder = directory.appending(path: pair.bridgeID).appending(path: "audio")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let audioURL = folder.appending(path: audio.sha256 + ".wav")
            let existing = try? Data(contentsOf: audioURL)
            if existing.map({ Self.digest($0) == audio.sha256 && $0.count == audio.byteCount }) != true {
                let bytes = try await audioInput(pair, audio.sha256)
                guard generation == exchangeGeneration, !Task.isCancelled else { throw CancellationError() }
                guard bytes.count == audio.byteCount, Self.digest(bytes) == audio.sha256 else { throw BridgeNetworkError.unexpectedResponse }
                try bytes.write(to: audioURL, options: [.atomic, .completeFileProtection])
            }
            // A pairing switch while downloading must never publish the old Mac's notification.
            guard try pairing()?.bridgeID == pair.bridgeID else { throw BridgeNetworkError.unavailable }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(brief).write(to: folder.appending(path: id + ".json"), options: [.atomic, .completeFileProtection])
            if let ready { await ready(id, pair.bridgeID) }
            else { await notifyOnce(id: id, bridgeID: pair.bridgeID, folder: folder, generation: generation) }
        }
        guard generation == exchangeGeneration, !Task.isCancelled else { throw CancellationError() }
        let url = file(context, bridgeID: pair.bridgeID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(brief).write(to: url, options: [.atomic, .completeFileProtection])
        return brief
    }
    static func validID(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isHexDigit } }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func reserveNotification(_ marker: URL) throws { try Data().write(to: marker, options: [.withoutOverwriting, .completeFileProtection]) }
    private func notifyOnce(id: String, bridgeID: String, folder: URL, generation: Int) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard generation == exchangeGeneration, !Task.isCancelled, [.authorized, .provisional, .ephemeral].contains(status) else { return }
        let marker = folder.appending(path: id + ".notified")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            // Reserve before enqueue: an interruption can suppress a notice, never duplicate it.
            try Self.reserveNotification(marker)
            let content = UNMutableNotificationContent()
            content.title = "今日の見通しが届きました"
            content.body = "タップして文章と音声を確認できます。"
            content.sound = .default
            content.userInfo = ["dailyBriefID": id, "bridgeID": bridgeID]
            do { try await center.add(UNNotificationRequest(identifier: "dailyBrief." + bridgeID + "." + id, content: content, trigger: nil)) }
            catch { try? FileManager.default.removeItem(at: marker) }
        } catch { /* A concurrent/retried receive already reserved this notice. */ }
    }
    static func playback(_ request: BriefPlaybackRequest) throws -> (DailyBrief, URL) {
        guard validID(request.briefID), let pair = try KeychainRelayPairing().load(), pair.bridgeID == request.bridgeID else {
            throw BridgeNetworkError.unavailable
        }
        let folder = URL.applicationSupportDirectory.appending(path: "DotDailyBrief").appending(path: pair.bridgeID).appending(path: "audio")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let brief = try decoder.decode(DailyBrief.self, from: Data(contentsOf: folder.appending(path: request.briefID + ".json")))
        guard brief.briefID == request.briefID, let audio = brief.audio, validID(audio.sha256) else { throw BridgeNetworkError.unexpectedResponse }
        let url = folder.appending(path: audio.sha256 + ".wav")
        let data = try Data(contentsOf: url)
        guard data.count == audio.byteCount, digest(data) == audio.sha256 else { throw BridgeNetworkError.unexpectedResponse }
        return (brief, url)
    }

}


struct BriefPlaybackRequest: Identifiable {
    let briefID: String
    let bridgeID: String
    var id: String { bridgeID + "." + briefID }
}
@MainActor final class BriefPlaybackRouter: ObservableObject {
    static let shared = BriefPlaybackRouter()
    @Published var request: BriefPlaybackRequest?
    func open(briefID: String, bridgeID: String) {
        guard DotDailyBriefRepository.validID(briefID) else { return }
        request = .init(briefID: briefID, bridgeID: bridgeID)
    }
}
struct BriefPlaybackView: View {
    let request: BriefPlaybackRequest
    @State private var brief: DailyBrief?
    @State private var player: AVAudioPlayer?
    @State private var message: String?
    @State private var position: Double = 0
    @State private var isPlaying = false
    @State private var isSeeking = false
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let brief {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(brief.date, systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("Dotのひとこと")
                                .font(.title2.bold())
                            Text("今日の流れを、ゆっくり確認しましょう。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let player { audioControls(player) }
                        VStack(alignment: .leading, spacing: 16) {
                            Label("今日の見通し", systemImage: "sun.horizon")
                                .font(.headline)
                                .foregroundStyle(.tint)
                            Text(brief.text)
                                .font(.body)
                                .lineSpacing(8)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(22)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    } else if message == nil {
                        ProgressView("見通しを読み込んでいます…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    }
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("今日の見通し")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            do {
                let (saved, url) = try DotDailyBriefRepository.playback(request)
                brief = saved
                player = try AVAudioPlayer(contentsOf: url)
                play()
            } catch { message = "音声を確認できません。Mac接続中に今日の画面を更新してください。" }
        }
        .onReceive(ticker) { _ in
            guard let player, !isSeeking else { return }
            position = player.currentTime
            isPlaying = player.isPlaying
        }
        .onDisappear {
            player?.stop()
            isPlaying = false
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    private func audioControls(_ player: AVAudioPlayer) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("音声で聴く", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text(isPlaying ? "再生中" : "停止中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Slider(value: $position, in: 0...max(player.duration, 0.01)) { editing in
                    isSeeking = editing
                    if !editing { player.currentTime = position }
                }
                .accessibilityLabel("再生位置")
                .accessibilityValue("\(timeLabel(position)) / \(timeLabel(player.duration))")
                HStack {
                    Text(timeLabel(position))
                    Spacer()
                    Text(timeLabel(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                Button {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    } else { play() }
                } label: {
                    Label(isPlaying ? "一時停止" : "再生", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                Button {
                    player.stop()
                    player.currentTime = 0
                    position = 0
                    isPlaying = false
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("停止して先頭に戻る")
            }
        }
        .padding(20)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
            isPlaying = true
            message = nil
        } catch { message = "音声を再生できません。" }
    }
}
