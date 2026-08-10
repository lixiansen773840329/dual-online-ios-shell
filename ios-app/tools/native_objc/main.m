#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

/**
 * 自研保温壳。启动先保证窗口可见，再异步加载 WebView，避免同步崩溃。
 * 环境变量式开关（Info.plist BaoWenMinimalUI=YES）可只显示占位页，用于排除法。
 */

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) UILabel *statusLabel;
@end

@implementation AppDelegate

static NSDictionary *LoadRuntimeConfig(void) {
    @try {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-config" ofType:@"json" inDirectory:@"www"];
        if (!path) {
            path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www/runtime-config.json"];
        }
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return @{};
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return @{};
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    } @catch (__unused NSException *e) {
        return @{};
    }
}

static NSString *JSONString(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(value ?: @"") options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"\"";
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
    @try {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor colorWithRed:0.75 green:0.05 blue:0.05 alpha:1.0];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 24, 80)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont boldSystemFontOfSize:22];
        label.text = @"保温系统\n启动成功";
        [vc.view addSubview:label];
        self.statusLabel = label;

        self.window.rootViewController = vc;
        [self.window makeKeyAndVisible];

        BOOL minimal = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BaoWenMinimalUI"] boolValue];
        if (minimal) {
            label.text = @"保温系统\n最小模式（无 WebView）\n若你能看到这行=原生壳正常";
            return YES;
        }

        // 延迟加载 WebView，确保先完成首帧
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self mountWebViewOn:vc];
        });
        return YES;
    } @catch (NSException *ex) {
        NSLog(@"BaoWen launch exception: %@", ex);
        return YES;
    }
}

- (void)mountWebViewOn:(UIViewController *)vc {
    @try {
        NSDictionary *cfg = LoadRuntimeConfig();
        NSString *entry = cfg[@"assets_entry"] ?: @"baowen/shell.html";
        NSString *insApi = cfg[@"insulation_api_base"] ?: cfg[@"server_base"] ?: @"";
        NSString *gtApi = cfg[@"gongtian_api_base"] ?: cfg[@"server_base"] ?: @"";
        NSString *deviceId = DeviceId();

        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        @try {
            [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
            [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
        } @catch (__unused NSException *e) {}
        if (@available(iOS 14.0, *)) {
            config.defaultWebpagePreferences.allowsContentJavaScript = YES;
        }
        NSString *flags = [NSString stringWithFormat:
            @"window.__INSULATION_APP__=true;"
            @"window.__INSULATION_DEVICE_ID__=%@;"
            @"window.__INSULATION_API_BASE__=%@;"
            @"window.__GONGTIAN_API_BASE__=%@;",
            JSONString(deviceId), JSONString(insApi), JSONString(gtApi)];
        [config.userContentController addUserScript:
            [[WKUserScript alloc] initWithSource:flags
                                   injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                forMainFrameOnly:NO]];
        [config.userContentController addScriptMessageHandler:self name:@"InsulationNativeBridge"];

        self.webView = [[WKWebView alloc] initWithFrame:vc.view.bounds configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.UIDelegate = self;
        self.webView.navigationDelegate = self;
        [vc.view insertSubview:self.webView belowSubview:self.statusLabel];

        NSString *wwwDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
        NSString *pagePath = [wwwDir stringByAppendingPathComponent:entry];
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:pagePath]) {
            pagePath = [wwwDir stringByAppendingPathComponent:@"index.html"];
        }
        if (![fm fileExistsAtPath:pagePath]) {
            self.statusLabel.text = [NSString stringWithFormat:@"保温系统\n缺少页面文件\n%@", entry];
            // 退化为在线地址
            NSString *online = insApi.length ? [insApi stringByAppendingString:@"/"] : @"http://1.14.142.104:3101/";
            [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:online]]];
            return;
        }
        self.statusLabel.text = @"保温系统\n加载中…";
        NSURL *page = [NSURL fileURLWithPath:pagePath];
        NSURL *root = [NSURL fileURLWithPath:wwwDir isDirectory:YES];
        [self.webView loadFileURL:page allowingReadAccessToURL:root];
    } @catch (NSException *ex) {
        self.statusLabel.text = [NSString stringWithFormat:@"WebView 异常\n%@", ex.reason ?: @"unknown"];
        NSLog(@"BaoWen webview exception: %@", ex);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.statusLabel.hidden = YES;
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = [NSString stringWithFormat:@"加载失败\n%@", error.localizedDescription ?: @""];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = [NSString stringWithFormat:@"加载失败\n%@", error.localizedDescription ?: @""];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
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
