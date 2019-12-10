//
//  DownloadListViewController.swift
//  Example
//
//  Created by 神崎H亚里亚 on 2019/12/10.
//  Copyright © 2019 moxcomic. All rights reserved.
//

import UIKit
import AriaM3U8Downloader


class DownloadListViewController: UITableViewController {
    @IBOutlet var downloadTableView: UITableView!
    
    override func viewDidLoad() {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let url = indexPath.row == 0 ? "https://youku.cdn3-okzy.com/20191210/4859_eab5780a/index.m3u8" : "https://youku.cdn2-okzy.com/20191129/5963_a84d35d8/index.m3u8"
        let downloader = AriaM3U8Downloader(withURLString: url, outputPath: documentPath.path, tag: indexPath.row)
        downloader.start()
        
        downloader.downloadFileProgressExeBlock = { (event) in
            DispatchQueue.main.async {
                cell?.textLabel?.text = "\(event)"
            }
        }
    }
}
