#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RootViewController : UIViewController
@end
@implementation RootViewController
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (BOOL)prefersStatusBarHidden { return NO; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) RootViewController *rootVC;
@end

@implementation AppDelegate

static NSDictionary *LoadRuntimeConfig(void) {
    @try {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-config" ofType:@"json" inDirectory:@"www"];
        if (!path) path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www/runtime-config.json"];
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return @{};
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return @{};
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
    } @catch (__unused NSException *e) { return @{}; }
}

static NSString *JSONString(NSString *value) {
    NSString *raw = value ?: @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[raw] options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *arr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arr.length >= 2) return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
    return @"\"\"";
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

- (CGFloat)safeTop {
    if (@available(iOS 11.0, *)) {
        CGFloat a = self.window.safeAreaInsets.top;
        CGFloat b = self.rootVC.view.safeAreaInsets.top;
        return a > 0 ? a : b;
    }
    return 20;
}
- (CGFloat)safeBottom {
    if (@available(iOS 11.0, *)) {
        CGFloat a = self.window.safeAreaInsets.bottom;
        CGFloat b = self.rootVC.view.safeAreaInsets.bottom;
        return a > 0 ? a : b;
    }
    return 0;
}

- (NSString *)handleBridgeMethod:(NSString *)method args:(NSArray *)args {
    if ([method isEqualToString:@"getDeviceId"]) return DeviceId();
    if ([method isEqualToString:@"getDeviceLabel"]) return UIDevice.currentDevice.model ?: @"iPhone";
    if ([method isEqualToString:@"getDeviceType"]) return @"mobile";
    if ([method isEqualToString:@"getSafeAreaTop"]) return [NSString stringWithFormat:@"%d", (int)lround([self safeTop])];
    if ([method isEqualToString:@"getSafeAreaBottom"]) return [NSString stringWithFormat:@"%d", (int)lround([self safeBottom])];
    if ([method isEqualToString:@"exitApp"]) { dispatch_async(dispatch_get_main_queue(), ^{ exit(0); }); return @""; }
    if ([method isEqualToString:@"goAppHome"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:@"location.href='baowen/shell.html'" completionHandler:nil];
        });
        return @"";
    }
    (void)args; return @"";
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.rootVC = [RootViewController new];
    self.rootVC.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.04 alpha:1];
    self.window.backgroundColor = self.rootVC.view.backgroundColor;
    self.window.rootViewController = self.rootVC;
    [self.window makeKeyAndVisible];
    BOOL minimal = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BaoWenMinimalUI"] boolValue];
    if (minimal) {
        UILabel *label = [[UILabel alloc] initWithFrame:self.rootVC.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0; label.textColor = UIColor.whiteColor;
        label.text = @"保温系统\n最小模式"; [self.rootVC.view addSubview:label]; return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self mountWebView]; });
    return YES;
}

- (void)mountWebView {
    @try {
        NSDictionary *cfg = LoadRuntimeConfig();
        NSString *entry = cfg[@"assets_entry"] ?: @"baowen/shell.html";
        NSString *insApi = cfg[@"insulation_api_base"] ?: cfg[@"server_base"] ?: @"";
        NSString *gtApi = cfg[@"gongtian_api_base"] ?: cfg[@"server_base"] ?: @"";
        NSString *deviceId = DeviceId();

        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.allowsInlineMediaPlayback = YES;
        if (@available(iOS 10.0, *)) config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        @try {
            [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
            [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
        } @catch (__unused NSException *e) {}
        if (@available(iOS 14.0, *)) config.defaultWebpagePreferences.allowsContentJavaScript = YES;

        NSString *bridgeJs =
            @"(function(){if(window.InsulationNativeBridge&&window.InsulationNativeBridge.__iosPromptBridge)return;"
            "function call(method){var args=Array.prototype.slice.call(arguments,1);"
            "var payload=JSON.stringify({method:method,args:args});var ret=prompt('__BRIDGE__'+payload);"
            "return(ret===null||ret===undefined)?'':String(ret);}"
            "window.InsulationNativeBridge={__iosPromptBridge:true,"
            "getDeviceId:function(){return call('getDeviceId');},"
            "getDeviceLabel:function(){return call('getDeviceLabel');},"
            "getDeviceType:function(){return call('getDeviceType');},"
            "getSafeAreaTop:function(){return parseInt(call('getSafeAreaTop')||'0',10)||0;},"
            "getSafeAreaBottom:function(){return parseInt(call('getSafeAreaBottom')||'0',10)||0;},"
            "setStatusBarColor:function(c){call('setStatusBarColor',c||'');},"
            "setScreenshotProtectionForTab:function(t){call('setScreenshotProtectionForTab',t||'');},"
            "saveDownloadFile:function(b,f,m){call('saveDownloadFile',b||'',f||'',m||'');},"
            "pickRestoreFile:function(){call('pickRestoreFile');},"
            "getDailyReminderSettings:function(){return call('getDailyReminderSettings');},"
            "saveDailyReminderSettings:function(j){return call('saveDailyReminderSettings',j||'{}');},"
            "openExactAlarmPermissionSettings:function(){call('openExactAlarmPermissionSettings');},"
            "openApplicationPermissionSettings:function(){call('openApplicationPermissionSettings');},"
            "pickDailyReminderSound:function(){call('pickDailyReminderSound');},"
            "requestNotificationPermission:function(){call('requestNotificationPermission');},"
            "goAppHome:function(s){call('goAppHome',s||'');},"
            "exitApp:function(){call('exitApp');}};})();";

        NSString *flags = [NSString stringWithFormat:
            @"(function(){try{localStorage.setItem('insulation_device_id',%@);"
            "window.__INSULATION_APP__=true;window.__INSULATION_NATIVE_APP__=true;"
            "window.__GONGTIAN_NATIVE_APP__=true;window.__DUAL_ONLINE_APP__=true;"
            "window.GONGTIAN_LOCAL_PACKAGE=true;window.GONGTIAN_LOCAL_FIRST=false;"
            "document.documentElement.classList.add('baowen-native-app');"
            "document.documentElement.classList.add('gongtian-native-app');"
            "if(%@!==''){window.INSULATION_API_BASE=%@;window.__INSULATION_API_BASE__=%@;}"
            "if(%@!==''){window.GONGTIAN_REMOTE_API_BASE=%@;window.GONGTIAN_API_BASE=%@;window.__GONGTIAN_API_BASE__=%@;}"
            "window.__INSULATION_DEVICE_ID__=%@;}catch(e){}})();",
            JSONString(deviceId),
            JSONString(insApi), JSONString(insApi), JSONString(insApi),
            JSONString(gtApi), JSONString(gtApi), JSONString(gtApi), JSONString(gtApi),
            JSONString(deviceId)];

        int sat = (int)lround([self safeTop]);
        int sab = (int)lround([self safeBottom]);
        NSString *layoutJs = [NSString stringWithFormat:
            @"(function(){try{"
            "var m=document.querySelector('meta[name=\"viewport\"]');"
            "if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}"
            "var c=m.getAttribute('content')||'width=device-width, initial-scale=1.0';"
            "if(c.indexOf('viewport-fit')<0)c=c.replace(/\\s*$/,'')+', viewport-fit=cover';"
            "m.setAttribute('content',c);"
            "document.documentElement.classList.add('baowen-native-app');"
            "document.documentElement.style.setProperty('--sat','%dpx');"
            "document.documentElement.style.setProperty('--sab','%dpx');"
            "if(!document.getElementById('baowen-native-safearea')){"
            "var css=document.createElement('style');css.id='baowen-native-safearea';"
            "css.textContent='html.baowen-native-app,html.baowen-native-app body{height:100%%;min-height:100%%;min-height:-webkit-fill-available;overflow:hidden;background:#0a0a0a;}'"
            "+'html.baowen-native-app .shell{height:100%%;min-height:100%%;min-height:-webkit-fill-available;}'"
            "+'html.baowen-native-app .nav-container{padding-top:env(safe-area-inset-top,var(--sat,0px));height:auto;'"
            "+'min-height:calc(64px + env(safe-area-inset-top,var(--sat,0px)));box-sizing:border-box;}'"
            "+'html.baowen-native-app .tab-panels{padding-bottom:env(safe-area-inset-bottom,var(--sab,0px));}'"
            "+'html.baowen-native-app .auth-wrap{min-height:-webkit-fill-available;'"
            "+'padding-top:calc(2rem + env(safe-area-inset-top,var(--sat,0px)));'"
            "+'padding-bottom:calc(2rem + env(safe-area-inset-bottom,var(--sab,0px)));}';"
            "(document.head||document.documentElement).appendChild(css);}"
            "}catch(e){}})();", sat, sab];

        WKUserContentController *ucc = config.userContentController;
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:bridgeJs injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:flags injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:layoutJs injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addScriptMessageHandler:self name:@"InsulationNativeBridge"];

        UIView *host = self.rootVC.view;
        self.webView = [[WKWebView alloc] initWithFrame:host.bounds configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.UIDelegate = self;
        self.webView.navigationDelegate = self;
        self.webView.opaque = NO;
        self.webView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.04 alpha:1];
        self.webView.scrollView.backgroundColor = self.webView.backgroundColor;
        self.webView.scrollView.bounces = YES;
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.webView.scrollView.contentInset = UIEdgeInsetsZero;
        self.webView.allowsBackForwardNavigationGestures = YES;
        [host addSubview:self.webView];

        NSString *wwwDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
        NSString *pagePath = [wwwDir stringByAppendingPathComponent:entry];
        if (![[NSFileManager defaultManager] fileExistsAtPath:pagePath])
            pagePath = [wwwDir stringByAppendingPathComponent:@"index.html"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:pagePath]) {
            [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://1.14.142.104:3101/"]]];
            return;
        }
        [self.webView loadFileURL:[NSURL fileURLWithPath:pagePath]
            allowingReadAccessToURL:[NSURL fileURLWithPath:wwwDir isDirectory:YES]];
    } @catch (NSException *ex) {
        NSLog(@"BaoWen webview exception: %@", ex);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    int sat = (int)lround([self safeTop]);
    int sab = (int)lround([self safeBottom]);
    NSString *js = [NSString stringWithFormat:
        @"document.documentElement.style.setProperty('--sat','%dpx');"
        "document.documentElement.style.setProperty('--sab','%dpx');"
        "document.documentElement.classList.add('baowen-native-app');", sat, sab];
    [webView evaluateJavaScript:js completionHandler:nil];
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:@"InsulationNativeBridge"]) return;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = message.body;
    NSString *method = [body[@"method"] isKindOfClass:[NSString class]] ? body[@"method"] : @"";
    NSArray *args = [body[@"args"] isKindOfClass:[NSArray class]] ? body[@"args"] : @[];
    [self handleBridgeMethod:method args:args];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    if ([prompt hasPrefix:@"__BRIDGE__"]) {
        NSString *jsonText = [prompt substringFromIndex:10];
        NSData *data = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSString *method = [obj[@"method"] isKindOfClass:[NSString class]] ? obj[@"method"] : @"";
            NSArray *args = [obj[@"args"] isKindOfClass:[NSArray class]] ? obj[@"args"] : @[];
            completionHandler([self handleBridgeMethod:method args:args] ?: @"");
            return;
        }
        completionHandler(@""); return;
    }
    completionHandler(defaultText ?: @"");
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
