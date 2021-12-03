import ArgumentParser
import SwiftShell
import Foundation


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
        
//        pwd = "/Users/king/Documents/flutter_win+"

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
        let firCommand = context.runAsyncAndPrint("fastlane", "firim", "file:\(toApkFile)")
        try firCommand.finish()
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
}

BuildAndroid.main()
