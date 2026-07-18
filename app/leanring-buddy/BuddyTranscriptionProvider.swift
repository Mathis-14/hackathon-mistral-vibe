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
    // Orchestral: Voxtral (via the OpenAI-compatible transcription provider,
    // pointed at api.mistral.ai) is the primary backend; Apple Speech stays as
    // the zero-config on-device fallback so push-to-talk always works.
    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let voxtralProvider = OpenAIAudioTranscriptionProvider()
        if voxtralProvider.isConfigured {
            print("🎙️ Transcription: using \(voxtralProvider.displayName)")
            return voxtralProvider
        }
        print("⚠️ Transcription: Voxtral not configured, falling back to Apple Speech")
        return AppleSpeechTranscriptionProvider()
    }
}
