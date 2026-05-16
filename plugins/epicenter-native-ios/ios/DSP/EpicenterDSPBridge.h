#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EpicenterDSPBridge : NSObject
- (void)prepareWithSampleRate:(double)sampleRate channelCount:(NSInteger)channelCount maxFrames:(NSInteger)maxFrames;
- (void)reset;
- (void)setEnabled:(BOOL)enabled;
- (void)setIntensity:(float)intensity sweepFreq:(float)sweepFreq width:(float)width balance:(float)balance volume:(float)volume;
- (void)processLeft:(float *)left right:(nullable float *)right frameCount:(NSInteger)frameCount;
- (NSDictionary<NSString *, id> *)stateDictionary;
@end

NS_ASSUME_NONNULL_END
