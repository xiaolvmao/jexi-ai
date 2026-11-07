//
//  JXPreviewViewController.h
//  jexi-ai
//

#import <UIKit/UIKit.h>

@interface JXPreviewViewController : UIViewController
- (instancetype)initWithResultImage:(UIImage *)result
                      originalImage:(UIImage *)original
                         properties:(NSDictionary *)properties
                          prescaled:(BOOL)prescaled;
@end
