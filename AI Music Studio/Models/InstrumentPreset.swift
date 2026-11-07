//
//  InstrumentPreset.swift
//  AI Music Studio
//

import Foundation

/// One named sound for a voice: the tone, envelope and character its notes are
/// rendered with.
struct InstrumentPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let voice: TrackVoiceKind

    /// Tone centre in hertz: filter cutoff for the synth, excitation brightness
    /// for plucked strings, formant tilt for the voice.
    let brightness: Double
    /// How long the sound rings, as a multiplier on the note's written length.
    let sustain: Double
    let attack: Double
    let release: Double
    /// Vibrato depth for sustained voices, from 0 to about 0.03.
    var vibrato: Double
    /// Overtone or drawbar mix, from 0 to 1.
    let harmonic: Double
    let level: Double
    /// Waveform used by the synth voice; ignored by the others.
    var waveform: SynthWaveform = .saw
}

/// Every preset in the studio, grouped by the voice that plays them.
enum InstrumentPresetLibrary {
    /// The order voices are browsed in.
    static let voiceOrder: [TrackVoiceKind] = [
        .synth, .piano, .strings, .organ, .percussion,
        .acousticGuitar, .electricGuitar, .distortedGuitar, .bassGuitar,
        .marleneVocal
    ]

    static let all: [InstrumentPreset] = synth + piano + strings + organ + percussion
        + acousticGuitar + electricGuitar + distortedGuitar + bassGuitar + vocal

    static func presets(for voice: TrackVoiceKind) -> [InstrumentPreset] {
        all.filter { $0.voice == voice }
    }

    static func preset(id: String?) -> InstrumentPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func defaultPreset(for voice: TrackVoiceKind) -> InstrumentPreset {
        presets(for: voice).first ?? all[0]
    }

    // MARK: - Voices

    private static let synth: [InstrumentPreset] = [
        InstrumentPreset(
            id: "synth-bright-saw", name: "Bright Saw",
            detail: "Cutting saw lead with an open filter",
            voice: .synth, brightness: 7_200, sustain: 1, attack: 0.012,
            release: 0.24, vibrato: 0, harmonic: 0.5, level: 1,
            waveform: .saw
        ),
        InstrumentPreset(
            id: "synth-warm-pad", name: "Warm Pad",
            detail: "Soft saw pad that swells in slowly",
            voice: .synth, brightness: 1_800, sustain: 1.2, attack: 0.24,
            release: 0.62, vibrato: 0.006, harmonic: 0.4, level: 1,
            waveform: .saw
        ),
        InstrumentPreset(
            id: "synth-square-lead", name: "Square Lead",
            detail: "Hollow square lead for hooks",
            voice: .synth, brightness: 4_200, sustain: 1, attack: 0.02,
            release: 0.26, vibrato: 0, harmonic: 0.5, level: 0.9,
            waveform: .square
        ),
        InstrumentPreset(
            id: "synth-sine-bell", name: "Sine Bell",
            detail: "Clean sine with a long ring",
            voice: .synth, brightness: 9_000, sustain: 1.4, attack: 0.005,
            release: 0.8, vibrato: 0, harmonic: 0.5, level: 0.85,
            waveform: .sine
        )
    ]

    private static let piano: [InstrumentPreset] = [
        InstrumentPreset(
            id: "piano-bright-keys", name: "Bright Keys",
            detail: "Hammered piano with a crisp top",
            voice: .piano, brightness: 6_500, sustain: 1, attack: 0.004,
            release: 0.18, vibrato: 0, harmonic: 0.35, level: 1
        ),
        InstrumentPreset(
            id: "piano-soft-upright", name: "Soft Upright",
            detail: "Gentle upright with a rounded edge",
            voice: .piano, brightness: 3_200, sustain: 0.8, attack: 0.006,
            release: 0.2, vibrato: 0, harmonic: 0.2, level: 0.95
        ),
        InstrumentPreset(
            id: "piano-warm-grand", name: "Warm Grand",
            detail: "Full concert grand with long decay",
            voice: .piano, brightness: 4_200, sustain: 1.3, attack: 0.005,
            release: 0.28, vibrato: 0, harmonic: 0.28, level: 1
        ),
        InstrumentPreset(
            id: "piano-felt", name: "Felt Piano",
            detail: "Muted, intimate felt hammers",
            voice: .piano, brightness: 1_800, sustain: 0.75, attack: 0.01,
            release: 0.22, vibrato: 0, harmonic: 0.12, level: 0.9
        )
    ]

    private static let strings: [InstrumentPreset] = [
        InstrumentPreset(
            id: "strings-legato", name: "Legato Strings",
            detail: "Smooth section that bows in together",
            voice: .strings, brightness: 3_400, sustain: 1.1, attack: 0.08,
            release: 0.32, vibrato: 0.008, harmonic: 0.5, level: 0.9
        ),
        InstrumentPreset(
            id: "strings-cinematic", name: "Cinematic Strings",
            detail: "Wide, dramatic swell with deep vibrato",
            voice: .strings, brightness: 4_800, sustain: 1.2, attack: 0.14,
            release: 0.46, vibrato: 0.014, harmonic: 0.55, level: 1
        ),
        InstrumentPreset(
            id: "strings-soft", name: "Soft Ensemble",
            detail: "Quiet, airy background strings",
            voice: .strings, brightness: 2_200, sustain: 1, attack: 0.18,
            release: 0.5, vibrato: 0.006, harmonic: 0.45, level: 0.85
        ),
        InstrumentPreset(
            id: "strings-bright", name: "Bright Strings",
            detail: "Staccato-ready section with bite",
            voice: .strings, brightness: 6_800, sustain: 0.9, attack: 0.05,
            release: 0.24, vibrato: 0.01, harmonic: 0.6, level: 0.9
        )
    ]

    private static let organ: [InstrumentPreset] = [
        InstrumentPreset(
            id: "organ-gospel", name: "Gospel Drawbars",
            detail: "Full drawbar organ with a percussive click",
            voice: .organ, brightness: 5_200, sustain: 1, attack: 0.012,
            release: 0.12, vibrato: 0.004, harmonic: 0.55, level: 0.95
        ),
        InstrumentPreset(
            id: "organ-pipe", name: "Church Pipe",
            detail: "Slow speaking pipes with a long tail",
            voice: .organ, brightness: 3_600, sustain: 1, attack: 0.07,
            release: 0.32, vibrato: 0.002, harmonic: 0.35, level: 0.9
        ),
        InstrumentPreset(
            id: "organ-tonewheel", name: "Tonewheel",
            detail: "Rounded vintage organ, no click",
            voice: .organ, brightness: 2_600, sustain: 1, attack: 0.02,
            release: 0.18, vibrato: 0.006, harmonic: 0.3, level: 0.9
        ),
        InstrumentPreset(
            id: "organ-bright", name: "Bright Organ",
            detail: "Thin, cutting organ for stabs",
            voice: .organ, brightness: 8_000, sustain: 1, attack: 0.008,
            release: 0.1, vibrato: 0.003, harmonic: 0.7, level: 0.85
        )
    ]

    private static let percussion: [InstrumentPreset] = [
        InstrumentPreset(
            id: "percussion-marimba", name: "Marimba",
            detail: "Warm wooden bars with a round mallet",
            voice: .percussion, brightness: 2_400, sustain: 1, attack: 0.003,
            release: 0.3, vibrato: 0, harmonic: 0.35, level: 1
        ),
        InstrumentPreset(
            id: "percussion-soft-mallets", name: "Soft Mallets",
            detail: "Dark, gentle tuned percussion",
            voice: .percussion, brightness: 1_500, sustain: 0.8, attack: 0.004,
            release: 0.35, vibrato: 0, harmonic: 0.2, level: 0.9
        ),
        InstrumentPreset(
            id: "percussion-bells", name: "Tuned Bells",
            detail: "Glass bells with a long shimmer",
            voice: .percussion, brightness: 6_000, sustain: 1.3, attack: 0.002,
            release: 0.6, vibrato: 0.004, harmonic: 0.6, level: 0.9
        ),
        InstrumentPreset(
            id: "percussion-wood", name: "Wood Block",
            detail: "Dry, tight wooden strike",
            voice: .percussion, brightness: 3_200, sustain: 0.35, attack: 0.001,
            release: 0.08, vibrato: 0, harmonic: 0.15, level: 0.85
        )
    ]

    private static let acousticGuitar: [InstrumentPreset] = [
        InstrumentPreset(
            id: "acoustic-fingerpicked", name: "Fingerpicked",
            detail: "Soft fingertips on steel strings",
            voice: .acousticGuitar, brightness: 3_200, sustain: 1, attack: 0,
            release: 0.22, vibrato: 0, harmonic: 0.5, level: 0.95
        ),
        InstrumentPreset(
            id: "acoustic-strummed", name: "Strummed Steel",
            detail: "Bright, ringing strum",
            voice: .acousticGuitar, brightness: 4_800, sustain: 1.2, attack: 0,
            release: 0.24, vibrato: 0, harmonic: 0.6, level: 1
        ),
        InstrumentPreset(
            id: "acoustic-nylon", name: "Soft Nylon",
            detail: "Warm classical guitar",
            voice: .acousticGuitar, brightness: 1_900, sustain: 0.9, attack: 0,
            release: 0.22, vibrato: 0, harmonic: 0.4, level: 0.9
        )
    ]

    private static let electricGuitar: [InstrumentPreset] = [
        InstrumentPreset(
            id: "electric-clean", name: "Clean Neck",
            detail: "Rounded neck pickup with long sustain",
            voice: .electricGuitar, brightness: 2_200, sustain: 1.1, attack: 0,
            release: 0.24, vibrato: 0, harmonic: 0.5, level: 0.95
        ),
        InstrumentPreset(
            id: "electric-bridge", name: "Bridge Twang",
            detail: "Bright bridge pickup with snap",
            voice: .electricGuitar, brightness: 4_600, sustain: 0.95, attack: 0,
            release: 0.22, vibrato: 0, harmonic: 0.6, level: 0.9
        ),
        InstrumentPreset(
            id: "electric-muted", name: "Muted",
            detail: "Palm-muted short notes",
            voice: .electricGuitar, brightness: 1_400, sustain: 0.45, attack: 0,
            release: 0.16, vibrato: 0, harmonic: 0.4, level: 0.85
        )
    ]

    private static let distortedGuitar: [InstrumentPreset] = [
        InstrumentPreset(
            id: "distorted-overdriven", name: "Overdriven",
            detail: "Saturated rhythm voice",
            voice: .distortedGuitar, brightness: 2_000, sustain: 1, attack: 0,
            release: 0.26, vibrato: 0, harmonic: 0.5, level: 0.95
        ),
        InstrumentPreset(
            id: "distorted-lead", name: "Lead",
            detail: "Singing lead with long sustain",
            voice: .distortedGuitar, brightness: 2_800, sustain: 1.25, attack: 0,
            release: 0.28, vibrato: 0.006, harmonic: 0.55, level: 0.9
        ),
        InstrumentPreset(
            id: "distorted-fuzz", name: "Fuzz",
            detail: "Thick, woolly fuzz",
            voice: .distortedGuitar, brightness: 1_200, sustain: 0.9, attack: 0,
            release: 0.24, vibrato: 0, harmonic: 0.7, level: 0.85
        )
    ]

    private static let bassGuitar: [InstrumentPreset] = [
        InstrumentPreset(
            id: "bass-fingered", name: "Fingered",
            detail: "Round fingerstyle bass",
            voice: .bassGuitar, brightness: 900, sustain: 1, attack: 0,
            release: 0.22, vibrato: 0, harmonic: 0.5, level: 1
        ),
        InstrumentPreset(
            id: "bass-picked", name: "Picked",
            detail: "Bright picked bass with attack",
            voice: .bassGuitar, brightness: 1_600, sustain: 0.9, attack: 0,
            release: 0.2, vibrato: 0, harmonic: 0.55, level: 0.95
        ),
        InstrumentPreset(
            id: "bass-sub", name: "Sub Bass",
            detail: "Deep, dark sub tone",
            voice: .bassGuitar, brightness: 500, sustain: 1.25, attack: 0.01,
            release: 0.26, vibrato: 0, harmonic: 0.35, level: 1
        )
    ]

    private static let vocal: [InstrumentPreset] = [
        InstrumentPreset(
            id: "vocal-clear", name: "Clear Lead",
            detail: "Focused lead with a steady vibrato",
            voice: .marleneVocal, brightness: 2_600, sustain: 1, attack: 0.06,
            release: 0.26, vibrato: 0.011, harmonic: 0.07, level: 1
        ),
        InstrumentPreset(
            id: "vocal-breathy", name: "Breathy",
            detail: "Airy, intimate delivery",
            voice: .marleneVocal, brightness: 2_200, sustain: 1, attack: 0.05,
            release: 0.3, vibrato: 0.014, harmonic: 0.18, level: 0.95
        ),
        InstrumentPreset(
            id: "vocal-powerful", name: "Powerful",
            detail: "Open and loud with a quick start",
            voice: .marleneVocal, brightness: 3_200, sustain: 1, attack: 0.03,
            release: 0.22, vibrato: 0.009, harmonic: 0.04, level: 1
        ),
        InstrumentPreset(
            id: "vocal-soft", name: "Soft Vowel",
            detail: "Gentle, rounded vowel",
            voice: .marleneVocal, brightness: 1_800, sustain: 1, attack: 0.09,
            release: 0.3, vibrato: 0.008, harmonic: 0.1, level: 0.9
        )
    ]
}
