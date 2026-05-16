#import "EpicenterDSPBridge.h"
#include "EpicenterDSPCore.hpp"

@implementation EpicenterDSPBridge {
    EpicenterDSPCore _core;
}

- (void)reset {
    _core.reset();
}

@end
