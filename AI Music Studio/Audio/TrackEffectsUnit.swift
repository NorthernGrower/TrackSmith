//
//  TrackEffectsUnit.swift
//  AI Music Studio
//

import AVFoundation

/// Configures the per-track effects shared by live playback and offline renders.
enum TrackEffectsUnit {
    static func makeDistortion() -> AVAudioUnitDistortion {
        let unit = AVAudioUnitDistortion()
        unit.loadFactoryPreset(.multiDistortedFunk)
        return unit
    }

    static func configure(
        chorus: AVAudioUnitDelay,
        distortion: AVAudioUnitDistortion,
        stereoDelay: AVAudioUnitDelay,
        settings: TrackEffectsRack,
        tempoBPM: Int,
        time: TimeInterval = 0,
        isFrozen: Bool = false
    ) {
        updateChorusDelay(chorus, settings: settings.chorus, time: time, isFrozen: isFrozen)
        chorus.feedback = 0
        chorus.wetDryMix = isFrozen || settings.chorus.isBypassed
            ? 0
            : Float(min(1, max(0, settings.chorus.mix)) * 100)

        distortion.preGain = Float(min(20, max(0, settings.distortion.driveDB)))
        distortion.wetDryMix = isFrozen || settings.distortion.isBypassed
            ? 0
            : Float(min(1, max(0, settings.distortion.mix)) * 100)
        distortion.bypass = isFrozen || settings.distortion.isBypassed

        updateStereoDelayTime(stereoDelay, settings: settings.stereoDelay, tempoBPM: tempoBPM)
        stereoDelay.feedback = isFrozen || settings.stereoDelay.isBypassed
            ? 0
            : Float(min(0.9, max(0, settings.stereoDelay.feedback)) * 100)
        stereoDelay.wetDryMix = isFrozen || settings.stereoDelay.isBypassed
            ? 0
            : Float(min(1, max(0, settings.stereoDelay.mix)) * 100)
    }

    static func updateChorusDelay(
        _ unit: AVAudioUnitDelay,
        settings: TrackChorusSettings,
        time: TimeInterval,
        isFrozen: Bool = false
    ) {
        let depth = min(0.012, max(0, settings.depthMilliseconds / 1_000))
        let rate = min(5, max(0.1, settings.rateHz))
        let modulation = sin(2 * Double.pi * rate * max(0, time))
        unit.delayTime = min(0.04, max(0.005, 0.02 + depth * modulation))
        unit.feedback = 0
        unit.wetDryMix = isFrozen || settings.isBypassed
            ? 0
            : Float(min(1, max(0, settings.mix)) * 100)
    }

    static func updateStereoDelayTime(
        _ unit: AVAudioUnitDelay,
        settings: TrackStereoDelaySettings,
        tempoBPM: Int
    ) {
        unit.delayTime = min(2, max(0.01, settings.timeBeats * 60 / Double(max(60, tempoBPM))))
    }

    static func tailDuration(settings: TrackEffectsRack, tempoBPM: Int, isFrozen: Bool = false) -> TimeInterval {
        guard !isFrozen else { return 0 }
        var tail: TimeInterval = 0
        if !settings.chorus.isBypassed, settings.chorus.mix > 0 {
            tail = max(tail, 0.04)
        }
        if !settings.stereoDelay.isBypassed, settings.stereoDelay.mix > 0 {
            let delayTime = min(2, max(0.01, settings.stereoDelay.timeBeats * 60 / Double(max(60, tempoBPM))))
            let feedback = min(0.9, max(0, settings.stereoDelay.feedback))
            let repeats = feedback > 0 ? max(1, ceil(log(0.001) / log(feedback))) : 1
            tail = max(tail, min(8, delayTime * repeats))
        }
        return tail
    }
}
