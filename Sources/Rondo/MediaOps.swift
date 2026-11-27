import AVFoundation
import Foundation

enum MediaOps {
    static func ff(_ args: [String]) throws {
        guard let ff = Shell.ffmpeg else {
            throw OpError(L("ffmpeg non trovato. Installalo con: brew install ffmpeg"))
        }
        var duration = 0.0
        var input: String?
        if let i = args.firstIndex(of: "-i"), i + 1 < args.count {
            input = args[i + 1]
            let d = CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: args[i + 1])).duration)
            if d.isFinite, d > 0 { duration = d }
        }
        try Shell.run(ff, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-progress", "pipe:1", "-nostats"] + args) { line in
            guard duration > 0, line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms="),
                  let v = Double(line.split(separator: "=").last ?? "") else { return }
            Jobs.report(input: input, fraction: v / 1_000_000 / duration)
        }
    }

    /// Encoders compiled into the installed ffmpeg (computed once).
    private static var cachedEncoders: Set<String>?
    private static let cacheLock = NSLock()

    static var encoders: Set<String> {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = cachedEncoders { return c }
        guard let ff = Shell.ffmpeg, let out = try? Shell.run(ff, ["-hide_banner", "-encoders"]) else { return [] }
        let set = Set(out.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count > 1 ? String(parts[1]) : nil
        })
        cachedEncoders = set
        return set
    }

    /// Call after ffmpeg gets installed or its path changes.
    static func resetEncoderCache() {
        cacheLock.lock(); cachedEncoders = nil; cacheLock.unlock()
    }

    static func hasEncoder(_ name: String) -> Bool { encoders.contains(name) }

    /// An item that runs `ffmpeg -i <in> <args> <out>` for each file.
    static func ffItem(_ title: String, symbol: String = "", ext: String?, suffix: String? = nil, args: [String]) -> WheelItem {
        WheelItem(title: title, symbol: symbol, ext: symbol.isEmpty ? ext : nil) { urls in
            try urls.map { u in
                let e = ext ?? u.pathExtension.lowercased()
                let out = Engine.output(for: u, ext: e, suffix: suffix)
                try ff(["-i", u.path] + args + [out.path])
                return out
            }
        }
    }

    // MARK: Audio

    static func audioConvertItems() -> [WheelItem] {
        if Shell.ffmpeg != nil {
            return [
                ffItem("MP3", ext: "mp3", args: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]),
                ffItem("M4A", ext: "m4a", args: ["-vn", "-c:a", "aac", "-b:a", "256k"]),
                ffItem("WAV", ext: "wav", args: ["-vn", "-c:a", "pcm_s16le"]),
                ffItem("FLAC", ext: "flac", args: ["-vn", "-c:a", "flac"]),
                ffItem("AIFF", ext: "aiff", args: ["-vn", "-c:a", "pcm_s16be"]),
                ffItem("OGG", ext: "ogg", args: ["-vn", "-c:a", "libvorbis", "-q:a", "6"]),
                ffItem("Opus", ext: "opus", args: ["-vn", "-c:a", "libopus", "-b:a", "160k"]),
                ffItem("WMA", ext: "wma", args: ["-vn", "-c:a", "wmav2", "-b:a", "192k"]),
            ]
        }
        // Built-in fallback via afconvert (no ffmpeg)
        func af(_ title: String, _ ext: String, _ args: [String]) -> WheelItem {
            WheelItem(title: title, ext: ext) { urls in
                try urls.map { u in
                    let out = Engine.output(for: u, ext: ext)
                    try Shell.run("/usr/bin/afconvert", args + [u.path, out.path])
                    return out
                }
            }
        }
        return [
            af("M4A", "m4a", ["-f", "m4af", "-d", "aac", "-b", "256000"]),
            af("WAV", "wav", ["-f", "WAVE", "-d", "LEI16"]),
            af("AIFF", "aiff", ["-f", "AIFF", "-d", "BEI16"]),
            af("FLAC", "flac", ["-f", "flac", "-d", "flac"]),
            af("CAF", "caf", ["-f", "caff", "-d", "aac"]),
        ]
    }

    static func audioToolItems() -> [WheelItem] {
        guard Shell.ffmpeg != nil else { return [] }
        let trim = "silenceremove=start_periods=1:start_silence=0.1:start_threshold=-50dB"
        return [
            ffItem(L("Comprimi"), symbol: "arrow.down.right.and.arrow.up.left", ext: "mp3", suffix: L("compresso"),
                   args: ["-vn", "-c:a", "libmp3lame", "-b:a", "128k"]),
            ffItem(L("Normalizza"), symbol: "waveform", ext: nil, suffix: L("normalizzato"), args: ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]),
            ffItem("Mono", symbol: "speaker.wave.1", ext: nil, suffix: "mono", args: ["-ac", "1"]),
            ffItem(L("Togli silenzi"), symbol: "scissors", ext: nil, suffix: L("senza silenzi"),
                   args: ["-af", "\(trim),areverse,\(trim),areverse"]),
            ffItem(L("Velocità 1.5×"), symbol: "hare", ext: nil, suffix: "1.5x", args: ["-af", "atempo=1.5"]),
        ]
    }

    // MARK: Video

    static let x264 = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"]
    static let gifFilter = "fps=12,scale=min(640\\,iw):-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"

    static func videoConvertItems() -> [WheelItem] {
        if Shell.ffmpeg != nil {
            return [
                ffItem("MP4", ext: "mp4", args: x264 + ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]),
                ffItem("MOV", ext: "mov", args: x264 + ["-c:a", "aac", "-b:a", "192k"]),
                ffItem("MKV", ext: "mkv", args: x264 + ["-c:a", "aac", "-b:a", "192k"]),
                ffItem("WebM", ext: "webm", args: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1",
                                                     "-deadline", "good", "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k"]),
                ffItem("AVI", ext: "avi", args: ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame", "-q:a", "3"]),
                ffItem("WMV", ext: "wmv", args: ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2", "-b:a", "192k"]),
                ffItem("GIF", ext: "gif", args: ["-vf", gifFilter, "-loop", "0"]),
                ffItem("MP3", ext: "mp3", args: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]),
                ffItem("M4A", ext: "m4a", args: ["-vn", "-c:a", "aac", "-b:a", "192k"]),
            ]
        }
        return [
            WheelItem(title: "MP4", ext: "mp4") { try $0.map { try avExport($0, AVAssetExportPresetHighestQuality, .mp4, "mp4") } },
            WheelItem(title: "MOV", ext: "mov") { try $0.map { try avExport($0, AVAssetExportPresetHighestQuality, .mov, "mov") } },
            WheelItem(title: "M4A", ext: "m4a") { try $0.map { try avExport($0, AVAssetExportPresetAppleM4A, .m4a, "m4a") } },
        ]
    }

    static func videoToolItems() -> [WheelItem] {
        guard Shell.ffmpeg != nil else {
            return [
                WheelItem(title: L("Comprimi"), symbol: "arrow.down.right.and.arrow.up.left") {
                    try $0.map { try avExport($0, AVAssetExportPresetMediumQuality, .mp4, "mp4", suffix: L("compresso")) }
                },
                WheelItem(title: L("Estrai audio"), symbol: "music.note") {
                    try $0.map { try avExport($0, AVAssetExportPresetAppleM4A, .m4a, "m4a") }
                },
            ]
        }
        return [
            ffItem(L("Comprimi"), symbol: "arrow.down.right.and.arrow.up.left", ext: "mp4", suffix: L("compresso"),
                   args: ["-c:v", "libx264", "-preset", "medium", "-crf", "28", "-pix_fmt", "yuv420p",
                          "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]),
            ffItem(L("Metà risoluzione"), symbol: "aspectratio", ext: "mp4", suffix: "50%",
                   args: ["-vf", "scale=trunc(iw/4)*2:trunc(ih/4)*2"] + x264 + ["-c:a", "copy"]),
            ffItem(L("Togli audio"), symbol: "speaker.slash", ext: nil, suffix: L("muto"), args: ["-c:v", "copy", "-an"]),
            ffItem(L("Estrai audio"), symbol: "music.note", ext: "m4a", args: ["-vn", "-c:a", "aac", "-b:a", "192k"]),
            ffItem(L("Ruota 90°"), symbol: "rotate.right", ext: "mp4", suffix: L("ruotato"),
                   args: ["-vf", "transpose=1"] + x264 + ["-c:a", "copy"]),
            ffItem(L("Velocità 2×"), symbol: "hare", ext: "mp4", suffix: "2x",
                   args: ["-filter:v", "setpts=0.5*PTS", "-filter:a", "atempo=2.0"] + x264),
            ffItem(L("Fotogramma"), symbol: "photo", ext: "jpg", suffix: L("frame"),
                   args: ["-ss", "00:00:01", "-frames:v", "1", "-q:v", "2"]),
        ]
    }

    static func avExport(_ url: URL, _ preset: String, _ type: AVFileType, _ ext: String, suffix: String? = nil) throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw OpError(L("Esportazione non supportata per questo file"))
        }
        let out = Engine.output(for: url, ext: ext, suffix: suffix)
        s.outputURL = out
        s.outputFileType = type
        s.shouldOptimizeForNetworkUse = true
        let sem = DispatchSemaphore(value: 0)
        s.exportAsynchronously { sem.signal() }
        sem.wait()
        guard s.status == .completed else {
            throw OpError(s.error?.localizedDescription ?? L("Esportazione non riuscita"))
        }
        return out
    }
}
