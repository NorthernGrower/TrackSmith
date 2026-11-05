//
//  MasteringChain.swift
//  AI Music Studio
//

import AVFoundation
import AudioToolbox

/// Builds and configures the master EQ, bus compressor and limiter.
enum MasteringChainUnit {
    /// Apple's peak limiter, configured through its audio unit parameters.
    static func makeLimiter() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    /// Applies one set of mastering settings to an already connected chain.
    static func configure(
        eq: AVAudioUnitEQ,
        compressor: AVAudioUnitEffect,
        limiter: AVAudioUnitEffect,
        ceiling: AVAudioMixerNode,
        settings: MasteringSettings
    ) {
        let bypassed = settings.isBypassed

        applyEQ(eq, settings: settings.eq, bypassed: bypassed)
        applyCompressor(compressor, settings: settings.compressor, bypassed: bypassed)
        applyLimiter(limiter, ceiling: ceiling, settings: settings.limiter, bypassed: bypassed)
    }

    private static func applyEQ(_ eq: AVAudioUnitEQ, settings: MasterEQSettings, bypassed: Bool) {
        eq.bypass = bypassed || settings.isBypassed
        guard eq.bands.count >= 3 else { return }

        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 120
        low.bandwidth = 1
        low.gain = Float(min(12, max(-12, settings.lowGain)))
        low.bypass = false

        let mid = eq.bands[1]
        mid.filterType = .parametric
        mid.frequency = Float(min(6_000, max(200, settings.midFrequency)))
        mid.bandwidth = 1.2
        mid.gain = Float(min(12, max(-12, settings.midGain)))
        mid.bypass = false

        let high = eq.bands[2]
        high.filterType = .highShelf
        high.frequency = 8_000
        high.bandwidth = 1
        high.gain = Float(min(12, max(-12, settings.highGain)))
        high.bypass = false
    }

    private static func applyCompressor(
        _ compressor: AVAudioUnitEffect,
        settings: MasterCompressorSettings,
        bypassed: Bool
    ) {
        var trackSettings = TrackCompressorSettings()
        trackSettings.isBypassed = bypassed || settings.isBypassed
        trackSettings.thresholdDB = min(0, max(-40, settings.thresholdDB))
        trackSettings.ratio = min(8, max(1, settings.ratio))
        trackSettings.attackMilliseconds = min(100, max(1, settings.attackMilliseconds))
        trackSettings.releaseMilliseconds = min(1_000, max(50, settings.releaseMilliseconds))
        TrackCompressorUnit.configure(compressor, settings: trackSettings)
    }

    private static func applyLimiter(
        _ limiter: AVAudioUnitEffect,
        ceiling: AVAudioMixerNode,
        settings: MasterLimiterSettings,
        bypassed: Bool
    ) {
        let isOff = bypassed || settings.isBypassed
        limiter.bypass = isOff

        let unit = limiter.audioUnit
        let drive = Float32(min(12, max(-12, settings.driveDB)))
        let release = Float32(min(0.5, max(0.02, settings.releaseMilliseconds / 1_000)))
        AudioUnitSetParameter(unit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, drive, 0)
        AudioUnitSetParameter(unit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(unit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, release, 0)

        // The peak limiter stops at 0 dBFS, so a trim after it sets the ceiling.
        let ceilingDB = min(0, max(-6, settings.ceilingDB))
        ceiling.outputVolume = isOff ? 1 : Float(pow(10, ceilingDB / 20))
    }
}

/// The peak limiter's output trim, exposed for the meters.
extension MasteringSettings {
    var ceilingLinearGain: Float {
        let db = min(0, max(-6, limiter.ceilingDB))
        return isBypassed || limiter.isBypassed ? 1 : Float(pow(10, db / 20))
    }
}
