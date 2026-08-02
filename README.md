# QuoteWords

QuoteWords 是面向 Quote/0 296 x 152 黑白墨水屏的 Android 雅思词卡应用。应用每天先安排到期复习，再加入新词；手机负责选词、提醒、记录进度和生成墨水屏帧，用户确认后通过 BLE 发送到设备。

当前默认学习方案：

- 每天 09:00 提醒
- 每天 8 个新词，可在学习设置中继续增加
- 每日学习总上限 24 张，避免复习积压时无限增加任务
- 复习间隔为 10 分钟、1 天、3 天、7 天、14 天、30 天
- 词卡只保留单词、音标、精简释义、例句、词频和学习进度
- 按 6 个月备考周期设计；当前版本不包含考试日期倒计时

## 当前功能

- 从 [ISDC](https://isdc.pages.dev/) 运行时同步雅思词汇，不把第三方完整词库提交到仓库
- 只保留墨水屏需要的高频字段，词频门槛为 40
- 本地词库缓存 7 天；网络失败时优先使用旧缓存，首次失败则使用 3 张内置词卡
- 四档回忆评分：忘记、模糊、认识、熟练
- 学习队列和评分结果持久化，重启应用后继续当天进度
- 生成与 Quote/0 物理分辨率一致的 296 x 152 单色预览和传输帧
- 保留独立的图片处理与 BLE 发送页面

## 设备要求

- Android 7.0 或更高版本（最低 API 24，目标 API 36）
- 支持 Bluetooth Low Energy 的 Android 手机
- Quote/0 墨水屏及实现 QuoteImage BLE protocol v1 的固件
- 首次同步需要网络；离线时可使用已有缓存或内置词卡

模拟器可以验证安装、界面、提醒授权、词卡生成和学习进度，但不能替代真实 BLE 传输测试。向墨水屏发送词卡必须使用 Android 真机和 Quote/0。

## 直接安装 APK

本地构建后的 APK 位于：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

开启手机的“开发者选项”和“USB 调试”，连接后执行：

```sh
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

也可以把 APK 传到手机后直接打开安装。Android 若提示禁止未知来源安装，需要只为当前文件管理器临时允许该权限。

## 首次使用

1. 打开 QuoteWords，允许通知权限。Android 12 及以上在连接设备时还会请求附近设备权限。
2. 等待词卡准备完成。ISDC 页面较大，网络慢时会在超时后自动使用内置词卡。
3. 点击右上角的设置图标调整每日新词数、每日上限和提醒时间。
4. 阅读词卡后选择“忘记”“模糊”“认识”或“熟练”，应用会保存结果并切换下一词。
5. 需要发送到墨水屏时，先进入“图片”页，点击设备切换按钮添加 Quote/0，并输入屏幕上的四位配对码。
6. 返回“词卡”页，点击“显示到设备”。发送完成前保持手机靠近设备并不要退出应用。

评分规则：

- 忘记：回到 10 分钟复习，并增加遗忘次数
- 模糊：前进一步，但使用该阶段一半的间隔，且不短于 10 分钟
- 认识：按标准间隔前进一步
- 熟练：一次前进两个阶段

## 开发环境

本项目已在以下环境验证：

- Flutter 3.44.8 stable / Dart 3.12.2
- JDK 17
- Android SDK Platform 36、Build Tools 36.0.0
- Android Emulator 37.1.11
- macOS Apple Silicon

安装 Android Studio 后，在 `Settings > Languages & Frameworks > Android SDK` 中确认已安装：

- Android SDK Platform 36
- Android SDK Build-Tools
- Android SDK Platform-Tools
- Android SDK Command-line Tools (latest)
- Android Emulator（需要模拟器测试时）

macOS 可在 `~/.zprofile` 中配置：

```sh
export JAVA_HOME="/你的/JDK17/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="/你的/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$PATH"
```

重新打开终端后验证：

```sh
flutter doctor -v
sdkmanager --version
adb version
emulator -list-avds
```

`flutter doctor` 中 Android toolchain 应显示绿色。只开发 Android 时，Xcode 和 CocoaPods 的警告可以忽略。

## 获取源码并运行

```sh
git clone https://github.com/joker-sxj/QuoteWords.git
cd QuoteWords
flutter pub get
flutter devices
flutter run -d <设备ID>
```

Android Studio 中选择 `File > Open` 打开仓库根目录，等待 Flutter 和 Gradle 索引完成，再从设备列表选择手机或模拟器运行。

## 测试与构建

每次提交功能前至少执行：

```sh
flutter test
flutter analyze
flutter build apk --debug
git diff --check
```

当前测试覆盖词库解析、7 天缓存、学习设置、提醒时间、艾宾浩斯调度、队列持久化、词卡排版、图片处理、设备状态和主要界面流程。TDD 证据见 [`docs/testing/ielts-word-cards.tdd.md`](docs/testing/ielts-word-cards.tdd.md)，Android 冒烟测试见 [`docs/testing/android-emulator-smoke.md`](docs/testing/android-emulator-smoke.md)。

## 国内网络问题

如果 Gradle 访问 `maven.google.com` 出现 TLS 超时，先尝试 Android Studio 的 HTTP Proxy、稳定网络或代理。也可以在本机 `~/.gradle/init.gradle` 配置阿里云镜像；该文件只影响本机，不应提交到仓库：

```groovy
beforeSettings { settings ->
    settings.pluginManagement.repositories {
        maven { url = uri('https://maven.aliyun.com/repository/google') }
        maven { url = uri('https://maven.aliyun.com/repository/public') }
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

beforeProject { project ->
    project.buildscript.repositories {
        maven { url = uri('https://maven.aliyun.com/repository/google') }
        maven { url = uri('https://maven.aliyun.com/repository/public') }
    }
    def normalized = project.rootProject.projectDir.path.replace('\\', '/')
    if (!normalized.endsWith('/packages/flutter_tools/gradle')) {
        project.repositories {
            maven { url = uri('https://maven.aliyun.com/repository/google') }
            maven { url = uri('https://maven.aliyun.com/repository/public') }
        }
    }
}
```

配置后重新运行 `flutter build apk --debug`。如果依然失败，删除项目的 `.gradle`/`build` 缓存不是第一选择，应先查看具体失败的仓库 URL 和证书错误。

## 数据与隐私

- 学习设置、词卡缓存和复习进度只保存在本机应用目录
- BLE 配对凭证保存在系统安全存储中
- 应用不需要账号，也不上传学习记录
- ISDC 是第三方网页，首次同步和缓存过期时应用会向其发起 HTTPS 请求

## 已知限制

- 后台只负责系统提醒，不会在后台自动连接墨水屏或刷新画面
- ISDC 页面结构变化时，解析适配器可能需要更新
- 首次同步下载量较大，慢速网络下可能等待到 90 秒超时后才切换内置词卡
- BLE 上传、配对码和实际屏幕刷新仍需在 Android 真机与 Quote/0 上验收
