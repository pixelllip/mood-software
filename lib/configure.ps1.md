## Configure.ps1使用说明

在项目根目录 ai_agent 下执行终端命令：

### 交互模式（推荐）
```
./configure.ps1
```
运行后会显示当前所有平台配置总览，然后通过菜单选择要修改的项目。

### 快速非交互模式
```
# 只改版本号
.\configure.ps1 -SetVersion 2.0.0+1
# 统一改各平台应用名称
.\configure.ps1 -SetAppName "我的应用"
```

### 脚本功能覆盖

|菜单	|功能	|修改的文件|
|---|---|---|
|1 版本号	|修改应用版本	|pubspec.yaml|
|2 应用名称	|统一修改所有平台显示名	|iOS Info.plist / macOS AppInfo.xcconfig / Windows Runner.rc / Web manifest & index.html|
|3 Android 配置	|修改 appId/namespace/SDK 版本	|build.gradle.kts|
|4 Android 签名	|配置 release keystore (storeFile/password/alias)	|build.gradle.kts + 生成 android/key.properties|
|5 iOS 显示名称	|修改 iOS 应用名	|Info.plist|
|6 iOS Bundle ID	|修改 iOS 包标识符	|Info.plist|
|7 macOS 配置	|修改产品名/Bundle ID/版权	|AppInfo.xcconfig|
|8 Windows 配置	|修改公司名/文件描述/产品名/文件名/版权	|Runner.rc|
|9 Linux 配置	|修改 APPLICATION_ID/BINARY_NAME	|CMakeLists.txt|
|10 Web 配置	|修改 name/short_name/description/title	|manifest.json + index.html|
|11 后端版本	|修改 Kotlin 后端版本号	|build.gradle.kts|
|12 Xcode 签名	|打开 Xcode 配置 iOS 签名 (Team/Provisioning)	|-|