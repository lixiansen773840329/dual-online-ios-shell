#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@end

@implementation AppDelegate

static NSDictionary *LoadRuntimeConfig(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-config" ofType:@"json" inDirectory:@"www"];
    if (!path) {
        path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www/runtime-config.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSString *DeviceId(void) {
    NSString *key = @"insulation_device_id";
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *existing = [ud stringForKey:key];
    if (existing.length) return existing;
    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"unknown";
    vendor = [[vendor stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    NSString *uuid = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    if (uuid.length > 12) uuid = [uuid substringToIndex:12];
    NSString *deviceId = [NSString stringWithFormat:@"i_%@_%@", vendor, uuid];
    [ud setObject:deviceId forKey:key];
    return deviceId;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.01 blue:0.01 alpha:1];

    NSDictionary *cfg = LoadRuntimeConfig();
    NSString *entry = cfg[@"assets_entry"] ?: @"baowen/shell.html";
    NSString *insApi = cfg[@"insulation_api_base"] ?: cfg[@"server_base"] ?: @"";
    NSString *gtApi = cfg[@"gongtian_api_base"] ?: cfg[@"server_base"] ?: @"";
    NSString *deviceId = DeviceId();

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
    if (@available(iOS 14.0, *)) {
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }
    NSString *flags = [NSString stringWithFormat:
        @"window.__INSULATION_APP__=true;"
        @"window.__INSULATION_DEVICE_ID__=%@;"
        @"window.__INSULATION_API_BASE__=%@;"
        @"window.__GONGTIAN_API_BASE__=%@;",
        [self jsonString:deviceId],
        [self jsonString:insApi],
        [self jsonString:gtApi]];
    WKUserScript *flagScript = [[WKUserScript alloc] initWithSource:flags
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:NO];
    [config.userContentController addUserScript:flagScript];
    [config.userContentController addScriptMessageHandler:self name:@"InsulationNativeBridge"];

    self.webView = [[WKWebView alloc] initWithFrame:vc.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    [vc.view addSubview:self.webView];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    NSString *wwwDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
    NSString *pagePath = [wwwDir stringByAppendingPathComponent:entry];
    if (![[NSFileManager defaultManager] fileExistsAtPath:pagePath]) {
        pagePath = [wwwDir stringByAppendingPathComponent:@"index.html"];
    }
    NSURL *page = [NSURL fileURLWithPath:pagePath];
    NSURL *root = [NSURL fileURLWithPath:wwwDir isDirectory:YES];
    [self.webView loadFileURL:page allowingReadAccessToURL:root];
    return YES;
}

- (NSString *)jsonString:(NSString *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(value ?: @"") options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"\"";
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    // 最小壳：收到 JS 桥消息不崩溃即可；完整桥接需 Swift DualOnline
    (void)userContentController;
    (void)message;
}

- (void)webView:(WKWebView *)webView
runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    completionHandler(defaultText ?: @"");
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
