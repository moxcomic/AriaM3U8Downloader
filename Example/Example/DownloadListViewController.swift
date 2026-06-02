//
//  DownloadListViewController.swift
//  Example
//
//  Created by 神崎H亚里亚 on 2019/12/10.
//  Copyright © 2019 moxcomic. All rights reserved.
//
//  迁移：下载进度由 block 改为 async 事件流。
//

import UIKit
import AriaM3U8Downloader

class DownloadListViewController: UITableViewController {
    @IBOutlet var downloadTableView: UITableView!

    private var downloaders: [Int: AriaM3U8Downloader] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        downloadTableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        downloadTableView.tableFooterView = UIView()
    }
}

extension DownloadListViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = "cell-\(indexPath.section)-\(indexPath.row)"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        return tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let urlString = indexPath.row == 0
            ? "http://183.159.37.34:8649/srv-videos/40/media/CA08E6D22DFA4D93B9B849E2D813F65D/CA08E6D22DFA4D93B9B849E2D813F65D_playlist_sub.m3u8"
            : "https://youku.cdn2-okzy.com/20191129/5963_a84d35d8/index.m3u8"
        guard let url = URL(string: urlString) else { return }

        let key = indexPath.row
        let downloader = AriaM3U8Downloader(url: url, outputDirectory: documentPath)
        downloaders[key] = downloader
        tasks[key] = Task { [weak cell] in
            for await event in downloader.events {
                if case .progress(let value) = event {
                    cell?.textLabel?.text = "\(Int(value * 100))%"
                }
            }
        }
        downloader.start()
    }
}
