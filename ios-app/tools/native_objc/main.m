#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Security/Security.h>

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
    if (@available(iOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
    self.view.backgroundColor = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
}
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    /* 禁止系统把 WebView 内容整体下推出一条黑带 */
    if (@available(iOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.onLayout) self.onLayout();
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, UIDocumentPickerDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) RootViewController *rootVC;
@property (strong, nonatomic) UIView *splashView;
@property (strong, nonatomic) UILabel *splashCountdownLabel;
@property (assign, nonatomic) BOOL splashFinished;
@property (strong, nonatomic) NSTimer *splashTimer;
@property (assign, nonatomic) NSInteger splashSecondsLeft;
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

/** 钥匙串读写：升级/覆盖安装通常保留；卸载后现代 iOS 仍可能清空（非硬件 UDID）。 */
static NSString *KeychainGet(NSString *service, NSString *account) {
    if (!service.length || !account.length) return nil;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (st != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL KeychainSet(NSString *service, NSString *account, NSString *value) {
    if (!service.length || !account.length || !value.length) return NO;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    };
    return SecItemAdd((__bridge CFDictionaryRef)add, NULL) == errSecSuccess;
}

/** 应用侧稳定设备码（非苹果硬件 UDID；公开 API 无法读取真实 UDID）。 */
static NSString *StableAppDeviceCode(void) {
    static NSString *cached = nil;
    if (cached.length) return cached;
    NSString *service = @"com.baowen.insulation.device";
    NSString *account = @"app_device_code";
    NSString *fromKc = KeychainGet(service, account);
    if (fromKc.length) {
        cached = fromKc;
        [[NSUserDefaults standardUserDefaults] setObject:cached forKey:@"insulation_device_id"];
        return cached;
    }
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *legacy = [ud stringForKey:@"insulation_device_id"];
    if (legacy.length) {
        KeychainSet(service, account, legacy);
        cached = legacy;
        return cached;
    }
    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"unknown";
    vendor = [[vendor stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    NSString *uuid = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    if (uuid.length > 16) uuid = [uuid substringToIndex:16];
    cached = [NSString stringWithFormat:@"ios_%@_%@", vendor, uuid];
    KeychainSet(service, account, cached);
    [ud setObject:cached forKey:@"insulation_device_id"];
    return cached;
}

static NSString *DeviceId(void) {
    return StableAppDeviceCode();
}

static NSString *VendorId(void) {
    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"";
    return [[vendor stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
}

static NSString *AppUdidAlias(void) {
    /* 对外别名 getUDID：返回钥匙串稳定设备码，不是苹果硬件 UDID */
    return StableAppDeviceCode();
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
    if ([method isEqualToString:@"getUDID"] || [method isEqualToString:@"getUdid"]) return AppUdidAlias();
    if ([method isEqualToString:@"getVendorId"] || [method isEqualToString:@"getIdentifierForVendor"]) return VendorId();
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
            UIApplication *app = UIApplication.sharedApplication;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            /* 先挂起再退出，兼容企业签/超级签 */
            SEL sus = NSSelectorFromString(@"suspend");
            if ([app respondsToSelector:sus]) {
                [app performSelector:sus];
            }
#pragma clang diagnostic pop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                exit(0);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                abort();
            });
        });
        return @"";
    }
    if ([method isEqualToString:@"goAppHome"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:@"location.href='index.html'" completionHandler:nil];
        });
        return @"";
    }
    if ([method isEqualToString:@"saveDownloadFile"]) {
        NSString *b64 = (args.count > 0 && [args[0] isKindOfClass:[NSString class]]) ? args[0] : @"";
        NSString *name = (args.count > 1 && [args[1] isKindOfClass:[NSString class]]) ? args[1] : @"download.bin";
        NSString *mime = (args.count > 2 && [args[2] isKindOfClass:[NSString class]]) ? args[2] : @"application/octet-stream";
        dispatch_async(dispatch_get_main_queue(), ^{
            [self saveDownloadBase64:b64 filename:name mimeType:mime];
        });
        return @"";
    }
    if ([method isEqualToString:@"pickRestoreFile"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self openRestoreFilePicker];
        });
        return @"";
    }
    (void)args; return @"";
}

- (void)saveDownloadBase64:(NSString *)base64 filename:(NSString *)filename mimeType:(NSString *)mimeType {
    (void)mimeType;
    if (!base64.length) {
        [self presentSimpleAlert:@"文件解码失败"];
        return;
    }
    NSString *raw = base64;
    NSRange range = [raw rangeOfString:@"base64,"];
    if (range.location != NSNotFound) {
        raw = [raw substringFromIndex:NSMaxRange(range)];
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:raw options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) {
        [self presentSimpleAlert:@"文件解码失败"];
        return;
    }
    NSString *rawName = filename.length ? filename : @"download.bin";
    NSString *safeName = [[rawName stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                          stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
    if (!safeName.length) safeName = @"download.bin";
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:safeName]];
    NSError *err = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&err]) {
        [self presentSimpleAlert:[NSString stringWithFormat:@"保存失败: %@", err.localizedDescription ?: @"未知错误"]];
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *presenter = self.rootVC;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = presenter.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    }
    [presenter presentViewController:activity animated:YES completion:nil];
}

- (void)openRestoreFilePicker {
    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        NSArray *types = @[
            UTTypeJSON,
            UTTypePlainText,
            UTTypeData
        ];
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"] inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    UIViewController *presenter = self.rootVC;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!data) {
        [self presentSimpleAlert:@"无法读取所选文件"];
        return;
    }
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    NSString *name = url.lastPathComponent ?: @"backup.json";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{"
        "var detail={name:%@,base64:%@,text:%@};"
        "window.dispatchEvent(new CustomEvent('gongtian-restore-file',{detail:detail}));"
        "if(window.onNativeRestoreFile)window.onNativeRestoreFile(detail);"
        "if(window.__handleNativeRestoreFile)window.__handleNativeRestoreFile(detail.text||'',detail.name||'backup.json');"
        "}catch(e){}})();",
        JSONString(name), JSONString(b64), JSONString(text)];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (void)presentSimpleAlert:(NSString *)message {
    if (!message.length) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *presenter = self.rootVC;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
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
    /* 不要强制 Dark：系统会在状态栏/Home 条区域铺黑底，造成顶底黑边 */
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    self.rootVC = [RootViewController new];
    UIColor *wine = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
    self.rootVC.view.backgroundColor = wine;
    self.window.backgroundColor = wine;
    self.window.rootViewController = self.rootVC;
    __weak AppDelegate *weakSelf = self;
    self.rootVC.onLayout = ^{
        AppDelegate *strong = weakSelf;
        if (!strong || !strong.webView) return;
        /* 始终铺满物理屏幕，避免顶/底露出黑条 */
        CGRect screen = UIScreen.mainScreen.bounds;
        strong.window.frame = screen;
        strong.rootVC.view.frame = screen;
        strong.webView.frame = screen;
        if (strong.splashView) strong.splashView.frame = screen;
        int sat = (int)lround([strong safeTop]);
        int sab = (int)lround([strong safeBottom]);
        NSString *js = [NSString stringWithFormat:
            @"document.documentElement.style.setProperty('--sat','%dpx');"
            "document.documentElement.style.setProperty('--sab','%dpx');"
            "document.documentElement.style.backgroundColor='#5c0000';"
            "if(document.body){document.body.style.backgroundColor=document.body.style.backgroundColor||'#5c0000';}",
            sat, sab];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self mountWebView];
        [self setupAndShowSplash];
    });
    return YES;
}

- (UIImage *)loadBundledSplashImage {
    NSBundle *bundle = [NSBundle mainBundle];
    NSArray *paths = @[
        [bundle pathForResource:@"splash" ofType:@"png"],
        [bundle pathForResource:@"splash" ofType:@"png" inDirectory:@"www"],
        [[[bundle resourcePath] stringByAppendingPathComponent:@"splash.png"] copy],
        [[[bundle resourcePath] stringByAppendingPathComponent:@"www/splash.png"] copy],
    ];
    for (NSString *path in paths) {
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) return img;
        }
    }
    return nil;
}

- (void)setupAndShowSplash {
    if (self.splashView || self.splashFinished) return;
    UIView *host = self.rootVC.view;
    CGRect full = UIScreen.mainScreen.bounds;

    UIView *panel = [[UIView alloc] initWithFrame:full];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.backgroundColor = [UIColor colorWithRed:0.05 green:0.01 blue:0.01 alpha:1];

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    UIImage *img = [self loadBundledSplashImage];
    if (img) {
        imageView.image = img;
    } else {
        imageView.backgroundColor = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
    }
    [panel addSubview:imageView];

    CGFloat topPad = 20;
    if (@available(iOS 11.0, *)) {
        topPad = MAX(20, host.safeAreaInsets.top + 12);
    }
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(full.size.width - 68, topPad, 48, 48)];
    label.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor colorWithRed:0.83 green:0.69 blue:0.31 alpha:1];
    label.font = [UIFont boldSystemFontOfSize:18];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    label.layer.cornerRadius = 24;
    label.clipsToBounds = YES;
    self.splashSecondsLeft = 3;
    label.text = [NSString stringWithFormat:@"%ld", (long)self.splashSecondsLeft];
    [panel addSubview:label];

    [host addSubview:panel];
    self.splashView = panel;
    self.splashCountdownLabel = label;
    self.splashFinished = NO;

    [self.splashTimer invalidate];
    __weak AppDelegate *weakSelf = self;
    self.splashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        AppDelegate *strong = weakSelf;
        if (!strong) { [timer invalidate]; return; }
        strong.splashSecondsLeft -= 1;
        if (strong.splashSecondsLeft <= 0) {
            [timer invalidate];
            [strong finishSplash];
        } else {
            strong.splashCountdownLabel.text = [NSString stringWithFormat:@"%ld", (long)strong.splashSecondsLeft];
        }
    }];
}

- (void)finishSplash {
    if (self.splashFinished) return;
    self.splashFinished = YES;
    [self.splashTimer invalidate];
    self.splashTimer = nil;
    UIView *panel = self.splashView;
    self.splashView = nil;
    self.splashCountdownLabel = nil;
    if (!panel) return;
    [UIView animateWithDuration:0.25 animations:^{
        panel.alpha = 0;
    } completion:^(BOOL finished) {
        [panel removeFromSuperview];
    }];
}

- (void)mountWebView {
    @try {
        NSDictionary *cfg = LoadRuntimeConfig();
        NSString *entry = cfg[@"assets_entry"] ?: @"index.html";
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
            "getUDID:function(){return call('getUDID');},"
            "getUdid:function(){return call('getUDID');},"
            "getVendorId:function(){return call('getVendorId');},"
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
            "try{localStorage.setItem('insulation_udid',%@);}catch(eU){}"
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
            "window.__INSULATION_DEVICE_ID__=%@;"
            "window.__INSULATION_UDID__=%@;"
            /* iOS：用工天 app-shell 外壳（与安卓一致）；播放器挂外壳，业务页在 iframe */
            "window.__BAOWEN_IOS_NO_APP_SHELL__=false;"
            "}catch(e){}})();",
            JSONString(deviceId), JSONString(deviceId),
            JSONString(insApi), JSONString(insApi), JSONString(insApi),
            JSONString(gtApi), JSONString(gtApi),
            JSONString(deviceId), JSONString(deviceId)];

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
            "r.classList.add('site-bg-ready','site-ui-ready','gongtian-native-app','page-bg-active');"
            "r.classList.remove('page-bg-pending','page-bg-pending-shell','shell-frame-cover-visible','shell-frame-navigating','user-theme-pending');"
            "if(document.body&&!r.classList.contains('auth-route')){"
            "var bu;try{bu=new URL('beijingtu.png',location.href).href;}catch(eBu){bu='beijingtu.png';}"
            "var bgi=\"url('\"+String(bu).replace(/'/g,'%27')+\"')\";"
            "document.body.style.setProperty('opacity','1','important');"
            "document.body.style.setProperty('visibility','visible','important');"
            "document.body.style.setProperty('background-image','none','important');"
            "document.body.style.setProperty('background-color','transparent','important');"
            "document.body.classList.add('page-fixed-bg-active');"
            "var layer=document.getElementById('pageFixedBg');"
            "if(!layer){layer=document.createElement('div');layer.id='pageFixedBg';"
            "layer.setAttribute('aria-hidden','true');r.insertBefore(layer,r.firstChild);}"
            "layer.classList.add('is-painted');"
            "layer.style.setProperty('position','fixed','important');"
            "layer.style.setProperty('top','0','important');"
            "layer.style.setProperty('left','0','important');"
            "layer.style.setProperty('right','0','important');"
            "layer.style.setProperty('bottom','0','important');"
            "layer.style.setProperty('width','100%','important');"
            "layer.style.setProperty('height','100%','important');"
            "layer.style.setProperty('z-index','0','important');"
            "layer.style.setProperty('transform','none','important');"
            "layer.style.setProperty('display','block','important');"
            "layer.style.setProperty('opacity','1','important');"
            "layer.style.setProperty('visibility','visible','important');"
            "layer.style.setProperty('background-image',bgi,'important');"
            "layer.style.setProperty('background-size','cover','important');"
            "layer.style.setProperty('background-position','center center','important');"
            "layer.style.setProperty('background-repeat','no-repeat','important');"
            "layer.style.setProperty('pointer-events','none','important');"
            "r.style.setProperty('background-image','none','important');"
            "}"
            "document.querySelectorAll('body > main,#mainNav,.marquee-bar,body > footer').forEach(function(el){"
            "el.style.setProperty('opacity','1','important');"
            "el.style.setProperty('visibility','visible','important');"
            "el.style.setProperty('display','block','important');});"
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
            /* 铺满：用酒红底，避免顶底露出纯黑 */
            "'html.baowen-native-app:not(.app-shell-page) body:not(.auth-page){background-color:#5c0000!important;"
            "+'-webkit-text-size-adjust:100%!important;text-size-adjust:100%!important;}'"
            "+'html.gongtian-native-app,html.gongtian-native-app body{background-color:#1a0505!important;"
            "+'min-height:100%!important;min-height:-webkit-fill-available!important;}'"
            "+'html.gongtian-native-app #pageFixedBg{position:fixed!important;inset:0!important;top:0!important;"
            "+'z-index:0!important;pointer-events:none!important;}'"
            /* 导航顶边贴状态栏：禁止 safe-area 顶距（会留出黑缝） */
            "+'html.gongtian-native-app #mainNav{padding-top:0!important;margin-top:0!important;"
            "+'top:0!important;box-sizing:border-box!important;"
            "+'background-color:rgba(92,0,0,0.96)!important;}'"
            "+'html.gongtian-native-app #mainNav > div,html.gongtian-native-app #mainNav .max-w-7xl{"
            "+'padding-top:0!important;box-sizing:border-box!important;}'"
            "+'html.gongtian-native-app #mainNav.bg-luxury-blur{background-color:rgba(92,0,0,0.96)!important;}'"
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
            "+'html.gongtian-native-app #mainNav,html.site-bg-ready #mainNav,' "
            "+'html.gongtian-native-app .marquee-bar,html.site-bg-ready .marquee-bar{' "
            "+'opacity:1!important;visibility:visible!important;display:block!important;}'"
            /* 覆盖 page-boot-guard 的 display:none，即使仍卡在 pending */
            "+'html.gongtian-native-app.page-bg-pending body>main,' "
            "+'html.gongtian-native-app.page-bg-pending body>footer,' "
            "+'html.gongtian-native-app.page-bg-pending #mainNav,' "
            "+'html.gongtian-native-app.page-bg-pending .marquee-bar{' "
            "+'opacity:1!important;visibility:visible!important;display:block!important;pointer-events:auto!important;}'"
            "+'html.gongtian-native-app,html.gongtian-native-app body{overscroll-behavior:none!important;overscroll-behavior-y:none!important;}'"
            "+'html.gongtian-native-app.site-bg-ready:not(.auth-route) body.page-fixed-bg-active.bg-cover,' "
            "+'html.gongtian-native-app.site-bg-ready:not(.auth-route) body.bg-cover,' "
            "+'html.gongtian-native-app:not(.auth-route) body.min-h-screen,' "
            "+'html.gongtian-native-app.user-theme-pending:not(.auth-route) body{' "
            "+'background-image:none!important;background-color:transparent!important;}'"
            "+'html.gongtian-native-app #pageFixedBg,html.gongtian-native-app.site-bg-ready #pageFixedBg.is-painted{' "
            "+'position:fixed!important;top:0!important;left:0!important;right:0!important;bottom:0!important;' "
            "+'width:100%!important;height:100%!important;' "
            "+'display:block!important;opacity:1!important;visibility:visible!important;' "
            "+'background-image:url(beijingtu.png)!important;background-size:cover!important;background-position:center center!important;' "
            "+'background-repeat:no-repeat!important;z-index:0!important;pointer-events:none!important;transform:none!important;}'"
            "+'html.gongtian-native-app .settings-tab-nav{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:.5rem!important;}'"
            "+'html.gongtian-native-app #syncServerTabBtn{grid-column:1/2!important;justify-self:start!important;white-space:nowrap!important;width:auto!important;}'"
            "+'html>#syncModeModal,html>#passwordModal,body>#syncModeModal,body>#passwordModal{' "
            "+'position:fixed!important;inset:0!important;z-index:2147483646!important;pointer-events:auto!important;transform:none!important;}'"
            "+'html>#syncModeModal.gt-modal-open,html>#passwordModal.gt-modal-open,' "
            "+'body>#syncModeModal.gt-modal-open,body>#passwordModal.gt-modal-open{display:flex!important;}'"
            "+'html.gongtian-native-app #mainNav{position:sticky!important;top:0!important;z-index:500!important;}'"
            "+'html.gongtian-native-app,html.gongtian-native-app body{background-color:#1a0505!important;}'"
            "+'html.gongtian-native-app #pageFixedBg{min-height:100dvh!important;height:100dvh!important;}'"
            "+'html.gongtian-native-app body>footer{margin-bottom:0!important;"
            "+'padding-bottom:max(1.25rem,env(safe-area-inset-bottom,0px))!important;"
            "+'background-color:rgba(92,0,0,0.96)!important;}'"
            "+'html.gongtian-native-app body>main{padding-bottom:calc(96px + env(safe-area-inset-bottom,0px))!important;}'"
            "+'input,textarea,select,[contenteditable=\"true\"]{-webkit-user-select:text!important;"
            "+'user-select:text!important;pointer-events:auto!important;-webkit-touch-callout:default!important;"
            "+'touch-action:manipulation!important;font-size:16px!important;}'"
            "+'input:focus,textarea:focus,select:focus{outline:none;-webkit-user-select:text!important;}'"
            /* 工天图表：隐藏空 canvas，露出 HTML 柱状图 */
            "+'.settlement-chart-panel canvas{display:none!important;visibility:hidden!important;"
            "+'width:0!important;height:0!important;pointer-events:none!important;}'"
            "+'.settlement-chart-panel .gt-html-chart{display:block!important;visibility:visible!important;"
            "+'opacity:1!important;position:relative!important;z-index:6!important;}'"
            "+'#dualFloatFab:not(.dual-hidden){display:flex!important;opacity:1!important;visibility:visible!important;"
            "+'z-index:2147483000!important;width:40px!important;height:40px!important;"
            "+'align-items:center!important;justify-content:center!important;}'"
            "+'#dualFloatFab .dual-fab-bars{display:flex!important;flex-direction:column!important;"
            "+'align-items:center!important;justify-content:center!important;gap:3px!important;"
            "+'width:18px!important;height:14px!important;}'"
            "+'#dualFloatFab .dual-fab-bars span{display:block!important;width:18px!important;height:2px!important;"
            "+'min-height:2px!important;margin:0!important;padding:0!important;border:0!important;"
            "+'border-radius:2px!important;background:#f5d488!important;}'"
            "+'html.baowen-native-app body.tab-embedded{padding-bottom:0!important;}'"
            "+'#dualFloatRestore.show{z-index:2147483000!important;}'"
            "+'#dualFloatMask,#dualFloatPanel{z-index:2147483001!important;}'"
            "+'#dualExitConfirm,#dualFloatTip{z-index:2147483002!important;}'"
            "+'.insulation-modal-root,.insulation-guard-overlay{z-index:2147483600!important;}'"
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
            /* 登录页：固定壳铺满，酒红底，避免上下黑边/键盘顶起 */
            "+'html.baowen-native-login,html.baowen-native-login body{' "
            "+'position:fixed!important;inset:0!important;width:100%!important;height:100%!important;"
            "+'min-height:100%!important;min-height:-webkit-fill-available!important;"
            "+'overflow:hidden!important;background:#5c0000!important;background-color:#5c0000!important;}'"
            "+'html.baowen-native-login body.page-module::before,html.baowen-native-login .page-bg-overlay{' "
            "+'position:fixed!important;inset:0!important;width:100%!important;height:100%!important;"
            "+'min-height:100%!important;background-color:#5c0000!important;}'"
            "+'html.baowen-native-app .auth-wrap{height:100%!important;max-height:100%!important;overflow-y:auto!important;"
            "+'-webkit-overflow-scrolling:touch;background:transparent!important;"
            /* 顶部不加 safe-area，红底顶到状态栏顶部 */
            "+'padding-top:1rem!important;"
            "+'padding-bottom:calc(1rem + env(safe-area-inset-bottom,var(--sab,0px)))!important;box-sizing:border-box!important;}';"
            "(document.head||document.documentElement).appendChild(css);}"
            "if(!isGtShell&&!isGtPath&&isBaowenPath&&!document.querySelector('.shell'))document.documentElement.classList.add('baowen-native-scroll');"
            "else document.documentElement.classList.remove('baowen-native-scroll');"
            "if(document.querySelector('.auth-wrap'))document.documentElement.classList.add('baowen-native-login');"
            "else document.documentElement.classList.remove('baowen-native-login');"
            "}"
            "applyScale();"
            "window.addEventListener('resize',applyScale,{passive:true});"
            /* 工天输入框：触摸后强制 focus，确保系统键盘弹出 */
            "if(!window.__baowenIosKeyboardFocus){window.__baowenIosKeyboardFocus=true;"
            "function __bwFocusField(t){if(!t||t.disabled||t.readOnly)return;"
            "var tag=(t.tagName||'').toUpperCase();"
            "if(tag!=='INPUT'&&tag!=='TEXTAREA'&&tag!=='SELECT'&&!t.isContentEditable)return;"
            "try{t.focus({preventScroll:false});}catch(eF){try{t.focus();}catch(eF2){}}}"
            "document.addEventListener('touchend',function(ev){"
            "var t=ev.target;if(!t)return;"
            "if(t.closest){var f=t.closest('input,textarea,select,[contenteditable=\"true\"]');if(f)t=f;}"
            "setTimeout(function(){__bwFocusField(t);},0);"
            "},true);"
            "document.addEventListener('click',function(ev){"
            "var t=ev.target;if(!t)return;"
            "if(t.closest){var f=t.closest('input,textarea,select,[contenteditable=\"true\"]');if(f)t=f;}"
            "__bwFocusField(t);"
            "},true);}"
            "}catch(e){}})();";

        /* 仅主 frame：顶栏安全区 + iframe 支付 URL 中转 */
        NSString *shellLayoutJs = [NSString stringWithFormat:
            @"(function(){try{"
            "document.documentElement.style.setProperty('--sat','%dpx');"
            "document.documentElement.style.setProperty('--sab','%dpx');"
            "if(!document.getElementById('baowen-native-safearea')){"
            "var css=document.createElement('style');css.id='baowen-native-safearea';"
            "css.textContent='html.baowen-native-app,html.baowen-native-app body{background:#5c0000!important;height:100%%;padding-top:0!important;margin:0!important;}'"
            "+'html.baowen-native-app .shell{position:fixed;inset:0;height:100%%;width:100%%;"
            "+'min-height:100%%;min-height:-webkit-fill-available;background:#5c0000!important;padding-top:0!important;}'"
            /* 顶栏贴顶：容器 padding=0；内层用 --app-sat（由 safe-area-adapt.js 计算，防云手机双倍） */
            "+'html.baowen-native-app .nav-container{padding-top:0!important;margin-top:0!important;top:0!important;height:auto;'"
            "+'min-height:52px;box-sizing:border-box;'"
            "+'background:linear-gradient(180deg,rgba(139,0,0,.92),rgba(178,34,34,.88),rgba(139,0,0,.92))!important;}'"
            "+'html.baowen-native-app .nav-container .nav-content{padding-top:0!important;"
            "+'min-height:52px;box-sizing:border-box;}'"
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
        CGRect full = UIScreen.mainScreen.bounds;
        host.frame = full;
        self.webView = [[WKWebView alloc] initWithFrame:full configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.UIDelegate = self;
        self.webView.navigationDelegate = self;
        self.webView.opaque = NO;
        UIColor *wine = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
        self.webView.backgroundColor = wine;
        self.webView.scrollView.backgroundColor = wine;
        if (@available(iOS 11.0, *)) {
            self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        /* 默认允许滚动；全程禁橡皮筋，避免顶底被拉开 */
        self.webView.scrollView.scrollEnabled = YES;
        self.webView.scrollView.bounces = NO;
        self.webView.scrollView.alwaysBounceVertical = NO;
        self.webView.scrollView.alwaysBounceHorizontal = NO;
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
        [self updateScrollForURL:[NSURL fileURLWithPath:pagePath]];
        [self.webView loadFileURL:[NSURL fileURLWithPath:pagePath]
            allowingReadAccessToURL:[NSURL fileURLWithPath:wwwDir isDirectory:YES]];
    } @catch (NSException *ex) {
        NSLog(@"BaoWen webview exception: %@", ex);
    }
}

- (void)updateScrollForURL:(NSURL *)url {
    NSString *path = (url.path ?: @"").lowercaseString;
    NSString *abs = (url.absoluteString ?: @"").lowercaseString;
    BOOL isBaowenShell = [path containsString:@"/baowen/shell.html"] || [abs containsString:@"/baowen/shell.html"];
    BOOL isGtShell = [path containsString:@"/gongtian/app-shell.html"] || [abs containsString:@"/gongtian/app-shell.html"];
    BOOL lockScroll = isBaowenShell || isGtShell;
    self.webView.scrollView.scrollEnabled = !lockScroll;
    /* 选择页/工天业务页都禁止下拉回弹，顶底不被拉开 */
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.alwaysBounceVertical = NO;
    self.webView.scrollView.alwaysBounceHorizontal = NO;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self updateScrollForURL:webView.URL];
    int sat = (int)lround([self safeTop]);
    int sab = (int)lround([self safeBottom]);
    NSString *js = [NSString stringWithFormat:
        @"document.documentElement.style.setProperty('--sat','%dpx');"
        "document.documentElement.style.setProperty('--sab','%dpx');"
        "document.documentElement.style.setProperty('--app-sat','%dpx');"
        "document.documentElement.style.setProperty('--app-sab','%dpx');"
        "var href=String(location.href||'');"
        "if(/\\/baowen\\//i.test(href))"
        "document.documentElement.classList.add('baowen-native-app');"
        "else document.documentElement.classList.remove('baowen-native-app');"
        "try{if(typeof window.updatePriceTagTornEdges==='function')window.updatePriceTagTornEdges();}catch(e){}"
        "if(/\\/gongtian\\//i.test(href)&&!/app-shell\\.html/i.test(href)){(function(){"
        "var r=document.documentElement;"
        "r.classList.add('site-bg-ready','site-ui-ready','gongtian-native-app');"
        "r.classList.remove('page-bg-pending','page-bg-pending-shell');"
        "if(document.body){document.body.style.setProperty('opacity','1','important');"
        "document.body.style.setProperty('visibility','visible','important');}"
        "document.querySelectorAll('body>main,#mainNav,.marquee-bar,body>footer,#themeOverlay').forEach(function(el){"
        "el.style.setProperty('opacity','1','important');"
        "el.style.setProperty('visibility','visible','important');"
        "if(el.tagName==='NAV'||el.id==='mainNav'){el.style.setProperty('display','block','important');}"
        "else if(el.tagName==='MAIN'||el.tagName==='FOOTER'){el.style.setProperty('display','block','important');}"
        "else{el.style.setProperty('display','block','important');}"
        "});})();}",
        sat, sab, sat, sab];
    /* 强制导航贴顶：清掉容器顶距；内层由 --app-sat 避让；触发网页自适应 */
    NSString *flushNav = @"try{var n=document.getElementById('mainNav');"
        "if(n){n.style.setProperty('padding-top','0','important');"
        "n.style.setProperty('margin-top','0','important');"
        "n.style.setProperty('top','0','important');}"
        "var nc=document.querySelector('.nav-container');"
        "if(nc){nc.style.setProperty('padding-top','0','important');"
        "nc.style.setProperty('margin-top','0','important');"
        "nc.style.setProperty('top','0','important');}"
        "document.documentElement.style.setProperty('padding-top','0','important');"
        "if(document.body){document.body.style.setProperty('padding-top','0','important');"
        "document.body.style.setProperty('margin-top','0','important');}"
        "try{if(window.__SAFE_AREA_ADAPT_READY__){"
        "var ev=document.createEvent('Event');ev.initEvent('resize',true,true);window.dispatchEvent(ev);}"
        "}catch(eA){}}catch(e){}";
    js = [js stringByAppendingString:flushNav];
    [webView evaluateJavaScript:js completionHandler:nil];
    self.webView.scrollView.contentInset = UIEdgeInsetsZero;
    self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
}

- (void)onKeyboardFrameChange:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.webView.scrollView.contentInset = UIEdgeInsetsZero;
        self.webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
        /* 始终保持酒红底，避免透明后底部露黑条；键盘由系统正常弹出 */
        UIColor *wine = [UIColor colorWithRed:0.36 green:0.0 blue:0.0 alpha:1];
        self.webView.backgroundColor = wine;
        self.webView.scrollView.backgroundColor = wine;
        if (self.rootVC.view) self.rootVC.view.backgroundColor = wine;
    });
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.targetFrame.isMainFrame) {
        [self updateScrollForURL:navigationAction.request.URL];
    }
    NSURL *url = navigationAction.request.URL;
    if (!url) { decisionHandler(WKNavigationActionPolicyAllow); return; }
    NSString *abs = (url.absoluteString ?: @"").lowercaseString;
    NSString *scheme = (url.scheme ?: @"").lowercaseString;

    /* 快捷菜单退出：baowen-app://exit */
    if ([scheme isEqualToString:@"baowen-app"] || [abs hasPrefix:@"baowen-app://exit"]) {
        [self handleBridgeMethod:@"exitApp" args:@[]];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

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
    (void)webView; (void)frame;
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
    /* 普通 prompt 必须弹原生输入框；静默 completion 会导致网页“点了没反应” */
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES;
        tf.text = defaultText ?: @"";
        tf.placeholder = @"请输入密码";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        completionHandler(nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UITextField *tf = alert.textFields.firstObject;
        completionHandler(tf.text ?: @"");
    }]];
    [self.rootVC presentViewController:alert animated:YES completion:nil];
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
