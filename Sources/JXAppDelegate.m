//
//  JXAppDelegate.m
//  jexi-ai
//

#import "JXAppDelegate.h"
#import "JXPickViewController.h"
#import "JXModelCatalog.h"

@implementation JXAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    JXPickViewController *root = [JXPickViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName : [UIColor whiteColor]};
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Core ML keeps a large ANE/GPU working set per loaded model; give it back
    // while the app is not on screen.
    [[JXModelCatalog shared] releaseModels];
}

@end
