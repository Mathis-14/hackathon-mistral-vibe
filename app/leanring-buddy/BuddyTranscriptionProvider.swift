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
    // Voxtral through the worker /transcribe route is the primary backend
    // (MUST #7); Apple Speech remains the zero-config on-device fallback,
    // forced with `defaults write com.vibebuddy.app vibebuddy.stt apple`.
    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let voxtralProvider = VoxtralTranscriptionProvider()
        if voxtralProvider.isConfigured {
            print("🎙️ Transcription: using \(voxtralProvider.displayName) via \(VoxtralTranscriptionProvider.transcribeURL)")
            return voxtralProvider
        }
        print("⚠️ Transcription: Voxtral disabled — falling back to Apple Speech")
        return AppleSpeechTranscriptionProvider()
    }
}
