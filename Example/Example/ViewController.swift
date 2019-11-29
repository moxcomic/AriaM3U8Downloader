//
//  ViewController.swift
//  Example
//
//  Created by 神崎H亚里亚 on 2019/11/28.
//  Copyright © 2019 moxcomic. All rights reserved.
//

import UIKit
import AriaM3U8Downloader
import SJVideoPlayer
import SnapKit

class ViewController: UIViewController {
    var downloader: AriaM3U8Downloader!

    @IBAction func startButton(_ sender: Any) {
        if downloader != nil { return }
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Once
        // https://v01-gl-vod.dtslb.com/201910/22/09YSU2z4/3721kb/hls/index.m3u8
        // Seconds
        // https://youku.com-ok-pptv.com/20191003/7712_b1cd8a61/index.m3u8
        downloader = AriaM3U8Downloader(withURLString: "https://youku.com-ok-pptv.com/20191003/7712_b1cd8a61/index.m3u8", outputPath: documentPath.path)
        downloader.start()
        
        downloader.downloadTSSuccessExeBlock = { self.statusLabel.text = $0 }
        downloader.downloadFileProgressExeBlock = { (event) in
            DispatchQueue.main.async {
                self.progressView.progress = event
            }
        }
        downloader.downloadM3U8StatusExeBlock = { (d, t) in
            DispatchQueue.main.async {
                self.countLabel.text = "\(d)/\(t)"
            }
        }
        downloader.downloadCompleteExeBlock = {
            DispatchQueue.main.async {
                self.statusLabel.text = "下载任务全部完成"
            }
        }
    }
    
    @IBAction func pauseButton(_ sender: Any) {
        if downloader == nil { return }
        downloader.pause()
    }
    
    @IBAction func resumeButton(_ sender: Any) {
        if downloader == nil { return }
        downloader.resume()
    }
    
    @IBAction func stopButton(_ sender: Any) {
        if downloader == nil { return }
        downloader.stop()
        downloader = nil
    }
    @IBAction func tempPlayButton(_ sender: Any) {
        guard
            let d = downloader,
            let server = AriaM3U8LocalServer.shared.getLocalServerURLString()
            else { print("未下载或者本地服务未开启"); return }
        d.createTempLocalM3U8File()
        let index = server.appending("/index.m3u8")
        
        let asset = SJVideoPlayerURLAsset(url: URL(string: index)!)
        asset?.title = "AriaM3U8Downloader"
        player.urlAsset = asset
    }
    
    @IBAction func playButton(_ sender: Any) {
        guard
            let d = downloader,
            let server = AriaM3U8LocalServer.shared.getLocalServerURLString()
            else { print("未下载或者本地服务未开启"); return }
        d.createLocalM3U8File()
        let index = server.appending("/index.m3u8")
        
        let asset = SJVideoPlayerURLAsset(url: URL(string: index)!)
        asset?.title = "AriaM3U8Downloader"
        player.urlAsset = asset
    }
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var playView: UIView!
    var player = SJVideoPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        AriaM3U8LocalServer.shared.start(withPath: documentPath.path)
        
        playView.addSubview(player.view)
        player.view.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
}

