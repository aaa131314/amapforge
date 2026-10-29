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

/// 数据体积
+ (NSString *)dataSize;

/// 生成随机 22 位 ID
+ (NSString *)randomID;

/// 当前是否在注入
+ (BOOL)isRunning;

/// 当前伪造 ID
+ (nullable NSString *)currentID;

/// 已服务次数
+ (NSInteger)servedCount;

@end

NS_ASSUME_NONNULL_END
