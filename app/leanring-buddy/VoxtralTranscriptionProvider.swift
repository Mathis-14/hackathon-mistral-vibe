//
//  VoxtralTranscriptionProvider.swift
//  Vibe Buddy
//
//  Push-to-talk transcription through Mistral's Voxtral, via the worker's
//  /transcribe route (multipart passthrough to /v1/audio/transcriptions,
//  model voxtral-mini-latest). The app never holds an API key (MUST #5) —
//  the worker injects it server-side.
//
//  Config (UserDefaults):
//    vibebuddy.workerURL  — worker base URL, default http://127.0.0.1:8787
//    vibebuddy.stt        — set to "apple" to force the on-device fallback
//

import AVFoundation
import Foundation

struct VoxtralTranscriptionProviderError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

final class VoxtralTranscriptionProvider: BuddyTranscriptionProvider {
    static let workerURLDefaultsKey = "vibebuddy.workerURL"
    static let sttModeDefaultsKey = "vibebuddy.stt"

    let displayName = "Voxtral"
    let requiresSpeechRecognitionPermission = false

    var isConfigured: Bool {
        UserDefaults.standard.string(forKey: Self.sttModeDefaultsKey) != "apple"
    }

    var unavailableExplanation: String? {
        guard !isConfigured else { return nil }
        return "Voxtral is disabled (vibebuddy.stt=apple) — using Apple Speech."
    }

    static var transcribeURL: URL {
        let base = UserDefaults.standard.string(forKey: workerURLDefaultsKey)
            ?? "http://127.0.0.1:8787"
        return URL(string: base)!.appendingPathComponent("transcribe")
    }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession {
        VoxtralTranscriptionSession(
            transcribeURL: Self.transcribeURL,
            onTranscriptUpdate: onTranscriptUpdate,
            onFinalTranscriptReady: onFinalTranscriptReady,
            onError: onError
        )
    }
}

private final class VoxtralTranscriptionSession: BuddyStreamingTranscriptionSession {
    let finalTranscriptFallbackDelaySeconds: TimeInterval = 8.0

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private static let targetSampleRate = 16_000

    private let transcribeURL: URL
    private let onTranscriptUpdate: (String) -> Void
    private let onFinalTranscriptReady: (String) -> Void
    private let onError: (Error) -> Void

    private let stateQueue = DispatchQueue(label: "com.vibebuddy.voxtral.transcription")
    private let audioPCM16Converter = BuddyPCM16AudioConverter(
        targetSampleRate: Double(targetSampleRate)
    )
    private let urlSession: URLSession

    private var bufferedPCM16AudioData = Data()
    private var hasRequestedFinalTranscript = false
    private var hasDeliveredFinalTranscript = false
    private var isCancelled = false
    private var transcriptionUploadTask: Task<Void, Never>?

    init(
        transcribeURL: URL,
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.transcribeURL = transcribeURL
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFinalTranscriptReady = onFinalTranscriptReady
        self.onError = onError

        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = 30
        urlSessionConfiguration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: urlSessionConfiguration)
    }

    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        guard let audioPCM16Data = audioPCM16Converter.convertToPCM16Data(from: audioBuffer),
              !audioPCM16Data.isEmpty else {
            return
        }

        stateQueue.async {
            guard !self.hasRequestedFinalTranscript, !self.isCancelled else { return }
            self.bufferedPCM16AudioData.append(audioPCM16Data)
        }
    }

    func requestFinalTranscript() {
        stateQueue.async {
            guard !self.hasRequestedFinalTranscript, !self.isCancelled else { return }
            self.hasRequestedFinalTranscript = true

            let bufferedPCM16AudioData = self.bufferedPCM16AudioData
            // Strong capture ON PURPOSE: the dictation manager releases the
            // session right after stop, so this task is what keeps the
            // session alive until the upload delivers the transcript (the
            // weak-capture version deallocated mid-flight and the panel hung
            // on "Transcribing…" forever). The task ends, the cycle breaks.
            self.transcriptionUploadTask = Task {
                await self.transcribeBufferedAudio(bufferedPCM16AudioData)
            }
        }
    }

    func cancel() {
        stateQueue.async {
            self.isCancelled = true
            self.bufferedPCM16AudioData.removeAll(keepingCapacity: false)
        }

        transcriptionUploadTask?.cancel()
        urlSession.invalidateAndCancel()
    }

    private func transcribeBufferedAudio(_ bufferedPCM16AudioData: Data) async {
        guard !Task.isCancelled else { return }

        let trimmedAudioDataIsEmpty = stateQueue.sync {
            isCancelled || bufferedPCM16AudioData.isEmpty
        }

        if trimmedAudioDataIsEmpty {
            deliverFinalTranscript("")
            return
        }

        let wavAudioData = BuddyWAVFileBuilder.buildWAVData(
            fromPCM16MonoAudio: bufferedPCM16AudioData,
            sampleRate: Self.targetSampleRate
        )

        do {
            let transcriptText = try await requestTranscription(for: wavAudioData)
            guard !stateQueue.sync(execute: { isCancelled }) else { return }

            if !transcriptText.isEmpty {
                onTranscriptUpdate(transcriptText)
            }

            deliverFinalTranscript(transcriptText)
        } catch {
            guard !stateQueue.sync(execute: { isCancelled }) else { return }
            print("[Voxtral] ❌ /transcribe failed (audio size: \(wavAudioData.count) bytes): \(error.localizedDescription)")
            onError(error)
        }
    }

    private func requestTranscription(for wavAudioData: Data) async throws -> String {
        let multipartBoundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: transcribeURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(multipartBoundary)", forHTTPHeaderField: "Content-Type")

        // Minimal field set: the worker owns auth and forces the model when
        // absent; no language field so Voxtral auto-detects (FR/EN demo).
        var requestBodyData = Data()
        requestBodyData.appendMultipartFormField(
            named: "model",
            value: "voxtral-mini-latest",
            usingBoundary: multipartBoundary
        )
        requestBodyData.appendMultipartFileField(
            named: "file",
            filename: "voice-input.wav",
            mimeType: "audio/wav",
            fileData: wavAudioData,
            usingBoundary: multipartBoundary
        )
        requestBodyData.appendString("--\(multipartBoundary)--\r\n")
        request.httpBody = requestBodyData

        let (responseData, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoxtralTranscriptionProviderError(
                message: "The worker /transcribe returned an invalid response."
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw VoxtralTranscriptionProviderError(
                message: "Worker /transcribe failed (\(httpResponse.statusCode)): \(responseText)"
            )
        }

        if let transcriptionResponse = try? JSONDecoder().decode(
            TranscriptionResponse.self,
            from: responseData
        ) {
            return transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw VoxtralTranscriptionProviderError(
            message: "Worker /transcribe returned no transcript text."
        )
    }

    private func deliverFinalTranscript(_ transcriptText: String) {
        guard !hasDeliveredFinalTranscript else { return }
        hasDeliveredFinalTranscript = true
        onFinalTranscriptReady(transcriptText)
    }

    deinit {
        // No cancel() here: dispatching a self-capturing block from deinit is
        // the "dangling reference" runtime warning. By deinit time the upload
        // task has either finished (it retains self) or was cancelled
        // explicitly by the dictation manager.
        urlSession.invalidateAndCancel()
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(string.data(using: .utf8)!)
    }

    mutating func appendMultipartFormField(
        named fieldName: String,
        value: String,
        usingBoundary boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFileField(
        named fieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        usingBoundary boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
