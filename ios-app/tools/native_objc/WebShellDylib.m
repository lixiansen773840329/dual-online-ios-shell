#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

/**
 * 注入到「已验证可签可开」的游戏主程序中：
 * 不替换 mt3，仅在启动后盖一层全屏 WKWebView 加载 www。
 */

static NSDictionary *WSLoadConfig(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-config" ofType:@"json" inDirectory:@"www"];
    if (!path) {
        path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www/runtime-config.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSString *WSJSONString(NSString *value) {
    NSString *raw = value ?: @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[raw] options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *arr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arr.length >= 2) {
        return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
    }
    return @"\"\"";
}

static NSString *WSDeviceId(void) {
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

@interface WSOverlayController : UIViewController <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation WSOverlayController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.01 blue:0.01 alpha:1];
    NSDictionary *cfg = WSLoadConfig();
    NSString *entry = cfg[@"assets_entry"] ?: @"baowen/shell.html";
    NSString *insApi = cfg[@"insulation_api_base"] ?: cfg[@"server_base"] ?: @"";
    NSString *gtApi = cfg[@"gongtian_api_base"] ?: cfg[@"server_base"] ?: @"";
    NSString *deviceId = WSDeviceId();

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
        WSJSONString(deviceId), WSJSONString(insApi), WSJSONString(gtApi)];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:flags
                                                                       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                                    forMainFrameOnly:NO]];
    [config.userContentController addScriptMessageHandler:self name:@"InsulationNativeBridge"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    [self.view addSubview:self.webView];

    NSString *wwwDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
    NSString *pagePath = [wwwDir stringByAppendingPathComponent:entry];
    if (![[NSFileManager defaultManager] fileExistsAtPath:pagePath]) {
        pagePath = [wwwDir stringByAppendingPathComponent:@"index.html"];
    }
    [self.webView loadFileURL:[NSURL fileURLWithPath:pagePath]
        allowingReadAccessToURL:[NSURL fileURLWithPath:wwwDir isDirectory:YES]];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)prefersStatusBarHidden { return NO; }

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController; (void)message;
}

- (void)webView:(WKWebView *)webView
runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    completionHandler(defaultText ?: @"");
}
@end

static UIWindow *sOverlayWindow = nil;

static void WSPresentOverlay(void) {
    if (sOverlayWindow) return;
    UIWindow *win = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    win.windowLevel = UIWindowLevelAlert + 100;
    win.backgroundColor = UIColor.blackColor;
    win.rootViewController = [WSOverlayController new];
    [win makeKeyAndVisible];
    sOverlayWindow = win;
}

static void WSHook(void) {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
        // 等游戏自己把窗口建起来，再盖住
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WSPresentOverlay();
        });
    }];
}

__attribute__((constructor))
static void WebShellDylibEntry(void) {
    WSHook();
}
