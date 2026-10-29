#import "ForgeRunner.h"

// 直连本机 frida-server（完全离线，不需要电脑）
#include "frida-core.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static NSString *const kAppBundle = @"com.autonavi.amap";
static NSString *const kRemoteAddr = @"127.0.0.1:27042";

@implementation ForgeRunner

#pragma mark - 原始 socket 检查（判断是网络还是 frida 库的问题）

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
        int e = errno;
        close(fd);
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

+ (NSString *)jsSource {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"forge_utdid" ofType:@"js"];
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

#pragma mark - core

+ (NSString *)injectSync {
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) {
        return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];
    }

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida-server 不可达 %@\n%@", kRemoteAddr, e];
    }

    // 杀掉旧的高德进程
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
        g_object_unref(dev);
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: spawn 失败\n%@", e];
    }

    FridaSession *session = frida_device_attach_sync(dev, pid, NULL, NULL, &err);
    if (!session) {
        NSString *e = [self errStr:err];
        g_object_unref(dev);
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: attach 失败 (pid %u)\n%@", pid, e];
    }

    NSString *js = [self jsSource];
    if (!js) {
        g_object_unref(session);
        g_object_unref(dev);
        g_object_unref(mgr);
        return @"FAIL: 包内缺少 forge_utdid.js";
    }

    FridaScriptOptions *opts = frida_script_options_new();
    frida_script_options_set_name(opts, "forge");
    frida_script_options_set_runtime(opts, FRIDA_SCRIPT_RUNTIME_QJS);

    FridaScript *script = frida_session_create_script_sync(
        session, js.UTF8String, opts, NULL, &err);
    if (!script) {
        NSString *e = [self errStr:err];
        g_object_unref(opts);
        g_object_unref(session);
        g_object_unref(dev);
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 创建脚本失败\n%@", e];
    }

    frida_script_load_sync(script, NULL, &err);
    if (err) {
        NSString *e = [self errStr:err];
        g_object_unref(script);
        g_object_unref(opts);
        g_object_unref(session);
        g_object_unref(dev);
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 加载脚本失败\n%@", e];
    }

    frida_device_resume_sync(dev, pid, NULL, &err);
    if (err) { g_error_free(err); err = NULL; }

    [NSThread sleepForTimeInterval:2.0];

    g_object_unref(script);
    g_object_unref(opts);
    g_object_unref(session);
    g_object_unref(dev);
    g_object_unref(mgr);

    return [NSString stringWithFormat:@"OK: 已注入 %@ (pid %u)\n设备 ID 已替换", kAppBundle, pid];
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
        g_object_unref(dev);
        g_object_unref(mgr);
        return @"OK: 高德已停止，恢复真实身份";
    }
    g_object_unref(dev);
    g_object_unref(mgr);
    return @"OK: 高德未运行";
}

+ (NSString *)probeSync {
    // 先做原始 TCP 预检
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) {
        return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];
    }

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    // 用 ref 保持存活，避免 dispatch_after 里的 use-after-free
    GCancellable *cancel = g_cancellable_new();
    g_object_ref_sink(cancel);   // 取消浮引用，由下面 unref 平衡
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        g_cancellable_cancel(cancel);
        g_object_unref(cancel);   // 在回调里释放，此时已用完
    });
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, cancel, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida-server 不可达 (%@)\n%@", kRemoteAddr, e];
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
    g_object_unref(dev);
    g_object_unref(mgr);
    return s;
}

#pragma mark - public

+ (NSString *)startWithID:(NSString *)utdid {
    __block NSString *result = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{
        result = [self injectSync];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)));
    return result;
}

+ (NSString *)stop {
    __block NSString *result = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{
        result = [self detachSync];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    return result;
}

+ (NSString *)status {
    __block NSString *result = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{
        result = [self probeSync];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    return result;
}

+ (NSDictionary *)statusDict {
    NSString *s = [self status];
    BOOL ok = ![s hasPrefix:@"FAIL"];
    BOOL running = [s containsString:@"running"];
    return @{@"ok": @(ok), @"running": @(running),
             @"utdid": running ? s : @"", @"served": @0};
}

+ (NSString *)wipeData:(BOOL)deep {
    return @"离线模式：清理请用 amap-wipe 命令\n（数据操作需要 root，App 内不做）";
}

+ (NSString *)dataSize {
    return @"离线模式不统计体积";
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
