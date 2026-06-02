# AriaM3U8Downloader

A Swift M3U8 / HLS downloader —— 纯 **Swift Concurrency**（async/await + actor）实现，无 RxSwift、无 CocoaPods。

> **注意**：名字带 “Aria” 但**不集成 aria2**，下载基于 `Alamofire` + 结构化并发。

## Requirements
- iOS 15.0+
- Swift 6.0+（以 Swift 6.3 工具链编译，语言模式 `.v6`）
- Xcode 16+

## Installation（Swift Package Manager）

Xcode：**File ▸ Add Package Dependencies…**，填入仓库地址。
或在 `Package.swift`：

```swift
dependencies: [
    .package(url: "https://github.com/moxcomic/AriaM3U8Downloader.git", from: "1.0.0")
]
```

两个 product：
- **`AriaM3U8Downloader`** —— 核心下载器
- **`AriaM3U8LocalServer`** —— 可选，本地播放 HTTP 服务（基于 `Network.framework`，支持 Range）

## Usage

```swift
import AriaM3U8Downloader

let downloader = AriaM3U8Downloader(
    url: URL(string: "https://xxx.m3u8")!,
    outputDirectory: outputURL
)

// 事件流：替代旧版 11 个 block 回调 + NotificationCenter 通知
Task {
    for await event in downloader.events {
        switch event {
        case .progress(let p):                              print("进度 \(p)")
        case .segmentCompleted(let name, let done, let all): print("\(done)/\(all) \(name)")
        case .completed:                                    print("全部完成")
        case .failed(let message):                          print("失败 \(message)")
        default:                                            break
        }
    }
}

downloader.start()
// downloader.pause() / .resume() / .cancel()
```

### 本地播放（AriaM3U8LocalServer + AVPlayer）

```swift
import AriaM3U8LocalServer

try AriaM3U8LocalServer.shared.start(path: outputURL.path)
try await downloader.makeLocalPlaylist()             // 或 makeLocalPlaylistForDownloaded() 边下边播
let url = URL(string: AriaM3U8LocalServer.shared.localServerURLString()! + "/index.m3u8")!
player.replaceCurrentItem(with: AVPlayerItem(url: url))
player.play()
```

## API

### 事件 `DownloadEvent`
`started` · `progress(Double)` · `segmentCompleted(name:completed:total:)` · `segmentFailed(name:)` · `paused` · `resumed` · `cancelled` · `completed` · `failed(String)`

### 配置 `DownloadConfiguration`
| 字段 | 默认 | 说明 |
|---|---|---|
| `maxConcurrentDownloads` | 3 | 最大并发切片下载数 |
| `requestTimeout` | 10 | 请求/资源超时（秒） |
| `retryCount` | 1 | 单切片失败重试次数 |
| `failFast` | false | 一片失败即整体取消（默认容错继续） |
| `autoPauseOnBackground` | true | 进后台自动暂停、回前台恢复 |

### 状态 `DownloadStatus`
`notReady` · `ready` · `downloading` · `paused` · `cancelled` · `completed` · `failed`

## 说明
- 仅支持**无 DRM / AES-128 clear-key** 内容；FairPlay 等 DRM 不支持（无法且不应手动解密）。
- **自 1.0 起的破坏性变更**：移除 CocoaPods 与 RxSwift 全家桶，改为 SPM + Swift Concurrency；不再提供 Objective-C（`@objc`）兼容层。
