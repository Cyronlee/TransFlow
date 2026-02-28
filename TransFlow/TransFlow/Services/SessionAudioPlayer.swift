import AVFoundation

/// A recording segment loaded for playback — stores file, player, and the global offset
/// at which this segment starts in the merged timeline.
struct PlaybackSegment {
    let fileName: String
    let player: AVAudioPlayer
    /// Start of this segment in the merged timeline (seconds).
    let globalOffset: TimeInterval
    /// ISO8601 timestamp from the recording_start marker.
    let recordingTimestamp: String

    var duration: TimeInterval { player.duration }
    var globalEnd: TimeInterval { globalOffset + duration }
}

/// Observable audio player that merges multiple recording segments into a single timeline.
///
/// Subtitle offsets are computed at runtime by comparing each content entry's `start_time`
/// against the `recording_start` timestamp of its enclosing segment.
@MainActor
@Observable
final class SessionAudioPlayer {

    // MARK: - State

    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    /// Index of the currently highlighted subtitle entry.
    var activeEntryIndex: Int? = nil

    /// Segment boundaries (globalOffset values) for UI markers on the seek bar.
    var segmentOffsets: [TimeInterval] = []

    // MARK: - Private

    private var segments: [PlaybackSegment] = []
    private var currentSegmentIndex: Int = 0
    private var timer: Timer?

    /// Computed subtitle offsets: for each content entry, its position in the merged timeline (seconds).
    /// `nil` if the entry doesn't fall within any recording segment.
    private var entryOffsets: [TimeInterval?] = []
    private var entryEndOffsets: [TimeInterval?] = []

    // MARK: - Loading

    /// Load one or more recording segments and their corresponding content entries.
    /// `allLines` is the full parsed JSONL; recordings are paired with content entries by timestamp.
    func load(allLines: [JSONLLine]) {
        unload()

        let isoFormatter = ISO8601DateFormatter()

        // Build segments from recording_start markers
        var segmentInfos: [(fileName: String, timestamp: String, startDate: Date)] = []
        for line in allLines {
            if case .recordingStart(let r) = line {
                if let date = isoFormatter.date(from: r.timestamp) {
                    segmentInfos.append((r.recordingFile, r.timestamp, date))
                }
            }
        }

        // Load audio files and compute global offsets
        var loadedSegments: [PlaybackSegment] = []
        var runningOffset: TimeInterval = 0

        for info in segmentInfos {
            let url = AudioRecordingService.recordingURL(for: info.fileName)
            guard AudioRecordingService.recordingExists(named: info.fileName),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()

            let seg = PlaybackSegment(
                fileName: info.fileName,
                player: player,
                globalOffset: runningOffset,
                recordingTimestamp: info.timestamp
            )
            loadedSegments.append(seg)
            runningOffset += player.duration
        }

        guard !loadedSegments.isEmpty else { return }

        self.segments = loadedSegments
        self.duration = runningOffset
        self.segmentOffsets = loadedSegments.map(\.globalOffset)

        // Compute entry offsets by matching each content entry to its enclosing segment
        let entries: [JSONLContentEntry] = allLines.compactMap {
            if case .content(let e) = $0 { return e } else { return nil }
        }

        // For each entry we compute two timeline positions:
        //   - "end offset": the point when the sentence was finalized (startTime in JSONL,
        //     which is actually the sentence completion timestamp)
        //   - "start offset": approximate start of the utterance, estimated as the previous
        //     entry's end offset (or segment start for the first entry)
        var rawEndOffsets: [TimeInterval?] = []

        for entry in entries {
            guard let entryDate = isoFormatter.date(from: entry.startTime) else {
                rawEndOffsets.append(nil)
                continue
            }

            var matched: PlaybackSegment?
            var matchedInfo: (fileName: String, timestamp: String, startDate: Date)?
            for seg in loadedSegments {
                if let info = segmentInfos.first(where: { $0.fileName == seg.fileName }),
                   info.startDate <= entryDate {
                    matched = seg
                    matchedInfo = info
                }
            }

            if let seg = matched, let info = matchedInfo {
                let relative = entryDate.timeIntervalSince(info.startDate)
                rawEndOffsets.append(seg.globalOffset + max(0, relative))
            } else {
                rawEndOffsets.append(nil)
            }
        }

        // Derive start offsets: entry i starts where entry i-1 ended.
        // For the first entry in a segment, start at the segment's global offset.
        var offsets: [TimeInterval?] = []
        var endOffsets: [TimeInterval?] = []

        for (i, endOpt) in rawEndOffsets.enumerated() {
            guard endOpt != nil else {
                offsets.append(nil)
                endOffsets.append(nil)
                continue
            }
            endOffsets.append(endOpt)

            if i == 0 {
                offsets.append(0)
            } else if let prevEnd = rawEndOffsets[i - 1] {
                offsets.append(prevEnd)
            } else {
                offsets.append(endOpt)
            }
        }

        self.entryOffsets = offsets
        self.entryEndOffsets = endOffsets
    }

    func unload() {
        stop()
        segments = []
        duration = 0
        currentTime = 0
        activeEntryIndex = nil
        segmentOffsets = []
        entryOffsets = []
        entryEndOffsets = []
        currentSegmentIndex = 0
    }

    // MARK: - Playback

    func play() {
        guard !segments.isEmpty, !isPlaying else { return }
        let idx = segmentIndex(for: currentTime)
        currentSegmentIndex = idx
        let seg = segments[idx]
        seg.player.currentTime = currentTime - seg.globalOffset
        seg.player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        segments[safe: currentSegmentIndex]?.player.pause()
        isPlaying = false
        stopTimer()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func stop() {
        for seg in segments { seg.player.stop(); seg.player.currentTime = 0 }
        isPlaying = false
        currentTime = 0
        activeEntryIndex = nil
        currentSegmentIndex = 0
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        let wasPlaying = isPlaying
        if wasPlaying {
            segments[safe: currentSegmentIndex]?.player.pause()
        }
        currentTime = clamped
        let idx = segmentIndex(for: clamped)
        currentSegmentIndex = idx
        let seg = segments[idx]
        seg.player.currentTime = clamped - seg.globalOffset

        if wasPlaying {
            seg.player.play()
        }
        updateActiveEntry()
    }

    /// Seek to the position of an entry by index.
    func seekToEntry(at index: Int) {
        guard index >= 0 && index < entryOffsets.count else { return }
        guard let offset = entryOffsets[index] else { return }
        seek(to: offset)
    }

    /// Global offset for an entry, if available.
    func entryOffset(at index: Int) -> TimeInterval? {
        guard index >= 0 && index < entryOffsets.count else { return nil }
        return entryOffsets[index]
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !segments.isEmpty else { return }
        let seg = segments[currentSegmentIndex]
        currentTime = seg.globalOffset + seg.player.currentTime

        // Check if current segment finished — advance to next
        if !seg.player.isPlaying && isPlaying {
            if currentSegmentIndex + 1 < segments.count {
                currentSegmentIndex += 1
                let next = segments[currentSegmentIndex]
                next.player.currentTime = 0
                next.player.play()
                currentTime = next.globalOffset
            } else {
                isPlaying = false
                stopTimer()
            }
        }

        updateActiveEntry()
    }

    private func updateActiveEntry() {
        let pos = currentTime
        var best: Int? = nil

        for (i, startOpt) in entryOffsets.enumerated() {
            guard let start = startOpt else { continue }
            let end = entryEndOffsets[i] ?? (i + 1 < entryOffsets.count ? entryOffsets[i + 1] ?? Double.greatestFiniteMagnitude : Double.greatestFiniteMagnitude)
            if pos >= start && pos < end {
                best = i
                break
            }
        }

        if activeEntryIndex != best {
            activeEntryIndex = best
        }
    }

    // MARK: - Helpers

    /// Find which segment contains the given global time.
    private func segmentIndex(for time: TimeInterval) -> Int {
        for (i, seg) in segments.enumerated().reversed() {
            if time >= seg.globalOffset { return i }
        }
        return 0
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
