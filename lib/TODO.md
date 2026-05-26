### 调试之前，如果动过kotlin源代码，请在终端执行：
```
cd backend_kotlin
./gradlew buildFatJar
```

### 请下载nuget.exe，将它放置于C:/Windows/System32下，
否则Flutter的GPS插件将无法编译。

### 打包 Windows（自动 build fatjar + 复制 + build flutter）
```
.\build_package.ps1 -Target windows
```
打包好的文件会在：
```
build\windows\x64\runner\Release\
├── 星火学伴.exe
└── backend\ai_agent_backend.jar
```
### 打包 Android
```
.\build_package.ps1 -Target android
```
打包好的文件会在：
```
build\app\outputs\flutter-apk\
└── app-release.apk
```
### 打包 Linux (Windows端无法打包Linux程序！)
```
.\build_package.ps1 -Target linux
```
打包好的文件会在：
```
build\linux\x64\release\bundle\
├── 星火学伴  (ELF 二进制)
└── backend/ai_agent_backend.jar
```
### 打包 iOS
```
.\build_package.ps1 -Target ios
```
打包好的文件会在：
```
build\macos\Build\Products\Release\
└── 星火学伴.app
    └── Contents/Resources/backend/ai_agent_backend.jar  (内嵌在 .app 包中)
```
### 打包 macOS
```
.\build_package.ps1 -Target macos
```
打包好的文件会在：
```
build\ios\iphoneos\
└── Runner.app
```
### 打包桌面端（Windows/Linux/MacOS）
```
.\build_package.ps1 -Target desktop
```
打包好的文件参见上面三平台的输出目录

### 所有五平台一起打包
```
.\build_package.ps1 -Target all
```
