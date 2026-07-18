//
//  BuddyTranscriptionProvider.swift
//  leanring-buddy
//
//  Shared protocol surface for voice transcription backends.
//

import AVFoundation
import Foundation

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

enum BuddyTranscriptionProviderFactory {
    // Voxtral through the local worker (/transcribe) is the primary backend —
    // keys live worker-side only (MUST #5, D018). Apple Speech stays as the
    // zero-config on-device fallback so push-to-talk always works even when
    // wrangler dev is down.
    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let voxtralProvider = WorkerTranscriptionProvider()
        if voxtralProvider.isConfigured {
            print("🎙️ Transcription: using \(voxtralProvider.displayName) via worker /transcribe")
            return voxtralProvider
        }
        print("⚠️ Transcription: worker unavailable, falling back to Apple Speech")
        return AppleSpeechTranscriptionProvider()
    }
}
