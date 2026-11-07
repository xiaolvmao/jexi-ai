//
//  JXModelCatalog.h
//  jexi-ai — which model to run, where it lives, and keeping only one loaded.
//

#import <Foundation/Foundation.h>
#import "JXUpscaler.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JXModelKind) {
    JXModelKindRealESRGAN = 0,
    JXModelKindFastSRGAN = 1,
    JXModelKindUser = 2,
};

@interface JXModelCatalog : NSObject

+ (instancetype)shared;

/// The .mlmodel the user imported, if any (it lives in Documents/UserModels).
@property (nonatomic, strong, nullable) NSURL *userModelURL;

+ (NSString *)titleForKind:(JXModelKind)kind;
+ (NSString *)oneLineForKind:(JXModelKind)kind;

/// Loads (and caches) the model for this kind.  Only one model stays in memory:
/// loading another releases the previous one, which on this device is worth
/// several hundred megabytes of ANE/GPU working set.
- (nullable JXSRModel *)modelForKind:(JXModelKind)kind error:(NSError **)error;

/// Drops every loaded model (called when the app goes to the background).
- (void)releaseModels;

/// Set while a run is in progress: releaseModels then keeps the model alive,
/// because the background notification would otherwise pull it out from under
/// a running batch.
@property (nonatomic, assign) BOOL busy;

/// Copies a picked .mlmodel/.mlpackage into the app and makes it the user model.
- (BOOL)importUserModelFromURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
