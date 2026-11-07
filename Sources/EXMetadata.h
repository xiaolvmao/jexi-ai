#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

typedef NS_OPTIONS(NSUInteger, EXWriteOptions) {
    EXWriteNone     = 0,
    EXWriteDevice   = 1 << 0,   // 机型、系统、镜头、曝光参数
    EXWriteTime     = 1 << 1,   // 当前时间与时区
    EXWriteLocation = 1 << 2,   // 真实定位（关闭时抹掉原有位置信息）
};

typedef NS_ENUM(NSInteger, EXOutputFormat) {
    EXOutputFormatKeep = 0,     // 保持原格式
    EXOutputFormatJPEG = 1,
    EXOutputFormatHEIF = 2,
};

/// 读写照片的 EXIF / TIFF / GPS 元数据，像素数据原样保留。
@interface EXMetadata : NSObject

/// 读取元数据（原始字典）
+ (NSDictionary *)propertiesAtURL:(NSURL *)url;

/// 将元数据摊平成展示行：@{@"section": @"EXIF", @"key": @"DateTimeOriginal", @"value": @"…"}
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)rowsFromProperties:(NSDictionary *)properties;

/// 主要信息摘要（拍摄时间 / 设备 / 位置…），没有的项不返回
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)summaryRowsFromProperties:(NSDictionary *)properties;

/// 把 src 的像素原样写出到 dst，同时按 options 重写元数据。
/// format 与源格式不同时重新编码为目标格式（HEIF/JPEG）。
+ (BOOL)writeSourceURL:(NSURL *)src
          toDestination:(NSURL *)dst
                options:(EXWriteOptions)options
               location:(CLLocation *)location
                   date:(NSDate *)date
                 format:(EXOutputFormat)format
                  error:(NSError **)error;

@end
