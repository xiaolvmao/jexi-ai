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

/// A filename in the camera's own style: IMG_0001.JPG, one past the highest
/// IMG_ number already in DCIM.  offset lets a batch continue the sequence.
/// Falls back to IMG_0001 when DCIM cannot be read.
NSString *JXCameraStyleFilename(NSString *ext, NSUInteger offset);

/// Appends one line to /var/mobile/jexi-ai-debug.log (the app runs without a
/// sandbox, so a fixed path is easy to read from a shell afterwards).
void JXNote(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Writes the picture as a JPEG that keeps the original's metadata but drops the
/// orientation flag (the pixels are already upright) and states the new size,
/// then adds it to the photo library as a NEW asset.  Requests add-only access
/// first; completion runs on the main queue.
void JXSaveImageToPhotoLibrary(UIImage *image,
                               NSDictionary *_Nullable originalProperties,
                               void (^completion)(BOOL ok, NSError *_Nullable error));

/// Adds an already written file (JPEG or HEIF) to the photo library as a new
/// asset, with this filename.  Asks for add-only access first; completion runs
/// on the main queue.
void JXSaveFileToPhotoLibrary(NSURL *fileURL,
                              NSString *_Nullable filename,
                              void (^completion)(BOOL ok, NSError *_Nullable error));

NS_ASSUME_NONNULL_END
