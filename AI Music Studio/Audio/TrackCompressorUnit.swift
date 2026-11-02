//
//  TrackCompressorUnit.swift
//  AI Music Studio
//

import AVFoundation
import AudioToolbox

/// Configures Apple's on-device Dynamics Processor for one track.
enum TrackCompressorUnit {
    static func make() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    static func configure(_ unit: AVAudioUnitEffect, settings: TrackCompressorSettings) {
        let audioUnit = unit.audioUnit
        let threshold = Float32(settings.thresholdDB)
        let inputRangeAboveThreshold = 20 - settings.thresholdDB
        // The system Dynamics Processor derives its compression slope from headroom.
        let headRoom = Float32(min(40, max(0.1, inputRangeAboveThreshold / max(1, settings.ratio))))
        let attack = Float32(settings.attackMilliseconds / 1_000)
        let release = Float32(settings.releaseMilliseconds / 1_000)

        AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, threshold, 0)
        AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, headRoom, 0)
        AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
        AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, attack, 0)
        AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, release, 0)
        unit.bypass = settings.isBypassed
    }
}
