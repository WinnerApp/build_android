import ArgumentParser
import SwiftShell
import Foundation
import Alamofire


struct BuildAndroid: ParsableCommand {
    
    enum BuildModel: String, EnumerableFlag {
        case debug
        case profile
        case release
    }
    
    @Flag(help: "编译的类型")
    var mode:BuildModel
    
    @Option(help:"设置主要的版本号 比如 1.0.0")
    var buildName:String?
    
    mutating func run() throws {
//        uploadApkInZealot(apkFile: "/Users/king/Library/Caches/apk/app-profile-1644727552.apk", changeLog: "")
//        return
        var context = CustomContext(SwiftShell.main)
        if let envPath = ProcessInfo.processInfo.environment["ENV_PATH"] {
            context.env["PATH"] = envPath
        }
        guard let pwd = ProcessInfo.processInfo.environment["PWD"] else {
            throw "$PWD为空"
        }
        guard let home = ProcessInfo.processInfo.environment["HOME"] else {
            throw "$HOME为空"
        }
        let buildNumber = "\(Int(Date().timeIntervalSince1970))"
        var buildParameters:[String] = [
            "build",
            "apk",
            "--\(mode.rawValue)",
            "--build-number=\(buildNumber)",
        ]
        if let buildName = buildName {
            buildParameters.append(contentsOf: ["--build-name=\(buildName)"])
        }
        print(pwd)
        context.currentdirectory = pwd
        let command = context.runAsyncAndPrint("flutter", buildParameters)
        try command.finish()
        let apkFile = "\(pwd)/build/app/outputs/flutter-apk/app-\(mode.rawValue).apk"
        guard FileManager.default.fileExists(atPath: apkFile) else {
            throw "\(apkFile)不存在,请检查编译命令"
        }
        let apkCachePath = "\(home)/Library/Caches/apk"
        try createDirectoryIfNotExit(path: apkCachePath)
        let toApkFile = "\(apkCachePath)/app-\(mode.rawValue)-\(buildNumber).apk"
        try FileManager.default.copyItem(atPath: apkFile, toPath: toApkFile)
        context.currentdirectory = "\(pwd)/android"
        print(context.currentdirectory)
        let changelog = changelog()
//        let firCommand = context.runAsyncAndPrint("fastlane", "firim", "file:\(toApkFile)", "changelog:\(changelog)")
//        try firCommand.finish()
        print("正在将APK上传到Zealot服务")
        let isOK = uploadApkInZealot(apkFile: apkFile, changeLog: changelog)
        guard isOK else {
            SwiftShell.exit(errormessage: "上传失败!")
        }
        print("上传APK完毕")
    }
    
    func createDirectoryIfNotExit(path:String) throws {
        var isDirectory:ObjCBool = .init(false)
        guard !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            if !isDirectory.boolValue {
                throw "\(path)已经存在，但不是一个文件夹"
            }
            return
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path),
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }
    
    func changelog() -> String {
        /// http://127.0.0.1:8080/job/win+_android/179/api/json?oauth_token=1191f0b1d3a092f71d96673689e32b0368&oauth_signature_method=HMAC-SHA1&oauth_timestamp=1644221464&oauth_nonce=W9KIzo&oauth_version=1.0&oauth_signature=AUAng0HUvSM5uLHk0l0QHf7fZCI%3D&pretty=true
        var log = mode == .release ? "正式版本":"体验版本"
        if let jobId = ProcessInfo.processInfo.environment["BUILD_ID"], let url = URL(string: "http://127.0.0.1:8080/job/win+_android/\(jobId)/api/json?oauth_token=1191f0b1d3a092f71d96673689e32b0368&oauth_signature_method=HMAC-SHA1&oauth_timestamp=1644221464&oauth_nonce=W9KIzo&oauth_version=1.0&oauth_signature=AUAng0HUvSM5uLHk0l0QHf7fZCI%3D&pretty=tru") {
            let semaphore = DispatchSemaphore(value: 0)
            var request = URLRequest(url: url)
            request.setValue("Basic a2luZzoxOTkwODIz", forHTTPHeaderField: "authorization")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data, let jobInfo = try? JSONDecoder().decode(JobInfo.self, from: data) {
                    jobInfo.changeSet?.items.forEach({ item in
                        log += """
                        
                        - \(item.comment)
                        """
                    })
                }
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()
        }
        return log
    }
    
    func uploadApkInZealot(apkFile:String, changeLog:String) -> Bool {
        guard let zealotToken = ProcessInfo.processInfo.environment["ZEALOT_TOKEN"] else {
            SwiftShell.exit(errormessage: "ZEALOT_TOKEN不存在")
        }
        guard let channelKey = ProcessInfo.processInfo.environment["ZEALOT_CHANNEL_KEY"] else {
            SwiftShell.exit(errormessage: "ZEALOT_CHANNEL_KEY不存在")
        }
        guard let uploadHost = ProcessInfo.processInfo.environment["ZEALOT_HOST"] else {
            SwiftShell.exit(errormessage: "ZEALOT_HOST 不存在")
        }
        let semaphore = DispatchSemaphore(value: 0)
        let uploadUrl = "\(uploadHost)/api/apps/upload?token=\(zealotToken)"
        let mode = mode != .release ? "adhoc" : "release"
        var isOK = false
        AF.sessionConfiguration.timeoutIntervalForRequest = 5 * 60
        AF.upload(multipartFormData: { fromData in
            if let data = channelKey.data(using: .utf8) {
                fromData.append(data, withName: "channel_key")
            }
            if let data = mode.data(using: .utf8) {
                fromData.append(data, withName: "release_type")
            }
            if let data = changeLog.data(using: .utf8) {
                fromData.append(data, withName: "changelog")
            }
            if let data = try? Data(contentsOf: URL(fileURLWithPath: apkFile)) {
                fromData.append(data, withName: "file", fileName: apkFile)
            }
        }, to: uploadUrl).uploadProgress(queue:DispatchQueue.global()) { progress in
            print("已上传:\(progress.completedUnitCount) 总共大小:\(progress.totalUnitCount)")
        }.response(queue: DispatchQueue.global()) { response in
            if let code = response.response?.statusCode {
                isOK = code == 201
            }
            semaphore.signal()
        }
        

        semaphore.wait()
        return isOK
    }
}

BuildAndroid.main()

struct JobInfo: Codable {
    let changeSet:ChangeSet?
}

extension JobInfo {
    struct ChangeSet: Codable {
        let items:[Item]
    }
}

extension JobInfo.ChangeSet {
    struct Item: Codable {
        let comment:String
    }
}
