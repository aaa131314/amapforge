#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ForgeRunner : NSObject

/// 换设备身份（伪造 UTDID 并重启高德）
+ (NSString *)startWithID:(nullable NSString *)utdid;

/// 停止注入
+ (NSString *)stop;

/// 查看状态（字符串）
+ (NSString *)status;

/// 一次拿全部状态 {running, utdid, served}
+ (NSDictionary *)statusDict;

/// 清理高德数据（deep=YES 连离线地图一起删）
+ (NSString *)wipeData:(BOOL)deep;

/// 数据体积（简短）
+ (NSString *)dataSize;

/// 数据体积（原始输出）
+ (NSString *)dataSizeText;

/// 连通测试（TCP + frida）
+ (NSString *)connectTest;

/// 当前服务器地址
+ (NSString *)serverAddr;

/// 设置服务器地址（持久化）
+ (BOOL)setServerAddr:(NSString *)addr;

/// 生成随机 22 位 ID
+ (NSString *)randomID;

/// 当前是否在注入
+ (BOOL)isRunning;

/// 当前伪造 ID
+ (nullable NSString *)currentID;

/// 已服务次数
+ (NSInteger)servedCount;

/// 已伪造的 UTDID
+ (nullable NSString *)currentForgedID;

/// 是否处于注入状态
+ (BOOL)isInjected;

@end

NS_ASSUME_NONNULL_END
