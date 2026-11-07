//
//  JXUpscaler.h
//  jexi-ai — Core ML super-resolution core, no UIKit.
//
//  One model, one tiled pass: the model takes a fixed square BGRA image and
//  returns scale x that size.  The upscaler cuts the source into tiles with a
//  small overlap, runs them one at a time and cross-fades each tile into the
//  destination, so nothing but the destination and the current tile is alive.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const JXUpscalerErrorDomain;

typedef NS_ENUM(NSInteger, JXUpscalerError) {
    JXUpscalerErrorBadModel = 1,
    JXUpscalerErrorTileFailed = 2,
    JXUpscalerErrorCanceled = 3,
    JXUpscalerErrorBuffer = 4,
    JXUpscalerErrorTooLarge = 5,
};

/// A loaded Core ML super-resolution model.
@interface JXSRModel : NSObject

/// Compiles (MLModel.compileModelAtURL) and loads the model at url.
+ (nullable instancetype)modelWithContentsOfURL:(NSURL *)url error:(NSError **)error;

@property (nonatomic, readonly) NSInteger inputTileSize;  // square, from the image constraint
@property (nonatomic, readonly) NSInteger scale;          // output / input
@property (nonatomic, readonly, copy) NSString *inputName;
@property (nonatomic, readonly, copy) NSString *outputName;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly) NSURL *compiledURL;
/// One "nope, it is still loading" run at tile size; used by Tools.
- (BOOL)warmUpWithError:(NSError **)error;

/// Runs one tile through the model.  Returns a retained output pixel buffer or
/// NULL with *error set.
- (nullable CVPixelBufferRef)runTile:(CVPixelBufferRef)tile
                               error:(NSError **)error CF_RETURNS_RETAINED;

@end

typedef BOOL (^JXCancelBlock)(void);
/// done, total, seconds per tile so far.
typedef void (^JXProgressBlock)(NSInteger done, NSInteger total, double secondsPerTile);

@interface JXUpscaler : NSObject

- (instancetype)initWithModel:(JXSRModel *)model NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Overlap between neighbouring tiles, in OUTPUT pixels. Default 32.
@property (nonatomic, assign) NSInteger overlapPixels;
/// Output long edge cap in pixels. 0 = no cap. Default 4096.
@property (nonatomic, assign) long long maxOutputEdge;

@property (nonatomic, readonly) NSInteger totalTiles;      // filled by the last pass
@property (nonatomic, readonly) BOOL didPrescale;          // true when the cap kicked in
@property (nonatomic, readonly) CGSize outputSize;

/// Runs the whole image.  Returns a retained BGRA pixel buffer (caller
/// CVBufferRelease's it) or NULL with *error set (JXUpscalerErrorCanceled when
/// the cancel block said yes).
- (nullable CVPixelBufferRef)upscalePixelBuffer:(CVPixelBufferRef)source
                                       progress:(nullable JXProgressBlock)progress
                                       canceled:(nullable JXCancelBlock)canceled
                                          error:(NSError **)error CF_RETURNS_RETAINED;

@end

/// Creates a BGRA pixel buffer backed by an IOSurface (the layout Core ML and
/// Core Graphics both prefer for images this size).
CVPixelBufferRef _Nullable JXCreateBGRABuffer(size_t width, size_t height);

/// Copies source into a new buffer of the given size with vImage (no GPU),
/// used for the high-quality downscale that keeps a huge photo under the cap.
CVPixelBufferRef _Nullable JXRescaleBuffer(CVPixelBufferRef source, size_t width,
                                           size_t height);

NS_ASSUME_NONNULL_END
