#import "EXDevice.h"
#import <UIKit/UIKit.h>
#include <sys/sysctl.h>
#include <stdlib.h>

static NSString *EXSysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return nil;
    }
    char *buffer = calloc(1, size + 1);
    if (buffer == NULL) {
        return nil;
    }
    NSString *result = nil;
    if (sysctlbyname(name, buffer, &size, NULL, 0) == 0) {
        result = [NSString stringWithUTF8String:buffer];
    }
    free(buffer);
    return result;
}

@implementation EXDevice

+ (NSString *)machineIdentifier {
    NSString *machine = EXSysctlString("hw.machine");
    return machine.length > 0 ? machine : @"iPhone";
}

+ (NSString *)marketingName {
    static NSDictionary<NSString *, NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"iPhone16,1": @"iPhone 15 Pro",
            @"iPhone16,2": @"iPhone 15 Pro Max",
            @"iPhone15,4": @"iPhone 15",
            @"iPhone15,5": @"iPhone 15 Plus",
            @"iPhone15,2": @"iPhone 14 Pro",
            @"iPhone15,3": @"iPhone 14 Pro Max",
            @"iPhone14,7": @"iPhone 14",
            @"iPhone14,8": @"iPhone 14 Plus",
            @"iPhone14,2": @"iPhone 13 Pro",
            @"iPhone14,3": @"iPhone 13 Pro Max",
            @"iPhone14,4": @"iPhone 13 mini",
            @"iPhone14,5": @"iPhone 13",
            @"iPhone13,1": @"iPhone 12 mini",
            @"iPhone13,2": @"iPhone 12",
            @"iPhone13,3": @"iPhone 12 Pro",
            @"iPhone13,4": @"iPhone 12 Pro Max",
            @"iPhone12,1": @"iPhone 11",
            @"iPhone12,3": @"iPhone 11 Pro",
            @"iPhone12,5": @"iPhone 11 Pro Max",
            @"iPhone12,8": @"iPhone SE (2nd generation)",
            @"iPhone17,1": @"iPhone 16 Pro",
            @"iPhone17,2": @"iPhone 16 Pro Max",
            @"iPhone17,3": @"iPhone 16",
            @"iPhone17,4": @"iPhone 16 Plus",
            @"iPad13,4": @"iPad Pro 11-inch (3rd generation)",
            @"iPad13,8": @"iPad Pro 12.9-inch (5th generation)",
        };
    });
    NSString *machine = [self machineIdentifier];
    NSString *name = names[machine];
    return name.length > 0 ? name : machine;
}

+ (NSString *)osBuild {
    NSString *build = EXSysctlString("kern.osversion");
    return build.length > 0 ? build : @"";
}

+ (NSString *)systemDescription {
    NSString *version = [UIDevice currentDevice].systemVersion;
    NSString *build = [self osBuild];
    if (build.length > 0) {
        return [NSString stringWithFormat:@"iOS %@ (%@)", version, build];
    }
    return [NSString stringWithFormat:@"iOS %@", version];
}

+ (NSDictionary<NSString *, id> *)cameraInfo {
    static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @{
            @"iPhone16,1": @{@"lens": @"iPhone 15 Pro back triple camera 6.765mm f/1.78",
                             @"focal": @6.765, @"focal35": @24, @"fnumber": @1.78},
            @"iPhone16,2": @{@"lens": @"iPhone 15 Pro Max back triple camera 6.765mm f/1.78",
                             @"focal": @6.765, @"focal35": @24, @"fnumber": @1.78},
            @"iPhone15,4": @{@"lens": @"iPhone 15 back dual wide camera 5.96mm f/1.6",
                             @"focal": @5.96, @"focal35": @26, @"fnumber": @1.6},
            @"iPhone15,5": @{@"lens": @"iPhone 15 Plus back dual wide camera 5.96mm f/1.6",
                             @"focal": @5.96, @"focal35": @26, @"fnumber": @1.6},
            @"iPhone15,2": @{@"lens": @"iPhone 14 Pro back triple camera 6.86mm f/1.78",
                             @"focal": @6.86, @"focal35": @24, @"fnumber": @1.78},
            @"iPhone15,3": @{@"lens": @"iPhone 14 Pro Max back triple camera 6.86mm f/1.78",
                             @"focal": @6.86, @"focal35": @24, @"fnumber": @1.78},
            @"iPhone14,5": @{@"lens": @"iPhone 13 back dual wide camera 5.7mm f/1.6",
                             @"focal": @5.7, @"focal35": @26, @"fnumber": @1.6},
        };
    });
    NSString *machine = [self machineIdentifier];
    NSDictionary *info = table[machine];
    if (info != nil) {
        return info;
    }
    return @{@"lens": [NSString stringWithFormat:@"%@ back camera", [self marketingName]],
             @"focal": @4.25, @"focal35": @26, @"fnumber": @1.8};
}

+ (NSString *)offsetStringForDate:(NSDate *)date {
    NSInteger seconds = [[NSTimeZone localTimeZone] secondsFromGMTForDate:date ?: [NSDate date]];
    NSInteger minutes = labs(seconds) / 60;
    return [NSString stringWithFormat:@"%c%02ld:%02ld",
            seconds < 0 ? '-' : '+', (long)(minutes / 60), (long)(minutes % 60)];
}

@end
