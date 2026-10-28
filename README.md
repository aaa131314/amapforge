# AMap Forge — 高德设备身份切换 App

一个越狱 iOS App，桌面图标，点一下就给高德换一个全新设备身份（UTDID），绕过设备黑名单。

## 界面

```
┌──────────────────────────────┐
│ 设备身份                      │
├──────────────────────────────┤
│ 当前状态                      │
│ 🟢 正在伪造设备身份           │
│                              │
│ 设备 ID (UTDID)              │
│ H6G3JcMwkw4SZFweW8Tv9W       │
│                              │
│ 已服务 20 次读取              │
├──────────────────────────────┤
│ ╭──────────────────────────╮ │
│ │   换一个新设备身份         │ │  ← 主按钮
│ ╰──────────────────────────╯ │
│ ╭──────────────────────────╮ │
│ │ 停止（恢复真实身份）       │ │
│ ╰──────────────────────────╯ │
│ ╭──────────────────────────╮ │
│ │ 刷新状态                  │ │
│ ╰──────────────────────────╯ │
├──────────────────────────────┤
│ [日志输出区]                  │
└──────────────────────────────┘
```

## 依赖

运行时依赖已装的 `amap-poi` 插件（提供 `amap-forge` 命令）：

- `/var/jb/usr/bin/amap-forge`
- `/var/jb/usr/share/amap-poi/forge_utdid.js`

先装 `com.local.amappoi` ≥ 1.2.0。

## 云编译

不需要 Mac。用 GitHub Actions：

```bash
cd theos-app
git init
git add .
git commit -m "init"
git remote add origin https://github.com/<你的用户名>/amapforge.git
git push -u origin main
```

推上去后：

1. 打开 GitHub 仓库 → **Actions** 标签
2. 左侧选 **Build AMap Forge**
3. 点右侧 **Run workflow**
4. 等 3~5 分钟
5. 构建完成后在本页最下方 **Artifacts** 下载 `amapforge-deb`
6. 解压得到 `com.local.amapforge_1.0.0_iphoneos-arm64.deb`

## 安装到手机

把 deb 传到手机（AirDrop / Filza / 我这边也可以推）：

```
dpkg -i --force-depends com.local.amapforge_1.0.0_iphoneos-arm64.deb
```

或者用 Filza 点开 deb 安装。

装完回桌面，就有 **「设备身份」** 图标。

## 使用

1. 点开 App
2. 点 **「换一个新设备身份」**
3. 等 5~8 秒（会自动关闭高德、重启并注入）
4. 状态变成 🟢，显示新的设备 ID
5. 打开高德，正常提报
6. 提报完回到这个 App，再点一次「换一个新设备身份」

## 原理

高德的设备标识是阿里 UT 的 `UTDID`，存在 `NSUserDefaults` 里，App 通过 `+[UTDevice utdid]` 读取。

这个 App 调用 `amap-forge`，后者用 Frida 在 App 启动时 hook `+[UTDevice utdid]`，每次返回一个随机生成的 22 位 ID。

高德服务端收到的 `tid` 就是伪造值，设备黑名单匹配不上。

## 已验证

| 项目 | 结果 |
|---|---|
| `tid` 替换 | ✅ 实测记录里写的是伪造 ID |
| 旧 ID 消失 | ✅ `OLD present: false` |
| App 稳定性 | ✅ 20 次读取无崩溃 |

## 源码结构

```
theos-app/
├── Makefile              # Theos 构建配置（rootless）
├── control               # deb 包元信息
├── Info.plist            # App 元信息
├── entitlements.plist    # 提权声明
├── main.m                # AppDelegate + 入口
├── RootViewController.h/.m   # 界面
├── ForgeRunner.h/.m      # 调用 amap-forge
└── .github/workflows/build.yml   # GitHub Actions 云编译
```
