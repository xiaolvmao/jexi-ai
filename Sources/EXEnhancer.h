#import <Foundation/Foundation.h>

/// 用 Core Image 把图片放大并锐化（Lanczos 放大 + Unsharp Mask），像素重编码，保留元数据。
@interface EXEnhancer : NSObject

/// scale 为目标倍数；长边超过 maxDimension 时自动降低倍数。
+ (BOOL)upscaleURL:(NSURL *)source
             toURL:(NSURL *)destination
             scale:(CGFloat)scale
      maxDimension:(CGFloat)maxDimension
             error:(NSError **)error;

@end
