#import "ARAppNotificationsDelegate.h"
#import "ARAnalyticsConstants.h"
#import "UIApplicationStateEnum.h"
#import "ARNotificationView.h"
#import <ARAnalytics/ARAnalytics.h>

@implementation ARAppNotificationsDelegate

+ (void)load
{
    [JSDecoupledAppDelegate sharedAppDelegate].remoteNotificationsDelegate = [[self alloc] init];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
#if (TARGET_IPHONE_SIMULATOR == 0)
    ARErrorLog(@"Error registering for remote notifications: %@", error.localizedDescription);
#endif
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceTokenData
{
    // http://stackoverflow.com/questions/9372815/how-can-i-convert-my-device-token-nsdata-into-an-nsstring
    const unsigned *tokenBytes = [deviceTokenData bytes];
    NSString *deviceToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                                ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                                ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                                ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

    ARActionLog(@"Got device notification token: %@", deviceToken);

    [ARAnalytics setUserProperty:ARAnalyticsEnabledNotificationsProperty toValue:@"true"];

    if (![[NSUserDefaults standardUserDefaults] boolForKey:ARHasSubmittedDeviceTokenDefault]) {
        [ArtsyAPI setAPNTokenForCurrentDevice:deviceToken success:^(id response) {
            ARActionLog(@"Pushed device token to Artsy's servers");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ARHasSubmittedDeviceTokenDefault];
        } failure:^(NSError *error) {
            ARErrorLog(@"Couldn't push the device token to Artsy, error: %@", error.localizedDescription);
        }];
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    UIApplication *app = [UIApplication sharedApplication];
    NSString *uiApplicationState = [UIApplicationStateEnum toString:app.applicationState];

    ARActionLog(@"Incoming notification in the %@ application state: %@", uiApplicationState, userInfo);

    NSMutableDictionary *notificationInfo = [[NSMutableDictionary alloc] initWithDictionary:userInfo];
    [notificationInfo setObject:uiApplicationState forKey:@"UIApplicationState"];
    [ARAnalytics event:ARAnalyticsNotificationReceived withProperties:notificationInfo];

    NSString *message = [[userInfo objectForKey:@"aps"] objectForKey:@"alert"];
    NSString *url = userInfo[@"url"];

    if (!message) {
        message = url;
    }

    if (app.applicationState == UIApplicationStateActive && message) {
        // app is in the foreground
        [ARNotificationView showNoticeInView:[self findVisibleWindow]
            title:message
            hideAfter:0
            response: ^{
                if (url) {
                    [ARAnalytics event:ARAnalyticsNotificationTapped withProperties:notificationInfo];

                    UIViewController *viewController = [ARSwitchBoard.sharedInstance loadPath:url];
                    if (viewController) {
                        [[ARTopMenuViewController sharedController] pushViewController:viewController];
                    }
                }
            }
        ];
    } else {
        // app was brought from the background after a user clicked on the notification
        [ARAnalytics event:ARAnalyticsNotificationTapped withProperties:notificationInfo];
        if (url) {
            UIViewController *viewController = [ARSwitchBoard.sharedInstance loadPath:url];

            if (viewController) {
                [[ARTopMenuViewController sharedController] pushViewController:viewController];
            }
        }
    }
}

-(void)registerForDeviceNotificationsOnce
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIUserNotificationType allTypes = (UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert);
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:allTypes categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    });
}

- (UIWindow *)findVisibleWindow {
    NSArray *windows = [[UIApplication sharedApplication] windows];
    for (UIWindow *window in [windows reverseObjectEnumerator]) {
        if (!window.hidden) {
            return window;
        }
    }
    return NULL;
}

@end
