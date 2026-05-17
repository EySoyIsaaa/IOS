#import "EpicenterDSPBridge.h"
#import "EpicenterDSPCore.hpp"

@implementation EpicenterDSPBridge {
    epicenter::EpicenterDSPCore _core;
}

- (void)prepareWithSampleRate:(double)sampleRate channelCount:(NSInteger)channelCount maxFrames:(NSInteger)maxFrames {
    _core.prepare(sampleRate, (int)channelCount, (std::size_t)MAX(128, maxFrames));
}

- (void)reset {
    _core.reset();
}

- (void)setEnabled:(BOOL)enabled {
    _core.setEnabled(enabled);
}

- (void)setIntensity:(float)intensity sweepFreq:(float)sweepFreq width:(float)width balance:(float)balance volume:(float)volume {
    _core.setParameters(intensity, sweepFreq, width, balance, volume);
}

- (void)processLeft:(float *)left right:(nullable float *)right frameCount:(NSInteger)frameCount {
    if (left == nil || frameCount <= 0) { return; }
    float *channels[2] = { left, right != nil ? right : left };
    _core.process(channels, right != nil ? 2 : 1, (std::size_t)frameCount);
}

- (NSDictionary<NSString *, id> *)stateDictionary {
    const auto params = _core.parameters();
    return @{
        @"enabled": @(params.enabled),
        @"intensity": @(params.intensity),
        @"sweepFreq": @(params.sweepFreq),
        @"width": @(params.width),
        @"balance": @(params.balance),
        @"volume": @(params.volume)
    };
}

- (NSDictionary<NSString *, id> *)calibrationDictionary {
    const auto calibration = _core.calibration();
    return @{
        @"subDepth": @(calibration.subDepth),
        @"deepExtensionAmount": @(calibration.deepExtensionAmount),
        @"synthDepthGain": @(calibration.synthDepthGain),
        @"gateDetectorFloor": @(calibration.gateDetectorFloor),
        @"gateDetectorAuthority": @(calibration.gateDetectorAuthority),
        @"outputDcHighpassHz": @(calibration.outputDcHighpassHz),
        @"deepExtensionSubsonicHighpassHz": @(calibration.deepExtensionSubsonicHighpassHz),
        @"deepExtensionMixBase": @(calibration.deepExtensionMixBase),
        @"deepExtensionMixVoice": @(calibration.deepExtensionMixVoice)
    };
}

@end
