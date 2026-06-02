// swift-tools-version: 6.0
// 说明：swift-tools-version 6.0 是启用 Swift 6 语言模式（完整严格并发）的最低门槛。
// 使用 Swift 6.3 工具链（Xcode 26.4/26.5）编译；语言模式为 .v6。
import PackageDescription

let package = Package(
    name: "AriaM3U8Downloader",
    platforms: [
        .iOS(.v15)            // 迁移目标最低部署版本
    ],
    products: [
        // 核心：M3U8/TS 下载引擎（去 Rx、去 @objc，async/await + actor）
        .library(
            name: "AriaM3U8Downloader",
            targets: ["AriaM3U8Downloader"]
        ),
        // 可选：本地播放 HTTP 服务（对应原 LocalServer subspec，自建 Network.framework，零外部依赖）
        .library(
            name: "AriaM3U8LocalServer",
            targets: ["AriaM3U8LocalServer"]
        )
    ],
    dependencies: [
        // 仅保留 Alamofire（见 MIGRATION-PLAN.md 3.2 依赖决策表）
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.12.0"))
    ],
    targets: [
        .target(
            name: "AriaM3U8Downloader",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire")
            ],
            path: "AriaM3U8Downloader/Downloader"
        ),
        .target(
            name: "AriaM3U8LocalServer",
            dependencies: [
                .target(name: "AriaM3U8Downloader")   // 自建 Network.framework，无外部依赖
            ],
            path: "AriaM3U8Downloader/LocalServer"
        ),
        .testTarget(
            name: "AriaM3U8DownloaderTests",
            dependencies: ["AriaM3U8Downloader"],
            path: "Tests/AriaM3U8DownloaderTests"
        )
    ]
)
