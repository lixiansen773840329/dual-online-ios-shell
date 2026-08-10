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
            /* 对齐安卓：LOCAL_PACKAGE + LOCAL_FIRST + REMOTE；勿写死 GONGTIAN_API_BASE */
            "window.GONGTIAN_LOCAL_PACKAGE=true;window.GONGTIAN_LOCAL_FIRST=true;"
            "window.GONGTIAN_WEB_DEPLOYMENT=false;window.GONGTIAN_IS_LOCAL_PACKAGE=true;"
            "try{if(window.GONGTIAN_API_BASE){delete window.GONGTIAN_API_BASE;}}catch(eDel){}"
            "var href=String(location.href||'');"
            "var isBaowen=/\\/baowen\\//i.test(href);"
            "var isGongtian=/\\/gongtian\\//i.test(href)||document.documentElement.classList.contains('app-shell-page');"
            "if(isBaowen)document.documentElement.classList.add('baowen-native-app');"
            "else document.documentElement.classList.remove('baowen-native-app');"
            "if(isGongtian)document.documentElement.classList.add('gongtian-native-app');"
            "if(%@!==''){window.INSULATION_API_BASE=%@;window.__INSULATION_API_BASE__=%@;}"
            "if(%@!==''){window.GONGTIAN_REMOTE_API_BASE=%@;}"
            "window.__INSULATION_DEVICE_ID__=%@;}catch(e){}})();",
            JSONString(deviceId),
            JSONString(insApi), JSONString(insApi), JSONString(insApi),
            JSONString(gtApi), JSONString(gtApi),
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
            "var href=String(location.href||'');"
            "var isGtShell=document.documentElement.classList.contains('app-shell-page');"
            "var isGtPath=/\\/gongtian\\//i.test(href);"
            "var isBaowenPath=/\\/baowen\\//i.test(href);"
            "if(isBaowenPath)document.documentElement.classList.add('baowen-native-app');"
            "else document.documentElement.classList.remove('baowen-native-app');"
            /* 工天兜底：强制揭示 + 关掉外壳遮罩，避免 #1a0505 黑屏 */
            "if((isGtPath||isGtShell)&&!window.__gtIosRevealArmed){window.__gtIosRevealArmed=true;"
            "function __gtReveal(){try{var r=document.documentElement;"
            "r.classList.add('site-bg-ready','site-ui-ready','gongtian-native-app');"
            "r.classList.remove('page-bg-pending','page-bg-pending-shell','shell-frame-cover-visible','shell-frame-navigating');"
            "if(document.body){document.body.style.setProperty('opacity','1','important');"
            "document.body.style.setProperty('visibility','visible','important');}"
            "document.querySelectorAll('body > main,#mainNav,.marquee-bar,body > footer').forEach(function(el){"
            "el.style.setProperty('opacity','1','important');"
            "el.style.setProperty('visibility','visible','important');});"
            "if(typeof hideShellFrameCover==='function')hideShellFrameCover();"
            "var cover=document.getElementById('shellFrameCover');"
            "if(cover){cover.style.setProperty('opacity','0','important');"
            "cover.style.setProperty('visibility','hidden','important');"
            "cover.style.setProperty('display','none','important');}"
            "var f=document.getElementById('mainFrame');"
            "if(f){f.style.setProperty('opacity','1','important');f.style.setProperty('visibility','visible','important');"
            "if(typeof revealShellIframe==='function')revealShellIframe(f);}"
            "}catch(eRv){}}"
            "setTimeout(__gtReveal,200);setTimeout(__gtReveal,700);setTimeout(__gtReveal,1600);}"
            "document.documentElement.style.webkitTextSizeAdjust='100%';"
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
            /* 工天外壳：iframe 可见，遮罩强制关掉（防卡死黑屏） */
            "+'html.app-shell-page,html.app-shell-page body{height:100%!important;overflow:hidden!important;"
            "+'background:#1a0505!important;}'"
            "+'html.app-shell-page #mainFrame{opacity:1!important;visibility:visible!important;}'"
            "+'html.app-shell-page #shellFrameCover,html.app-shell-page.shell-frame-cover-visible #shellFrameCover{' "
            "+'opacity:0!important;visibility:hidden!important;pointer-events:none!important;display:none!important;}'"
            "+'html.gongtian-native-app body,html.site-bg-ready body{opacity:1!important;visibility:visible!important;}'"
            "+'html.gongtian-native-app body>main,html.site-bg-ready body>main,' "
            "+'html.gongtian-native-app #mainNav,html.site-bg-ready #mainNav{opacity:1!important;visibility:visible!important;}'"
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
            "if(!isGtShell&&!isGtPath&&isBaowenPath&&!document.querySelector('.shell'))document.documentElement.classList.add('baowen-native-scroll');"
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
            "var d=ev&&ev.data;if(!d)return;"
            "if(d.type==='baowen-pwd-modal-closed'){"
            "var h0=document.getElementById('baowenPwdHostOverlay');"
            "if(h0){h0.className='';h0.innerHTML='';}return;}"
            "if(d.type==='baowen-native-open-url'&&d.url){"
            "var u=String(d.url);"
            "if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.InsulationNativeBridge){"
            "window.webkit.messageHandlers.InsulationNativeBridge.postMessage({method:'openExternalUrl',args:[u]});return;}"
            "if(window.InsulationNativeBridge&&typeof window.InsulationNativeBridge.openExternalUrl==='function'){"
            "window.InsulationNativeBridge.openExternalUrl(u);}return;}"
            /* 退出登录等确认框：挂到外壳 */
            "if(d.type==='baowen-host-confirm'){"
            "if(!document.getElementById('baowen-pwd-host-css')){"
            "var stC=document.createElement('style');stC.id='baowen-pwd-host-css';"
            "stC.textContent='#baowenPwdHostOverlay{position:fixed;inset:0;z-index:2147483646;display:none;"
            "align-items:center;justify-content:center;padding:1rem;box-sizing:border-box;background:rgba(10,10,10,.88);}"
            "#baowenPwdHostOverlay.show{display:flex!important;}"
            "#baowenPwdHostOverlay .pwd-modal,#baowenPwdHostOverlay .bw-host-confirm{"
            "width:100%;max-width:360px;background:linear-gradient(145deg,rgba(139,0,0,.98),rgba(178,34,34,.95));"
            "border:1px solid rgba(212,175,55,.45);border-radius:1rem;padding:1.25rem;box-shadow:0 16px 40px rgba(0,0,0,.55);color:#f5d488;}"
            "#baowenPwdHostOverlay .bw-host-confirm h3{margin:0 0 .75rem;font-size:1.1rem;}"
            "#baowenPwdHostOverlay .bw-host-confirm p{margin:0 0 1rem;font-size:.9rem;color:rgba(245,212,136,.9);line-height:1.5;}"
            "#baowenPwdHostOverlay .pwd-modal-actions{display:flex;gap:.5rem;justify-content:flex-end;}"
            "#baowenPwdHostOverlay .pwd-modal-actions button{padding:.5rem 1rem;border-radius:.5rem;"
            "border:1px solid rgba(212,175,55,.35);background:rgba(0,0,0,.25);color:#f5d488;}"
            "#baowenPwdHostOverlay .pwd-modal-actions button.primary{background:linear-gradient(135deg,#d4af37,#f5d488);color:#0a0a0a;border:none;font-weight:600;}';"
            "(document.head||document.documentElement).appendChild(stC);}"
            "var hostC=document.getElementById('baowenPwdHostOverlay');"
            "if(!hostC){hostC=document.createElement('div');hostC.id='baowenPwdHostOverlay';document.body.appendChild(hostC);}"
            "var title=String(d.title||'确认');var msg=String(d.message||'');"
            "var okT=String(d.confirmText||'确定');var cancelT=String(d.cancelText||'取消');"
            "hostC.innerHTML='<div class=\"bw-host-confirm\"><h3></h3><p></p>"
            "<div class=\"pwd-modal-actions\"><button type=\"button\" data-act=\"cancel\"></button>"
            "<button type=\"button\" class=\"primary\" data-act=\"ok\"></button></div></div>';"
            "hostC.querySelector('h3').textContent=title;"
            "hostC.querySelector('p').textContent=msg;"
            "hostC.querySelector('[data-act=cancel]').textContent=cancelT;"
            "hostC.querySelector('[data-act=ok]').textContent=okT;"
            "hostC.className='show';"
            "function finishConfirm(ok){hostC.className='';hostC.innerHTML='';"
            "try{ev.source&&ev.source.postMessage({type:'baowen-host-confirm-result',id:d.id,ok:!!ok},'*');}catch(eF){}}"
            "hostC.onclick=function(e){if(e.target===hostC)finishConfirm(false);};"
            "hostC.querySelector('[data-act=cancel]').onclick=function(){finishConfirm(false);};"
            "hostC.querySelector('[data-act=ok]').onclick=function(){finishConfirm(true);};"
            "return;}"
            /* 子 iframe 修改信息：把弹层挂到外壳，避免 WK iframe fixed 失效 */
            "if(d.type==='baowen-host-pwd-modal'&&d.html){"
            "if(!document.getElementById('baowen-pwd-host-css')){"
            "var st=document.createElement('style');st.id='baowen-pwd-host-css';"
            "st.textContent='#baowenPwdHostOverlay{position:fixed;inset:0;z-index:2147483646;display:none;"
            "align-items:center;justify-content:center;padding:1rem;box-sizing:border-box;background:rgba(10,10,10,.88);}"
            "#baowenPwdHostOverlay.show{display:flex!important;}"
            "#baowenPwdHostOverlay .pwd-modal{width:100%;max-width:400px;max-height:calc(100% - 2rem);overflow-y:auto;"
            "-webkit-overflow-scrolling:touch;background:linear-gradient(145deg,rgba(139,0,0,.98),rgba(178,34,34,.95));"
            "border:1px solid rgba(212,175,55,.45);border-radius:1rem;padding:1.25rem;box-shadow:0 16px 40px rgba(0,0,0,.55);}"
            "#baowenPwdHostOverlay .pwd-modal h3{color:#f5d488;margin:0 0 1rem;font-size:1.125rem;}"
            "#baowenPwdHostOverlay .pwd-field{margin-bottom:.875rem;}"
            "#baowenPwdHostOverlay .pwd-field label{display:block;font-size:.8125rem;color:rgba(245,212,136,.9);margin-bottom:.35rem;}"
            "#baowenPwdHostOverlay .pwd-field input{width:100%;padding:.625rem .75rem;border-radius:.5rem;box-sizing:border-box;"
            "border:1px solid rgba(212,175,55,.3);background:rgba(0,0,0,.35);color:#fff;}"
            "#baowenPwdHostOverlay .pwd-section-title{font-size:.8125rem;color:rgba(245,212,136,.75);margin:1rem 0 .75rem;padding-top:.75rem;border-top:1px solid rgba(212,175,55,.2);}"
            "#baowenPwdHostOverlay .pwd-modal-actions{display:flex;gap:.5rem;justify-content:flex-end;margin-top:1rem;}"
            "#baowenPwdHostOverlay .pwd-modal-actions button{padding:.5rem 1rem;border-radius:.5rem;border:1px solid rgba(212,175,55,.35);background:rgba(0,0,0,.25);color:#f5d488;}"
            "#baowenPwdHostOverlay .pwd-modal-actions button.primary{background:linear-gradient(135deg,#d4af37,#f5d488);color:#0a0a0a;border:none;font-weight:600;}"
            "#baowenPwdHostOverlay .pwd-msg{font-size:.8125rem;margin-top:.5rem;min-height:1.25rem;color:#ffb3b3;}';"
            "(document.head||document.documentElement).appendChild(st);}"
            "var host=document.getElementById('baowenPwdHostOverlay');"
            "if(!host){host=document.createElement('div');host.id='baowenPwdHostOverlay';document.body.appendChild(host);}"
            "host.innerHTML=String(d.html);"
            "host.className='show';"
            "try{ev.source&&ev.source.postMessage({type:'baowen-host-pwd-modal-ready'},'*');}catch(eAck){}"
            "host.onclick=function(e){if(e.target===host){host.className='';host.innerHTML='';"
            "try{ev.source&&ev.source.postMessage({type:'baowen-pwd-modal-closed'},'*');}catch(eC){}}};"
            "var cancel=host.querySelector('#pwdModalCancel');"
            "if(cancel)cancel.onclick=function(){host.className='';host.innerHTML='';"
            "try{ev.source&&ev.source.postMessage({type:'baowen-pwd-modal-closed'},'*');}catch(eC2){};};"
            "var form=host.querySelector('#changePwdForm');"
            "if(form)form.onsubmit=function(e){e.preventDefault();"
            "var payload={type:'baowen-pwd-modal-submit',"
            "nickname:(host.querySelector('#profileNickname')||{}).value||'',"
            "oldPassword:(host.querySelector('#oldPassword')||{}).value||'',"
            "newPassword:(host.querySelector('#newPasswordHome')||{}).value||'',"
            "confirmPassword:(host.querySelector('#confirmPasswordHome')||{}).value||''};"
            "try{ev.source&&ev.source.postMessage(payload,'*');}catch(eS){};};"
            "}"
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
        @        "document.documentElement.style.setProperty('--sat','%dpx');"
        "document.documentElement.style.setProperty('--sab','%dpx');"
        "var href=String(location.href||'');"
        "if(/\\/baowen\\//i.test(href))"
        "document.documentElement.classList.add('baowen-native-app');"
        "else document.documentElement.classList.remove('baowen-native-app');"
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
