//
//  AriaGlobal.swift
//  AriaM3U8Downloader
//
//  Created by 神崎H亚里亚 on 2019/11/28.
//  Copyright © 2019 moxcomic. All rights reserved.
//

import UIKit
import RxSwift

struct baseError: Error {
    var desc = ""
    var localizedDescription: String { return desc }
    init(_ desc: String) { self.desc = desc }
}

enum AriaNotification: String {
    case DownloadTSSuccessNotification
    case DownloadM3U8ProgressNotification
    case DownloadM3U8StartNotification
    case DownloadM3U8PausedNotification
    case DownloadM3U8ResumeNotification
    case DownloadM3U8StopNotification
    case DownloadTSFailureNotification
    case DownloadM3U8CompleteNotification
    case DownloadM3U8StatusNotification
    
    var stringValue: String {
        return "Aria" + rawValue
    }
    
    var notificationName: NSNotification.Name {
        return NSNotification.Name(stringValue)
    }
}

extension NotificationCenter {
    static func post(customeNotification name: AriaNotification, object: Any? = nil) {
        NotificationCenter.default.post(name: name.notificationName, object: object)
    }
}

extension Reactive where Base: NotificationCenter {
    func notification(custom name: AriaNotification, object: AnyObject? = nil) -> Observable<Notification> {
       return notification(name.notificationName, object: object)
    }
}
