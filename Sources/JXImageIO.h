//
//  JXImageIO.h
//  jexi-ai — photo data in, BGRA buffers and library saves out.
//

#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Decodes image data (JPEG/HEIC/PNG, any EXIF orientation) into an upright
/// BGRA pixel buffer.  outPreview, when given, receives the same picture as a
/// UIImage for the screen.  Caller releases the buffer.
CVPixelBufferRef _Nullable JXCreatePixelBufferFromImageData(NSData *data,
                                                            UIImage *_Nullable *_Nullable outPreview,
                                                            NSError *_Nullable *_Nullable error)
    CF_RETURNS_RETAINED;

/// BGRA pixel buffer -> UIImage (copies the pixels).
UIImage *_Nullable JXImageFromPixelBuffer(CVPixelBufferRef buffer);

/// The image properties (EXIF/TIFF/GPS) of the original file, kept so the saved
/// result carries the same time, camera and location.
NSDictionary *_Nullable JXImagePropertiesFromData(NSData *data);

/// Writes the picture as a JPEG that keeps the original's metadata but drops the
/// orientation flag (the pixels are already upright) and states the new size,
/// then adds it to the photo library as a NEW asset.  Requests add-only access
/// first; completion runs on the main queue.
void JXSaveImageToPhotoLibrary(UIImage *image,
                               NSDictionary *_Nullable originalProperties,
                               void (^completion)(BOOL ok, NSError *_Nullable error));

NS_ASSUME_NONNULL_END
