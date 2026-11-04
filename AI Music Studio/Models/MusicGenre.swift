//
//  MusicGenre.swift
//  AI Music Studio
//

import Foundation

/// One chord of a genre's progression: a semitone offset from the key root
/// and the intervals that build the chord above it.
struct GenreChord {
    let rootOffset: Int
    let intervals: [Int]
}

/// A one-bar drum groove written as 16th-note steps per voice.
struct GenreGroove {
    let kick: [Int]
    let snare: [Int]
    let closedHat: [Int]
    let openHat: [Int]
    let clap: [Int]
}

/// The rhyming building blocks a genre's lyrics are written from.
struct GenreLyrics {
    let openings: [String]
    let couplets: [(String, String)]
    let hooks: [String]
    let bridges: [String]
    let imagery: String
}

/// The musical and lyrical character of one genre.
enum MusicGenre: String, CaseIterable, Identifiable {
    case pop
    case hipHop
    case rock
    case rnb
    case country
    case electronic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pop: return "Pop"
        case .hipHop: return "Hip-Hop"
        case .rock: return "Rock"
        case .rnb: return "R&B"
        case .country: return "Country"
        case .electronic: return "Electronic"
        }
    }

    var tagline: String {
        switch self {
        case .pop: return "Bright hooks, wide chorus"
        case .hipHop: return "Half-time drums, deep low end"
        case .rock: return "Driven guitars, live kit"
        case .rnb: return "Slow grooves, warm keys"
        case .country: return "Storytelling, plucked strings"
        case .electronic: return "Four on the floor, neon synths"
        }
    }

    var systemImage: String {
        switch self {
        case .pop: return "sparkles"
        case .hipHop: return "waveform.path"
        case .rock: return "bolt.fill"
        case .rnb: return "moon.stars.fill"
        case .country: return "sun.horizon.fill"
        case .electronic: return "circle.hexagongrid.fill"
        }
    }

    var defaultTempo: Int {
        switch self {
        case .pop: return 118
        case .hipHop: return 92
        case .rock: return 138
        case .rnb: return 84
        case .country: return 104
        case .electronic: return 126
        }
    }

    var tempoRange: ClosedRange<Int> {
        switch self {
        case .pop: return 100...132
        case .hipHop: return 76...104
        case .rock: return 110...158
        case .rnb: return 68...96
        case .country: return 88...126
        case .electronic: return 112...134
        }
    }

    var defaultKit: DrumKit {
        switch self {
        case .pop: return .studio808
        case .hipHop: return .trap
        case .rock: return .acoustic
        case .rnb: return .studio808
        case .country: return .acoustic
        case .electronic: return .electro
        }
    }

    var defaultGuitar: GuitarStyle {
        switch self {
        case .pop: return .cleanElectric
        case .hipHop: return .none
        case .rock: return .overdriven
        case .rnb: return .cleanElectric
        case .country: return .acoustic
        case .electronic: return .cleanElectric
        }
    }

    var bassVoice: TrackVoiceKind {
        switch self {
        case .electronic, .hipHop: return .synth
        case .rock, .pop, .rnb: return .bassGuitar
        case .country: return .bassGuitar
        }
    }

    var keysVoice: TrackVoiceKind? {
        switch self {
        case .rnb, .pop, .electronic: return .synth
        case .hipHop: return .synth
        case .rock: return nil
        case .country: return nil
        }
    }

    var chords: [GenreChord] {
        switch self {
        case .pop:
            return [
                GenreChord(rootOffset: 0, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 7, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 9, intervals: [0, 3, 7]),
                GenreChord(rootOffset: 5, intervals: [0, 4, 7]),
            ]
        case .hipHop:
            return [
                GenreChord(rootOffset: 0, intervals: [0, 3, 7]),
                GenreChord(rootOffset: 8, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 3, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 10, intervals: [0, 4, 7]),
            ]
        case .rock:
            return [
                GenreChord(rootOffset: 0, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 10, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 5, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 0, intervals: [0, 4, 7]),
            ]
        case .rnb:
            return [
                GenreChord(rootOffset: 2, intervals: [0, 3, 7, 10]),
                GenreChord(rootOffset: 7, intervals: [0, 4, 7, 10]),
                GenreChord(rootOffset: 0, intervals: [0, 4, 7, 11]),
                GenreChord(rootOffset: 9, intervals: [0, 3, 7, 10]),
            ]
        case .country:
            return [
                GenreChord(rootOffset: 0, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 5, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 7, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 0, intervals: [0, 4, 7]),
            ]
        case .electronic:
            return [
                GenreChord(rootOffset: 0, intervals: [0, 3, 7]),
                GenreChord(rootOffset: 10, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 8, intervals: [0, 4, 7]),
                GenreChord(rootOffset: 10, intervals: [0, 4, 7]),
            ]
        }
    }

    var groove: GenreGroove {
        switch self {
        case .pop:
            return GenreGroove(
                kick: [0, 8],
                snare: [4, 12],
                closedHat: [0, 2, 4, 6, 8, 10, 12],
                openHat: [14],
                clap: [12]
            )
        case .hipHop:
            return GenreGroove(
                kick: [0, 3, 8, 11],
                snare: [4, 12],
                closedHat: [0, 2, 4, 6, 8, 10, 12, 14],
                openHat: [],
                clap: [4, 12]
            )
        case .rock:
            return GenreGroove(
                kick: [0, 6, 8, 14],
                snare: [4, 12],
                closedHat: [0, 2, 4, 6, 8, 10, 12, 14],
                openHat: [10],
                clap: []
            )
        case .rnb:
            return GenreGroove(
                kick: [0, 7, 10],
                snare: [4, 12],
                closedHat: [0, 2, 4, 6, 8, 10, 12, 14],
                openHat: [],
                clap: [12]
            )
        case .country:
            return GenreGroove(
                kick: [0, 8],
                snare: [4, 12],
                closedHat: [0, 2, 4, 6, 8, 10, 12, 14],
                openHat: [],
                clap: [12]
            )
        case .electronic:
            return GenreGroove(
                kick: [0, 4, 8, 12],
                snare: [],
                closedHat: [0, 4, 8, 12],
                openHat: [2, 6, 10, 14],
                clap: [4, 12]
            )
        }
    }

    var lyrics: GenreLyrics {
        switch self {
        case .pop:
            return GenreLyrics(
                openings: [
                    "I woke up with your name on the window",
                    "Streetlights were humming a tune we knew",
                    "There's a version of me that still waits by the door",
                ],
                couplets: [
                    ("We were running through the {topic} light", "Holding on to what felt right"),
                    ("Every little thing you said to me", "Turned into a melody"),
                    ("I don't need a map to find your road", "I just follow what my heart has known"),
                    ("Say it once and say it slow", "Tell me everything I need to know"),
                    ("We can take the long way home tonight", "Chase the quiet till it turns to light"),
                ],
                hooks: [
                    "So turn it up, we're not going home",
                    "This is the sound of letting go",
                    "Hold me in the {topic} light",
                ],
                bridges: [
                    "And if the whole world goes quiet",
                    "I'll be the echo in your chest",
                ],
                imagery: "neon"
            )
        case .hipHop:
            return GenreLyrics(
                openings: [
                    "Yeah, woke up with a plan and a pocket of dreams",
                    "They talk loud but the work stays quiet",
                    "City on my shoulders, beat in my chest",
                ],
                couplets: [
                    ("Built this from the bottom, no handouts, no lies", "Now the whole block sees it when I rise"),
                    ("Keep the circle small and the vision wide", "Every scar on my story is a badge of pride"),
                    ("Slow steps, long nights, still I move", "Nothing left to prove, only room to improve"),
                    ("They want the highlight, not the grind", "I put the hours in and rewired my mind"),
                    ("Count the wins like a drum on the {topic} floor", "Then go back and go get a little more"),
                ],
                hooks: [
                    "Hands up if you're still on your way",
                    "We don't fold, we reload",
                    "Made of the nights they said we'd never make",
                ],
                bridges: [
                    "If you're counting me out, count again",
                    "Same kid, bigger room, same hunger",
                ],
                imagery: "concrete"
            )
        case .rock:
            return GenreLyrics(
                openings: [
                    "The amps are warm and the door's wide open",
                    "I broke the lock on the quiet in my head",
                    "There's a storm in the wiring tonight",
                ],
                couplets: [
                    ("We were louder than the doubt in the room", "Burned the dark down, let it bloom"),
                    ("Every scar is a song I survived", "Every wrong turn kept the fire alive"),
                    ("Scream it out till the rafters shake", "We are the noise that the silence can't take"),
                    ("Give me the {topic} and a reason to run", "I'll take the long road into the sun"),
                    ("No retreat and no regret", "Just the echo of the things we said"),
                ],
                hooks: [
                    "Turn it up until it hurts",
                    "We were built for the burn",
                    "Raise your voice, the night is ours",
                ],
                bridges: [
                    "And when the feedback fades away",
                    "I'll still be standing in the sound",
                ],
                imagery: "thunder"
            )
        case .rnb:
            return GenreLyrics(
                openings: [
                    "Two in the morning and the city's asleep",
                    "Your voice on the line like a slow perfume",
                    "I keep the lights low so the truth can talk",
                ],
                couplets: [
                    ("Tell me what you need and I'll make the room slow", "We can let the rest of the world go"),
                    ("Every little touch is a promise I keep", "Every quiet word puts the noise to sleep"),
                    ("I don't rush the moment, I let it breathe", "You're the only place I want to be"),
                    ("Pour a little patience in the glass", "Let the good things take their time to last"),
                    ("In the {topic} I can feel you near", "Everything I needed shows up here"),
                ],
                hooks: [
                    "Stay a little longer tonight",
                    "You're the only song I know by heart",
                    "Slow down, let it feel like this",
                ],
                bridges: [
                    "And if the morning comes too soon",
                    "I'll keep the chorus on repeat for you",
                ],
                imagery: "velvet"
            )
        case .country:
            return GenreLyrics(
                openings: [
                    "Dirt on the dashboard, sun going down",
                    "Grandpa's radio still knows the way",
                    "There's a porch light burning two miles from town",
                ],
                couplets: [
                    ("Down a gravel road where the {topic} runs wide", "That's where I left my worries behind"),
                    ("Mama used to say that the heart knows best", "Follow it slow and let the rest of it rest"),
                    ("Hometown sky with the stars hung low", "Some things change and some just don't go"),
                    ("We'd sing along to a broken AM dial", "Made a little heaven out of every mile"),
                    ("When the work week ends and the screen door slams", "I'm a better man than the man I am"),
                ],
                hooks: [
                    "Take me home where the road runs out",
                    "A little bit of dirt and a whole lot of heart",
                    "That old song still gets me there",
                ],
                bridges: [
                    "And when the fields go quiet and gold",
                    "I'll still be singing what the years told",
                ],
                imagery: "porch"
            )
        case .electronic:
            return GenreLyrics(
                openings: [
                    "Lights down, city breathing slow",
                    "Somewhere between the kick and the dawn",
                    "Hands in the air like we own the night",
                ],
                couplets: [
                    ("Feel the bassline running through your spine", "Lose the clock, lose the line"),
                    ("We don't sleep, we just move", "Every heartbeat locks into the groove"),
                    ("Neon bleeding into the {topic}", "Keep it going till it's all we see"),
                    ("One more hour, one more track", "No looking forward, no looking back"),
                    ("Let the filter open like a door", "Nothing's heavy when you're on the floor"),
                ],
                hooks: [
                    "Move till the morning finds you",
                    "We are the pulse of the night",
                    "Keep it going, keep it loud",
                ],
                bridges: [
                    "And when the sun comes up on the floor",
                    "We'll still be asking for one more",
                ],
                imagery: "neon"
            )
        }
    }
}
