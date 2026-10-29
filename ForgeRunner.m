#import "ForgeRunner.h"

// 直连本机 frida-server（完全离线）
#include "frida-core.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static NSString *const kAppBundle = @"com.autonavi.amap";
static NSString *const kRemoteAddr = @"127.0.0.1:27042";

// ---- GLib 主循环（收 send() 消息）----
static NSMutableString *gCurrentBuf = nil;
static NSString *gCurrentWaitFor = nil;
static BOOL *gCurrentDone = NULL;

static void on_script_message(FridaScript *script, const gchar *message,
                              GBytes *data, gpointer user_data) {
    if (!message) return;
    @autoreleasepool {
        NSString *m = [NSString stringWithUTF8String:message];
        if (gCurrentBuf && m) [gCurrentBuf appendString:m];
        if (gCurrentWaitFor && gCurrentBuf &&
            [gCurrentBuf containsString:gCurrentWaitFor] && gCurrentDone) {
            *gCurrentDone = YES;
        }
    }
}

@implementation ForgeRunner

#pragma mark - socket 预检

+ (NSString *)tcpProbe:(NSString *)host port:(int)port timeoutMs:(int)ms {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return [NSString stringWithFormat:@"socket()失败 errno=%d", errno];
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = inet_addr(host.UTF8String);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc < 0 && errno != EINPROGRESS) {
        int e = errno; close(fd);
        return [NSString stringWithFormat:@"connect失败 errno=%d (%s)", e, strerror(e)];
    }
    fd_set wfds; FD_ZERO(&wfds); FD_SET(fd, &wfds);
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (rc == 0) { close(fd); return [NSString stringWithFormat:@"connect超时%dms", ms]; }
    if (rc < 0) { int e = errno; close(fd); return [NSString stringWithFormat:@"select失败 errno=%d", e]; }
    int soerr = 0; socklen_t len = sizeof(soerr);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &len);
    close(fd);
    if (soerr != 0) return [NSString stringWithFormat:@"SO_ERROR=%d (%s)", soerr, strerror(soerr)];
    return [NSString stringWithFormat:@"TCP OK %@:%d", host, port];
}

#pragma mark - helpers

+ (NSString *)jsSourceNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"js"];
    if (!p) return nil;
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
}

+ (void)runOnFridaThread:(void (^)(void))block {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("amapforge.frida", DISPATCH_QUEUE_SERIAL);
        frida_init();
    });
    dispatch_async(q, block);
}

+ (NSString *)errStr:(GError *)e {
    if (!e) return @"";
    NSString *s = [NSString stringWithFormat:@"%s", e->message];
    g_error_free(e);
    return s;
}

+ (NSString *)execScript:(NSString *)jsName
               onProcess:(NSString *)procName
                 waitFor:(NSString *)waitFor
              timeoutSec:(int)timeoutSec {
    NSString *js = [self jsSourceNamed:jsName];
    if (!js) return [NSString stringWithFormat:@"FAIL: 缺少 %@.js", jsName];

    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];

    // 关键：为本次调用创建私有的 GMainContext 并推为线程默认
    GMainContext *ctx = g_main_context_new();
    g_main_context_push_thread_default(ctx);

    __block NSMutableString *buf = [NSMutableString string];
    __block BOOL done = NO;

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        return [NSString stringWithFormat:@"FAIL: frida 连接失败\n%@", e];
    }

    FridaProcess *proc = frida_device_get_process_by_name_sync(
        dev, procName.UTF8String, NULL, NULL, &err);
    if (!proc) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        return [NSString stringWithFormat:@"FAIL: 进程 %@ 未运行\n%@", procName, e];
    }
    guint pid = frida_process_get_pid(proc);
    g_object_unref(proc);

    FridaSession *session = frida_device_attach_sync(dev, pid, NULL, NULL, &err);
    if (!session) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        return [NSString stringWithFormat:@"FAIL: attach %@ 失败 (pid %u)\n%@", procName, pid, e];
    }

    FridaScriptOptions *opts = frida_script_options_new();
    frida_script_options_set_name(opts, jsName.UTF8String);
    frida_script_options_set_runtime(opts, FRIDA_SCRIPT_RUNTIME_QJS);

    FridaScript *script = frida_session_create_script_sync(
        session, js.UTF8String, opts, NULL, &err);
    if (!script) {
        NSString *e = [self errStr:err];
        g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        return [NSString stringWithFormat:@"FAIL: 创建脚本失败\n%@", e];
    }

    // 消息回调（用 block 捕获 buf）
    void (^onMsg)(const gchar *) = ^(const gchar *message) {
        if (!message) return;
        NSString *m = [NSString stringWithUTF8String:message];
        if (m) [buf appendString:m];
        if ([buf containsString:waitFor]) done = YES;
    };
    __block void (^savedBlock)(const gchar *) = onMsg;

    // 用 libffi 风格的回调不方便，改用 C 函数 + 全局指针
    gCurrentBuf = buf;
    gCurrentWaitFor = waitFor;
    gCurrentDone = &done;
    g_signal_connect(script, "message", G_CALLBACK(on_script_message), NULL);

    frida_script_load_sync(script, NULL, &err);
    if (err) {
        NSString *e = [self errStr:err];
        gCurrentBuf = nil; gCurrentWaitFor = nil; gCurrentDone = NULL;
        g_object_unref(script); g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        g_main_context_pop_thread_default(ctx);
        g_main_context_unref(ctx);
        return [NSString stringWithFormat:@"FAIL: 加载脚本失败\n%@", e];
    }

    // 手动 pump 这个私有 context，直到出结果或超时
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSec];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            while (g_main_context_iteration(ctx, FALSE)) { }
            [NSThread sleepForTimeInterval:0.1];
        }
    }

    gCurrentBuf = nil; gCurrentWaitFor = nil; gCurrentDone = NULL;

    NSString *result = [buf copy];

    g_object_unref(script); g_object_unref(opts); g_object_unref(session);
    g_object_unref(dev); g_object_unref(mgr);

    g_main_context_pop_thread_default(ctx);
    g_main_context_unref(ctx);

    if (result.length) return result;
    return [NSString stringWithFormat:@"FAIL: 脚本无输出（pid %u，%.0fs 超时）", pid, (double)timeoutSec];
}

#pragma mark - 注入 UTDID

+ (NSString *)injectSync {
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida 连接失败\n%@", e];
    }

    FridaProcess *old = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    if (old) {
        frida_device_kill_sync(dev, frida_process_get_pid(old), NULL, &err);
        if (err) { g_error_free(err); err = NULL; }
        g_object_unref(old);
        [NSThread sleepForTimeInterval:1.0];
    }

    guint pid = frida_device_spawn_sync(dev, kAppBundle.UTF8String, NULL, NULL, &err);
    if (pid == 0) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: spawn 失败\n%@", e];
    }

    FridaSession *session = frida_device_attach_sync(dev, pid, NULL, NULL, &err);
    if (!session) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: attach 失败 (pid %u)\n%@", pid, e];
    }

    NSString *js = [self jsSourceNamed:@"forge_utdid"];
    if (!js) {
        g_object_unref(session); g_object_unref(dev); g_object_unref(mgr);
        return @"FAIL: 包内缺少 forge_utdid.js";
    }

    FridaScriptOptions *opts = frida_script_options_new();
    frida_script_options_set_name(opts, "forge");
    frida_script_options_set_runtime(opts, FRIDA_SCRIPT_RUNTIME_QJS);

    FridaScript *script = frida_session_create_script_sync(
        session, js.UTF8String, opts, NULL, &err);
    if (!script) {
        NSString *e = [self errStr:err];
        g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 创建脚本失败\n%@", e];
    }

    frida_script_load_sync(script, NULL, &err);
    if (err) {
        NSString *e = [self errStr:err];
        g_object_unref(script); g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 加载脚本失败\n%@", e];
    }

    frida_device_resume_sync(dev, pid, NULL, &err);
    if (err) { g_error_free(err); err = NULL; }
    [NSThread sleepForTimeInterval:2.0];

    g_object_unref(script); g_object_unref(opts); g_object_unref(session);
    g_object_unref(dev); g_object_unref(mgr);

    // 记录注入状态（供状态显示用，不依赖高德进程是否存活）
    NSString *forged = [self currentForgedID];
    if (!forged) {
        forged = [self randomID];
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"amapforge_injected"];
    [ud setObject:forged forKey:@"amapforge_utdid"];
    [ud setObject:[NSDate date] forKey:@"amapforge_inject_time"];
    [ud synchronize];

    return [NSString stringWithFormat:@"OK: 已注入 %@ (pid %u)\n设备 ID: %@", kAppBundle, pid, forged];
}

+ (NSString *)detachSync {
    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 连接失败\n%@", e];
    }
    FridaProcess *p = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    if (p) {
        frida_device_kill_sync(dev, frida_process_get_pid(p), NULL, &err);
        if (err) { g_error_free(err); err = NULL; }
        g_object_unref(p);
        g_object_unref(dev); g_object_unref(mgr);
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:NO forKey:@"amapforge_injected"];
        [ud removeObjectForKey:@"amapforge_utdid"];
        [ud synchronize];
        return @"OK: 高德已停止，恢复真实身份";
    }
    g_object_unref(dev); g_object_unref(mgr);
    return @"OK: 高德未运行";
}

+ (NSString *)probeSync {
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida 库连不上\nTCP: %@\nfrida: %@", tcp, e];
    }
    FridaProcess *p = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    NSString *s;
    if (p) {
        s = [NSString stringWithFormat:@"running pid %u | %@", frida_process_get_pid(p), tcp];
        g_object_unref(p);
    } else {
        s = [NSString stringWithFormat:@"idle | %@", tcp];
    }
    g_object_unref(dev); g_object_unref(mgr);
    return s;
}

#pragma mark - public

+ (NSString *)startWithID:(NSString *)utdid {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self injectSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)stop {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self detachSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)status {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self probeSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    return r;
}

+ (NSDictionary *)statusDict {
    // 1) 注入标记（本地记录，不依赖高德进程）
    BOOL injected = [self isInjected];
    NSString *forged = [self currentForgedID];

    // 2) frida 连通性（轻量）
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:2000];
    BOOL ok = [tcp hasPrefix:@"TCP OK"];

    // 3) 高德进程状态（附带的）
    NSString *proc = @"";
    if (ok) {
        GError *err = NULL;
        FridaDeviceManager *mgr = frida_device_manager_new();
        FridaDevice *dev = frida_device_manager_add_remote_device_sync(
            mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
        if (dev) {
            FridaProcess *p = frida_device_get_process_by_name_sync(
                dev, kAppBundle.UTF8String, NULL, NULL, NULL);
            if (p) {
                proc = [NSString stringWithFormat:@"pid %u", frida_process_get_pid(p)];
                g_object_unref(p);
            }
            g_object_unref(dev);
        } else if (err) {
            g_error_free(err);
        }
        g_object_unref(mgr);
    }

    return @{@"ok": @(ok),
             @"running": @(injected),
             @"utdid": forged ?: @"",
             @"proc": proc,
             @"tcp": tcp};
}

+ (NSString *)wipeData:(BOOL)deep {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSString *js = deep ? @"wipe_deep" : @"wipe_std";
    [self runOnFridaThread:^{
        r = [self execScript:js onProcess:@"SpringBoard"
                     waitFor:@"wipe_result" timeoutSec:90];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)dataSizeText {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{
        r = [self execScript:@"wipe_size" onProcess:@"SpringBoard"
                     waitFor:@"size_result" timeoutSec:60];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(70 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)dataSize {
    NSString *r = [self dataSizeText];
    NSRange hr = [r rangeOfString:@"'human': '"];
    if (hr.location == NSNotFound) return r;
    NSString *tail = [r substringFromIndex:hr.location + hr.length];
    NSRange end = [tail rangeOfString:@"'"];
    if (end.location == NSNotFound) return r;
    return [NSString stringWithFormat:@"数据体积：%@",
            [tail substringToIndex:end.location]];
}

+ (NSString *)randomID {
    NSString *cs = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:22];
    for (int i = 0; i < 22; i++) {
        [s appendFormat:@"%C", [cs characterAtIndex:arc4random_uniform((uint32_t)cs.length)]];
    }
    return s;
}

+ (BOOL)isRunning { return [[self statusDict][@"running"] boolValue]; }
+ (NSString *)currentID { return [self statusDict][@"utdid"]; }
+ (NSInteger)servedCount { return 0; }

@end
