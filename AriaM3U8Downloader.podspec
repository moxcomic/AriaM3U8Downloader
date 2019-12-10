Pod::Spec.new do |s|
  s.name             = "AriaM3U8Downloader"
  s.version          = "0.0.5"
  s.summary          = "A Swift M3U8 Downloader."
  s.homepage         = "https://github.com/moxcomic/AriaM3U8Downloader.git"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "moxcomic" => "656469762@qq.com" }
  s.source           = { :git => "https://github.com/moxcomic/AriaM3U8Downloader.git", :tag => "#{s.version}" }
  s.ios.deployment_target = "9.0"
  s.swift_version = "5.0"
  s.source_files = "AriaM3U8Downloader/Downloader/**/*.swift"
  s.frameworks = "UIKit", "Foundation"

  s.subspec "LocalServer" do |ss|
    ss.source_files = "AriaM3U8Downloader/LocalServer/**/*.swift"
    ss.dependency "GCDWebServer/WebDAV"
  end

  s.dependency "RxSwift"
  s.dependency "NSObject+Rx"
  s.dependency "RxDataSources"
  s.dependency "Alamofire"
  s.dependency "RxAlamofire"
end