//
//  JXMetaViewController.h
//  jexi-ai — 从 jexi 迁移过来的批量功能：写入真实设备信息、时间、定位，
//  换格式、改文件名、Lanczos 放大锐化。
//

#import <UIKit/UIKit.h>

@interface JXMetaViewController : UIViewController

/// URLs of the picked photos, already copied into the app's temp folder.
- (instancetype)initWithFileURLs:(NSArray<NSURL *> *)urls NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end
