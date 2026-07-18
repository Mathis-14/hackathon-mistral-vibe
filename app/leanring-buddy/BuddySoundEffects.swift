//
//  BuddySoundEffects.swift
//  Vibe Buddy
//
//  The cat's voice: a real recorded meow celebrates a finished Vibe Code
//  agent (played by the notification), a real recorded hiss calls out
//  failures. Both live in the bundle as wav (recorded by the team).
//

import AppKit

@MainActor
enum BuddySoundEffects {
    private static var currentSound: NSSound?

    /// The cat hisses: worker unreachable, stream failure, launch failure.
    static func playHiss() {
        play(resource: "hiss")
    }

    private static func play(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            NSSound.beep()
            return
        }
        currentSound?.stop()
        currentSound = sound
        sound.play()
    }
}
