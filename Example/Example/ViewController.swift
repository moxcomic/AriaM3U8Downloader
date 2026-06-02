//
//  ViewController.swift
//  Example
//
//  Created by 神崎H亚里亚 on 2019/11/28.
//  Copyright © 2019 moxcomic. All rights reserved.
//
//  迁移：去除 SJVideoPlayer/SnapKit，改用系统 AVPlayer；下载回调由 block 改为 async 事件流。
//

import UIKit
import AVFoundation
import AriaM3U8Downloader
import AriaM3U8LocalServer

class ViewController: UIViewController {
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var playView: UIView!

    private var downloader: AriaM3U8Downloader?
    private var eventTask: Task<Void, Never>?
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer?

    private var outputDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AriaM3U8LocalServer.shared.start(path: outputDirectory.path)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        playView.layer.addSublayer(layer)
        playerLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = playView.bounds
    }

    @IBAction func startButton(_ sender: Any) {
        guard downloader == nil else { return }
        // 示例地址；双层 m3u8 示例见 README
        guard let url = URL(string: "http://183.159.37.34:8649/srv-videos/40/media/CA08E6D22DFA4D93B9B849E2D813F65D/CA08E6D22DFA4D93B9B849E2D813F65D_playlist_sub.m3u8") else { return }

        let downloader = AriaM3U8Downloader(url: url, outputDirectory: outputDirectory)
        self.downloader = downloader
        eventTask = Task { [weak self] in
            for await event in downloader.events {
                self?.handle(event)
            }
        }
        downloader.start()
    }

    @IBAction func pauseButton(_ sender: Any) { downloader?.pause() }

    @IBAction func resumeButton(_ sender: Any) { downloader?.resume() }

    @IBAction func stopButton(_ sender: Any) {
        downloader?.cancel()
        eventTask?.cancel()
        downloader = nil
    }

    /// 边下边播：仅用已下载切片生成临时播放列表
    @IBAction func tempPlayButton(_ sender: Any) {
        Task { await play(downloadedOnly: true) }
    }

    /// 播放完整列表
    @IBAction func playButton(_ sender: Any) {
        Task { await play(downloadedOnly: false) }
    }

    @MainActor
    private func handle(_ event: DownloadEvent) {
        switch event {
        case .segmentCompleted(let name, let completed, let total):
            statusLabel.text = name
            countLabel.text = "\(completed)/\(total)"
        case .progress(let value):
            progressView.progress = Float(value)
        case .completed:
            statusLabel.text = "下载任务全部完成"
        case .segmentFailed(let name):
            statusLabel.text = "切片失败: \(name)"
        case .failed(let message):
            statusLabel.text = "失败: \(message)"
        default:
            break
        }
    }

    private func play(downloadedOnly: Bool) async {
        guard
            let downloader,
            let server = AriaM3U8LocalServer.shared.localServerURLString()
        else {
            print("未下载或本地服务未开启")
            return
        }
        do {
            if downloadedOnly {
                try await downloader.makeLocalPlaylistForDownloaded()
            } else {
                try await downloader.makeLocalPlaylist()
            }
        } catch {
            print("生成播放文件失败: \(error)")
            return
        }
        guard let url = URL(string: server + "/index.m3u8") else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}
