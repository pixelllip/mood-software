### 调试之前，如果动过kotlin源代码，请在终端执行：
cd backend_kotlin

./gradlew buildFatJar

### 打包 Windows（自动 build fatjar + 复制 + build flutter）
.\build_package.ps1 -Target windows

### 打包 Android
.\build_package.ps1 -Target android

### 两个平台一起打包
.\build_package.ps1 -Target all