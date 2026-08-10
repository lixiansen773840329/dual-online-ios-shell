#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>

@interface RootViewController : UIViewController
@property (nonatomic, copy) void (^onLayout)(void);
@end
@implementation RootViewController
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (BOOL)prefersStatusBarHidden { return NO; }
- (BOOL)prefersHomeIndicatorAutoHidden { return NO; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.view.backgroundColor = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.onLayout) self.onLayout();
}
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
    if ([method isEqualToString:@"openExternalUrl"]) {
        NSString *raw = (args.count && [args[0] isKindOfClass:[NSString class]]) ? args[0] : @"";
        [self openExternalURLString:raw];
        return @"";
    }
    if ([method isEqualToString:@"exitApp"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            /* 企业签/超级签场景允许直接结束进程 */
            UIApplication *app = UIApplication.sharedApplication;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            if ([app respondsToSelector:NSSelectorFromString(@"suspend")]) {
                [app performSelector:NSSelectorFromString(@"suspend")];
            }
#pragma clang diagnostic pop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                exit(0);
            });
        });
        return @"";
    }
    if ([method isEqualToString:@"goAppHome"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:@"location.href='baowen/shell.html'" completionHandler:nil];
        });
        return @"";
    }
    (void)args; return @"";
}

- (void)openExternalURLString:(NSString *)raw {
    if (!raw.length) return;
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) {
        NSString *enc = [raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
        url = [NSURL URLWithString:enc ?: raw];
    }
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *scheme = (url.scheme ?: @"").lowercaseString;
        /* http(s) 收银台：优先 SFSafariViewController，保证用户能看到跳转 */
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
            if (@available(iOS 9.0, *)) {
                SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
                UIViewController *presenter = self.rootVC;
                while (presenter.presentedViewController) {
                    presenter = presenter.presentedViewController;
                }
                [presenter presentViewController:svc animated:YES completion:nil];
                return;
            }
        }
        /* 支付宝/微信/QQ 等自定义 scheme：交给系统唤起 App */
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
            }
        }];
    });
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.rootVC = [RootViewController new];
    UIColor *wine = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
    self.rootVC.view.backgroundColor = wine;
    self.window.backgroundColor = wine;
    self.window.rootViewController = self.rootVC;
    __weak AppDelegate *weakSelf = self;
    self.rootVC.onLayout = ^{
        AppDelegate *strong = weakSelf;
        if (!strong || !strong.webView) return;
        strong.webView.frame = strong.rootVC.view.bounds;
        int sat = (int)lround([strong safeTop]);
        int sab = (int)lround([strong safeBottom]);
        NSString *js = [NSString stringWithFormat:
            @"document.documentElement.style.setProperty('--sat','%dpx');"
            "document.documentElement.style.setProperty('--sab','%dpx');", sat, sab];
        [strong.webView evaluateJavaScript:js completionHandler:nil];
    };
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
            "openExternalUrl:function(u){"
            "try{if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.InsulationNativeBridge){"
            "window.webkit.messageHandlers.InsulationNativeBridge.postMessage({method:'openExternalUrl',args:[u||'']});return;}}catch(e){}"
            "call('openExternalUrl',u||'');},"
            "goAppHome:function(s){call('goAppHome',s||'');},"
            "exitApp:function(){"
            "try{if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.InsulationNativeBridge){"
            "window.webkit.messageHandlers.InsulationNativeBridge.postMessage({method:'exitApp',args:[]});return;}}catch(e){}"
            "call('exitApp');}};})();";

        NSString *flags = [NSString stringWithFormat:
            @"(function(){try{localStorage.setItem('insulation_device_id',%@);"
            "window.__INSULATION_APP__=true;window.__INSULATION_NATIVE_APP__=true;"
            "window.__GONGTIAN_NATIVE_APP__=true;window.__DUAL_ONLINE_APP__=true;"
            "window.GONGTIAN_LOCAL_PACKAGE=true;window.GONGTIAN_LOCAL_FIRST=true;"
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

        /* 所有 frame：视口 + 红底铺满；保留资费锯齿；去掉蓝色点按高亮 */
        NSString *adaptiveJs =
            @"(function(){try{"
            "function applyScale(){"
            "var m=document.querySelector('meta[name=\"viewport\"]');"
            "if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}"
            "m.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');"
            "document.documentElement.classList.add('baowen-native-app');"
            "document.documentElement.style.webkitTextSizeAdjust='100%';"
            "var isGtShell=document.documentElement.classList.contains('app-shell-page');"
            "var isGtPath=/\\/gongtian\\//i.test(String(location.href||''));"
            "if(!document.getElementById('baowen-native-adaptive')){"
            "var css=document.createElement('style');css.id='baowen-native-adaptive';"
            "css.textContent="
            /* 铺满：用酒红底，避免顶底露出纯黑（仅保温页） */
            "'html.baowen-native-app:not(.app-shell-page) body:not(.auth-page){background-color:#5c0000!important;"
            "+'-webkit-text-size-adjust:100%!important;text-size-adjust:100%!important;}'"
            "+'html.baowen-native-app body.page-module::before{background-color:#5c0000!important;"
            "+'background-image:url(\"./beijingtu.jpg\"),url(\"../beijingtu.jpg\"),linear-gradient(180deg,#8B0000,#4a0000)!important;"
            "+'background-size:cover!important;background-position:center!important;position:absolute!important;"
            "+'top:0;left:0;right:0;bottom:0;min-height:100%!important;}'"
            "+'html.baowen-native-app.baowen-native-scroll{height:auto!important;min-height:100%!important;}'"
            "+'html.baowen-native-app.baowen-native-scroll body{height:auto!important;min-height:100%!important;"
            "+'overflow-x:hidden!important;overflow-y:auto!important;-webkit-overflow-scrolling:touch!important;touch-action:pan-y!important;}'"
            /* 工天外壳：禁止 baowen-scroll 破坏 100% 高 iframe */
            "+'html.app-shell-page,html.app-shell-page body{height:100%!important;overflow:hidden!important;"
            "+'background:#1a0505!important;}'"
            "+'html.app-shell-page #mainFrame{opacity:1!important;visibility:visible!important;}'"
            "+'html.app-shell-page #shellFrameCover{pointer-events:none!important;}'"
            "+'html.baowen-native-app body.tab-embedded{padding-bottom:0!important;}'"
            /* 悬浮球 */
            "+'#dualFloatFab,#dualFloatRestore{z-index:9000!important;}'"
            "+'#dualFloatMask,#dualFloatPanel,#dualExitConfirm,#dualFloatTip{z-index:100050!important;}'"
            "+'.insulation-modal-root,.insulation-guard-overlay{z-index:200000!important;}'"
            "+'#dualFloatFab{width:40px!important;height:40px!important;}'"
            /* 资费/支付：可点 + 去掉 iOS 蓝色 tap 高亮；不禁用撕边 */
            "+'html.baowen-native-app .notice-price-tag,html.baowen-native-app .notice-price-tag *,'"
            "+'html.baowen-native-app .notice-pay-btn,html.baowen-native-app .notice-pay-btn *{' "
            "+'-webkit-tap-highlight-color:transparent!important;outline:none!important;' "
            "+'-webkit-touch-callout:none!important;-webkit-user-select:none!important;user-select:none!important;}'"
            "+'html.baowen-native-app .notice-price-tag{pointer-events:auto!important;}'"
            "+'html.baowen-native-app .notice-pay-btn{pointer-events:auto!important;position:relative;z-index:8;"
            "+'-webkit-appearance:none;touch-action:manipulation;-webkit-tap-highlight-color:transparent!important;}'"
            "+'html.baowen-native-app .notice-contact{pointer-events:auto!important;}'"
            "+'html.baowen-native-app .notice-board{margin-bottom:0.35rem!important;}'"
            /* 登录页：固定壳，避免键盘顶起整页 */
            "+'html.baowen-native-login body{position:fixed!important;inset:0!important;"
            "+'width:100%!important;height:100%!important;overflow:hidden!important;}'"
            "+'html.baowen-native-app .auth-wrap{height:100%!important;max-height:100%!important;overflow-y:auto!important;"
            "+'-webkit-overflow-scrolling:touch;padding-top:calc(1rem + env(safe-area-inset-top,var(--sat,0px)))!important;"
            "+'padding-bottom:calc(1rem + env(safe-area-inset-bottom,var(--sab,0px)))!important;box-sizing:border-box!important;}';"
            "(document.head||document.documentElement).appendChild(css);}"
            "if(!isGtShell&&!isGtPath&&!document.querySelector('.shell'))document.documentElement.classList.add('baowen-native-scroll');"
            "else document.documentElement.classList.remove('baowen-native-scroll');"
            "if(document.querySelector('.auth-wrap'))document.documentElement.classList.add('baowen-native-login');"
            "else document.documentElement.classList.remove('baowen-native-login');"
            "}"
            "applyScale();"
            "window.addEventListener('resize',applyScale,{passive:true});"
            "}catch(e){}})();";

        /* 仅主 frame：顶栏安全区 + iframe 支付 URL 中转 */
        NSString *shellLayoutJs = [NSString stringWithFormat:
            @"(function(){try{"
            "document.documentElement.style.setProperty('--sat','%dpx');"
            "document.documentElement.style.setProperty('--sab','%dpx');"
            "if(!document.getElementById('baowen-native-safearea')){"
            "var css=document.createElement('style');css.id='baowen-native-safearea';"
            "css.textContent='html.baowen-native-app,html.baowen-native-app body{background:#5c0000!important;height:100%%;}'"
            "+'html.baowen-native-app .shell{position:fixed;inset:0;height:100%%;width:100%%;"
            "+'min-height:100%%;min-height:-webkit-fill-available;background:#5c0000!important;}'"
            "+'html.baowen-native-app .nav-container{padding-top:max(env(safe-area-inset-top,0px),var(--sat,0px));height:auto;'"
            "+'min-height:calc(52px + max(env(safe-area-inset-top,0px),var(--sat,0px)));box-sizing:border-box;}'"
            "+'html.baowen-native-app .tab-panels{padding-bottom:0!important;background:#5c0000!important;flex:1;min-height:0;}'"
            "+'html.baowen-native-app .tab-panel{background:#5c0000!important;}';"
            "(document.head||document.documentElement).appendChild(css);}"
            "if(!window.__baowenOpenUrlRelay){window.__baowenOpenUrlRelay=true;"
            "window.addEventListener('message',function(ev){try{"
            "var d=ev&&ev.data;if(!d||d.type!=='baowen-native-open-url'||!d.url)return;"
            "var u=String(d.url);"
            "if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.InsulationNativeBridge){"
            "window.webkit.messageHandlers.InsulationNativeBridge.postMessage({method:'openExternalUrl',args:[u]});return;}"
            "if(window.InsulationNativeBridge&&typeof window.InsulationNativeBridge.openExternalUrl==='function'){"
            "window.InsulationNativeBridge.openExternalUrl(u);}"
            "}catch(e){}},false);}"
            "}catch(e){}})();", sat, sab];

        WKUserContentController *ucc = config.userContentController;
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:bridgeJs injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:flags injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:adaptiveJs injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:shellLayoutJs injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
        [ucc addScriptMessageHandler:self name:@"InsulationNativeBridge"];

        UIView *host = self.rootVC.view;
        self.webView = [[WKWebView alloc] initWithFrame:host.bounds configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.UIDelegate = self;
        self.webView.navigationDelegate = self;
        self.webView.opaque = NO;
        UIColor *wine = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
        self.webView.backgroundColor = wine;
        self.webView.scrollView.backgroundColor = wine;
        /* shell 自身不滚动，交给 iframe 内页滚动，避免手势被外层抢走 */
        self.webView.scrollView.scrollEnabled = NO;
        self.webView.scrollView.bounces = NO;
        self.webView.scrollView.delaysContentTouches = NO;
        self.webView.scrollView.canCancelContentTouches = YES;
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.webView.scrollView.contentInset = UIEdgeInsetsZero;
        self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
        if (@available(iOS 11.0, *)) {
            self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        self.webView.allowsBackForwardNavigationGestures = NO;
        [host addSubview:self.webView];
        self.webView.frame = host.bounds;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardFrameChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardFrameChange:) name:UIKeyboardWillHideNotification object:nil];

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
        "document.documentElement.classList.add('baowen-native-app');"
        "try{if(typeof window.updatePriceTagTornEdges==='function')window.updatePriceTagTornEdges();}catch(e){}",
        sat, sab];
    [webView evaluateJavaScript:js completionHandler:nil];
    self.webView.scrollView.contentInset = UIEdgeInsetsZero;
    self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)onKeyboardFrameChange:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.webView.scrollView.contentInset = UIEdgeInsetsZero;
        self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
        /* 不强制改 contentOffset，避免和 iframe 内滑动抢手势导致卡死 */
    });
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (!url) { decisionHandler(WKNavigationActionPolicyAllow); return; }
    NSString *abs = (url.absoluteString ?: @"").lowercaseString;
    NSString *scheme = (url.scheme ?: @"").lowercaseString;

    BOOL isHttp = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
    BOOL isFile = [scheme isEqualToString:@"file"] || [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"blob"];

    /* 支付宝/微信等 App Scheme 或 alipays:// 中间页 */
    BOOL looksPayApp =
        [abs hasPrefix:@"alipay"] || [abs hasPrefix:@"alipays"] ||
        [abs hasPrefix:@"weixin"] || [abs hasPrefix:@"wechat"] ||
        [abs hasPrefix:@"mqqapi"] || [abs hasPrefix:@"mqq"] ||
        [abs containsString:@"://platformapi/startapp"] ||
        ([abs containsString:@"alipay.com/"] && [abs containsString:@"app_id="]);

    if (!isHttp && !isFile) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        });
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (isHttp && looksPayApp && navigationAction.navigationType != WKNavigationTypeOther) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        });
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)configuration; (void)windowFeatures;
    NSURL *url = navigationAction.request.URL;
    if (url) {
        if (!navigationAction.targetFrame.isMainFrame) {
            [webView loadRequest:navigationAction.request];
        }
    }
    return nil;
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    (void)webView; (void)frame;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { completionHandler(); }]];
    [self.rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    (void)webView; (void)frame;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) { completionHandler(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { completionHandler(YES); }]];
    [self.rootVC presentViewController:alert animated:YES completion:nil];
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
