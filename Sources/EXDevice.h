#import <Foundation/Foundation.h>

/// 设备上真实可读的数据，供 EXIF 写入使用。
@interface EXDevice : NSObject

/// 例如 iPhone16,1
+ (NSString *)machineIdentifier;
/// 例如 iPhone 15 Pro（未知机型时回落到 machineIdentifier）
+ (NSString *)marketingName;
/// 例如 iOS 17.0 (21A329)
+ (NSString *)systemDescription;
/// 例如 21A329
+ (NSString *)osBuild;
/// 该机型的后置主摄参数：lens / focal / focal35 / fnumber
+ (NSDictionary<NSString *, id> *)cameraInfo;
/// 当前时区相对 UTC 的偏移，例如 +08:00
+ (NSString *)offsetStringForDate:(NSDate *)date;

@end
