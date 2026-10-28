#import "ForgeRunner.h"

static NSString *const kForgeBin = @"/var/jb/usr/bin/amap-forge";
static NSString *const kForgeLog = @"/var/jb/var/log/amap-forge.log";

@implementation ForgeRunner

+ (NSString *)runShell:(NSString *)cmd {
    NSMutableString *out = [NSMutableString string];
    @try {
        NSTask *t = [[NSTask alloc] init];
        t.launchPath = @"/var/jb/usr/bin/bash";
        t.arguments = @[@"-lc", cmd];
        NSPipe *pipe = [NSPipe pipe];
        t.standardOutput = pipe;
        t.standardError = pipe;
        [t launch];
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [t waitUntilExit];
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s) [out appendString:s];
    } @catch (NSException *e) {
        [out appendFormat:@"异常: %@", e.reason];
    }
    return out;
}

+ (NSString *)startWithID:(NSString *)utdid {
    NSString *arg = utdid.length > 0 ? [NSString stringWithFormat:@" %@", utdid] : @"";
    return [self runShell:[NSString stringWithFormat:@"%@ on%@", kForgeBin, arg]];
}

+ (NSString *)stop {
    return [self runShell:[NSString stringWithFormat:@"%@ off", kForgeBin]];
}

+ (NSString *)status {
    return [self runShell:[NSString stringWithFormat:@"%@ status", kForgeBin]];
}

+ (NSString *)randomID {
    NSString *cs = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:22];
    for (int i = 0; i < 22; i++) {
        [s appendFormat:@"%C", [cs characterAtIndex:arc4random_uniform((uint32_t)cs.length)]];
    }
    return s;
}

+ (BOOL)isRunning {
    NSString *out = [self runShell:@"pgrep -x frida >/dev/null 2>&1 && echo YES || echo NO"];
    return [out containsString:@"YES"];
}

+ (NSString *)currentID {
    NSString *log = [NSString stringWithContentsOfFile:kForgeLog
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
    if (!log) return nil;
    NSRange r = [log rangeOfString:@"forged UTDID="];
    if (r.location == NSNotFound) return nil;
    NSString *tail = [log substringFromIndex:r.location + r.length];
    NSCharacterSet *stop = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSRange end = [tail rangeOfCharacterFromSet:stop];
    if (end.location == NSNotFound) return tail;
    return [tail substringToIndex:end.location];
}

+ (NSInteger)servedCount {
    NSString *log = [NSString stringWithContentsOfFile:kForgeLog
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
    if (!log) return 0;
    NSInteger n = 0, pos = 0;
    while (pos < (NSInteger)log.length) {
        NSRange r = [log rangeOfString:@"'kind': 'served'" options:0
                                 range:NSMakeRange(pos, log.length - pos)];
        if (r.location == NSNotFound) break;
        n++;
        pos = r.location + r.length;
    }
    return n;
}

@end
