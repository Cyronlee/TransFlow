# 029 - Dual Audio Capture

## Background

This document records research findings for a potential feature that transcribes **microphone audio** and **system audio** at the same time during a live session.

Today, TransFlow supports these live input modes:

- `microphone`
- `systemAudio`
- `appAudio(AppAudioTarget?)`

They are mutually exclusive. The current question is whether the app can support a new mode that runs microphone capture and system-audio capture concurrently, then transcribes both streams in parallel.

## Research Question

Is it technically possible for TransFlow to transcribe **both system audio and microphone audio simultaneously** on macOS?

## Short Answer

Yes. The current architecture and Apple APIs make this feasible.

The existing implementation already has:

- one microphone capture pipeline based on `AVAudioEngine`
- one system/app audio capture pipeline based on `ScreenCaptureKit`
- one transcription pipeline based on Apple `SpeechAnalyzer` + `SpeechTranscriber`

The main missing piece is orchestration: starting both capture services together, creating a separate speech-analysis pipeline for each stream, and presenting the two transcript sources clearly in the UI.

## Current Codebase Findings

### 1. Microphone capture is independent

`TransFlow/TransFlow/Services/AudioCaptureService.swift` captures microphone input with `AVAudioEngine` by installing a tap on the input node and converting the result to 16kHz mono `Float32` `AudioChunk` values.

Implication:

- microphone capture is already encapsulated as an `AsyncStream<AudioChunk>`
- it does not depend on `ScreenCaptureKit`

### 2. System audio capture is independent

`TransFlow/TransFlow/Services/AppAudioCaptureService.swift` captures app/system audio with `ScreenCaptureKit` using `SCStream` and `SCStreamConfiguration`.

It already supports:

- per-app capture via `startCapture(for:)`
- all-system capture via `startSystemCapture()`

Both paths convert ScreenCaptureKit audio into the same 16kHz mono `AudioChunk` format used elsewhere in the app.

Implication:

- system audio already exists as a separate, reusable `AsyncStream<AudioChunk>`
- microphone and system audio are produced by different services and different Apple frameworks

### 3. The transcription engine already consumes a generic audio stream

`TransFlow/TransFlow/Services/SpeechEngine.swift` accepts an `AsyncStream<AudioChunk>` and feeds it into Apple Speech using `SpeechAnalyzer` and `SpeechTranscriber`.

Implication:

- the speech layer does not care whether the audio came from the mic or from ScreenCaptureKit
- running two concurrent transcription pipelines should be possible if each pipeline gets its own stream and analyzer

### 4. The current limitation is in session orchestration, not capture capability

`TransFlow/TransFlow/ViewModels/TransFlowViewModel.swift` currently switches on `audioSource` and starts **one** capture source at a time.

Implication:

- the app is designed around a single active live source today
- dual capture requires ViewModel/session changes more than low-level capture changes

### 5. There is no existing live dual-stream mixing or dual-transcript UI

The app currently fans out a single `AudioChunk` stream to multiple consumers:

- transcription
- level meter
- recording
- optional realtime diarization

This is fan-out, not dual-source mixing.

Implication:

- there is no existing abstraction yet for "two live sources in one session"
- UI and recording behavior must be defined explicitly

## Apple API Validation

The Apple documentation supports the basic building blocks needed for this feature.

### ScreenCaptureKit supports audio capture

Apple documents `SCStreamConfiguration.capturesAudio` as:

> "A Boolean value that indicates whether to capture audio."

Important details:

- audio capture is disabled by default and must be enabled explicitly
- TransFlow already does this in `AppAudioCaptureService`
- `ScreenCaptureKit` is therefore a valid source for the system-audio half of a dual-capture session

Reference:

- `https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio`

### AVAudioEngine input taps support microphone capture

Apple documents `AVAudioNode.installTap(onBus:bufferSize:format:block:)` as a way to:

> "record, monitor, and observe the output of the node"

The documentation example shows installing a tap on `AVAudioEngine.inputNode` to capture live input buffers.

Important details:

- TransFlow already uses this pattern in `AudioCaptureService`
- this is independent of the ScreenCaptureKit pipeline

Reference:

- `https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)`

### Apple Speech supports separate analysis sessions

Apple documents `SpeechAnalyzer` as managing an analysis session and notes:

> "The analyzer can only analyze one input sequence at a time."

This implies a dual-stream design should use:

- one `SpeechAnalyzer` per source
- one `SpeechTranscriber` per source

Apple also documents `SpeechTranscriber` with this note:

> "Several transcriber instances can share the same backing engine instances and models, so long as the transcribers are configured similarly in certain respects."

This is strong evidence that running multiple transcription modules concurrently is an intended use case.

References:

- `https://developer.apple.com/documentation/speech/speechanalyzer`
- `https://developer.apple.com/documentation/speech/speechtranscriber`

## Feasibility Conclusion

Dual transcription is technically feasible in this codebase.

The most likely architecture is:

```text
Microphone
    -> AudioCaptureService
    -> mic AudioChunk stream
    -> SpeechEngine / SpeechAnalyzer / SpeechTranscriber
    -> local transcript lane

System Audio
    -> AppAudioCaptureService.startSystemCapture()
    -> system AudioChunk stream
    -> second SpeechEngine / SpeechAnalyzer / SpeechTranscriber
    -> remote transcript lane
```

This should be implemented as **two parallel pipelines**, not by mixing the two live sources into one shared audio stream.

Reasons:

- keeping sources separate preserves speaker/source identity
- Expression Coach and other future features can treat mic as "local" and system audio as "remote context"
- per-source error handling and performance monitoring become simpler

## Recommended Scope for a First Implementation

### Proposed new mode

Add a new audio-source mode for live transcription, for example:

- `.microphoneAndSystemAudio`

### Proposed behavior

- start `AudioCaptureService` and `AppAudioCaptureService.startSystemCapture()` together
- create a dedicated speech-analysis pipeline for each source
- surface transcript entries with an explicit source label, such as `Local` and `System`
- keep the two streams logically separate all the way to the UI

### Recommended non-goals for v1

- do not merge mic and system audio into one transcript stream without source labels
- do not attempt cross-stream speaker diarization
- do not block the feature on perfect dual-track recording support
- do not try to auto-balance or mix audio levels between sources

## Key Design Choices

### 1. Two analyzers, not one

Because one `SpeechAnalyzer` can analyze only one input sequence at a time, the correct model is:

- one analyzer for microphone audio
- one analyzer for system audio

### 2. Separate transcript identity should be preserved

System audio and microphone audio represent different roles in the conversation.

Recommended semantics:

- microphone transcript = local speaker
- system transcript = remote/app/output audio

This is especially important for the future Expression Coach workflow, where coaching should apply only to local microphone speech while still being able to use remote speech as optional context.

### 3. Realtime diarization should remain microphone-only initially

`RealtimeDiarizationService` currently fits the microphone path much better than the mixed system-audio stream.

Recommended v1 behavior:

- allow diarization on microphone audio only
- treat system audio as unlabeled remote audio

### 4. Recording can be deferred or simplified

`AudioRecordingService` currently assumes one live stream.

Possible v1 options:

- record microphone only
- record system only
- record two separate files
- postpone recording changes until after dual transcription is proven stable

The cleanest sequencing is to validate dual capture + dual transcription first, then define recording UX separately.

## Main Risks

### 1. CPU and memory load

Running two live transcription pipelines likely increases:

- CPU usage
- memory usage
- thermal pressure on lower-end Macs

This is the biggest technical risk and should be validated with a small spike.

### 2. Runtime behavior of concurrent Apple Speech sessions

The Apple documentation supports multiple transcriber instances, but the exact realtime performance characteristics for two concurrent live streams still need validation in the app.

This is a validation risk, not a fundamental architecture blocker.

### 3. UI complexity

The current live transcript UI is built around one source. A dual-source session needs a clear presentation model:

- separate lanes
- interleaved timeline with source badges
- or a hybrid layout

### 4. Session lifecycle complexity

A dual session must define how to handle:

- one source failing while the other keeps running
- per-source permissions and errors
- starting/stopping both services cleanly

## Suggested Spike Plan

Before building the full feature, validate with a narrow spike:

1. Start microphone capture and system-audio capture at the same time.
2. Feed each stream into its own `SpeechEngine`.
3. Log partial/final results from both pipelines with a source tag.
4. Measure CPU, memory, and latency on at least one lower-end Mac and one higher-end Mac if available.
5. Confirm behavior when one stream is silent and the other is active.

Success criteria for the spike:

- both streams produce transcription results concurrently
- stopping one pipeline does not crash the other
- latency remains acceptable for live use
- resource usage is high but manageable

## Open Questions

- What should the live transcript UI look like for two simultaneous sources?
- Should dual capture be a new source mode or a composable option layered on top of microphone mode?
- What should recording export look like in dual mode?
- Should Expression Coach read remote/system transcript history as context in a later version?
- Do we want per-source language selection, or should both streams share one locale in v1?

## Recommendation

Proceed with a proof-of-concept on a dedicated feature branch.

The research result is:

- **possible at the API level**
- **compatible with the current TransFlow architecture**
- **best implemented as two parallel transcription pipelines**
- **main unknowns are performance, UI design, and session orchestration**
