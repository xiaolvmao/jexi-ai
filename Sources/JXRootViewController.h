//
//  JXRootViewController.h
//  jexi-ai — 第二页：模型、超分、进度。照片由第一页传进来。
//

#import <UIKit/UIKit.h>

@interface JXRootViewController : UIViewController

- (instancetype)initWithImageData:(NSData *)data
                       properties:(NSDictionary *)properties
                          preview:(UIImage *)preview NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end
