//
//  Kubernetes.swift
//  KubeContext
//
//  Created by Turken, Hasan on 07.10.18.
//  Copyright © 2018 Turken, Hasan. All rights reserved.
//

import Foundation
import Yams
import os
import CoreServices
import Cocoa

private let contextChangedCallback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
    guard let clientCallBackInfo = clientCallBackInfo else {
        return
    }
    let kubernetes = Unmanaged<Kubernetes>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    kubernetes.contextChanged()
}

private let contextReleaseCallback: FSEventStreamContextReleaseCallBack = { clientCallBackInfo in
    guard let clientCallBackInfo = clientCallBackInfo else {
        return
    }
    Unmanaged<Kubernetes>.fromOpaque(clientCallBackInfo).release()
}

private func updateContextStatusBar() {
    statusBarButton.imagePosition = NSControl.ImagePosition.imageLeft
    if k8s.kubeconfig != nil {
        do {
            try showContextName()
        } catch {
            NSLog("Error occured while trying to set statusBarButton in contextChangedCallback %@", error as NSError) 
        }
    }
}

func showContextName() throws {
    let currContext: String = try (k8s.getConfig()?.CurrentContext) ?? ""
    if k8s.shouldShowContextName {
        statusBarButton.title = currContext.truncated(limit: 20, position: String.TruncationPosition.middle, leader: "...")
    } else {
        statusBarButton.title = ""
    }
    if #available(OSX 10.14, *) {
        if let c = UserDefaults.standard.color(forKey: keyIconColorPrefix + currContext) {
            statusBarButton.contentTintColor = c
        } else {
            statusBarButton.contentTintColor = nil
        }
    }
}

class Kubernetes {
    let fileManager = FileManager.default
    var kubeconfig:URL?
    var shouldShowContextName:Bool
    var iconColor: NSColor?
    var watcher: FSEventStream?

    init() {
        shouldShowContextName = UserDefaults.standard.bool(forKey: keyShowContextOnMenu)
        let f = loadBookmarks()
        if f == nil {
            return
        }
    
        if kubeconfig == nil || kubeconfig != f {
            kubeconfig = f
            initWatcher()
        }
    }
    
    func setShowContextName(show: Bool) {
        shouldShowContextName = show
        do {
            try showContextName()
        } catch {
            NSLog("Error occured while trying to setShowContextName %@", error as NSError)
        }
    }
    
    func setKubeconfig(configFile: URL?) throws {
        if configFile == nil {
            return
        }
        let _ = try loadConfig(url: configFile!)
        
        if kubeconfig == nil || kubeconfig != configFile {
            kubeconfig = configFile
            initWatcher()
        }
        backupKubeconfig()
        storeFolderInBookmark(url: configFile!)
        saveBookmarksData()
    }
    
    func initWatcher(){
        if let watcher = watcher {
            FSEventStreamStop(watcher)
            FSEventStreamInvalidate(watcher)
            self.watcher = nil
        }

        guard let kubeconfigPath = kubeconfig?.path else {
            return
        }
        let pathsToWatch = [kubeconfigPath] as CFArray
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passRetained(self).toOpaque(),
                                           retain: nil,
                                           release: contextReleaseCallback,
                                           copyDescription: nil)
        guard let watcher = FSEventStreamCreate(nil,
                                                contextChangedCallback,
                                                &context,
                                                pathsToWatch,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                0,
                                                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)) else {
            Unmanaged<Kubernetes>.fromOpaque(context.info!).release()
            NSLog("Error while creating watcher")
            return
        }

        FSEventStreamSetDispatchQueue(watcher, DispatchQueue.main)
        guard FSEventStreamStart(watcher) else {
            FSEventStreamInvalidate(watcher)
            NSLog("Error while starting watcher")
            return
        }
        self.watcher = watcher
    }

    func contextChanged() {
        updateContextStatusBar()
    }
    
    func backupKubeconfig() {
        let origConfigURL = getOrigKubeconfigFileUrl()
        do {
            if fileManager.isReadableFile(atPath: (origConfigURL?.path)!) {
                try fileManager.removeItem(at: origConfigURL!)
            }
            try fileManager.copyItem(at: kubeconfig!, to: origConfigURL!)
        } catch {
            NSLog("Error: could not backup original kubeconfig file: \(error)")
        }
    }
    
    func getConfigFilePath () -> String {
        return (kubeconfig?.path)!
    }
    
    private func loadConfig(url: URL) throws -> Config? {
        // TODO: return error as well
        let fileContent = try String(contentsOf: url, encoding: .utf8)
        
        let decoder = YAMLDecoder()
        var config = try decoder.decode(Config.self, from: fileContent)
        

        for (i, ctx) in config.Contexts.enumerated() {
            if #available(OSX 10.13, *) {
                if let c = UserDefaults.standard.color(forKey: keyIconColorPrefix + ctx.Name) {
                    config.Contexts[i].IconColor = c
                }
            }
        }

        return config
    }
    
    func saveConfig(config: Config) throws {
        try saveConfigToFile(config: config, file: kubeconfig)
    }
    
    func getConfig() throws -> Config? {
        return try loadConfig(url: kubeconfig!)
    }
    
    func mergeKubeconfigIntoConfig(configToImportFileUrl: URL, mainConfig: Config) throws -> Config {
        let newConfig = try loadConfig(url: configToImportFileUrl)
        
        var mergedConfig = mainConfig
        
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmSS"
        let dateString = formatter.string(from: now)
        
        var importIdSuffix = ""
        if uiTesting {
            importIdSuffix = "_imported"
        } else {
            importIdSuffix = "_imported_" + dateString
        }
        
        for var cluster in (newConfig?.Clusters)! {
            cluster.Name += importIdSuffix
            mergedConfig.Clusters.append(cluster)
        }
        for var user in (newConfig?.AuthInfos)! {
            user.Name += importIdSuffix
            mergedConfig.AuthInfos.append(user)
        }
        for var context in (newConfig?.Contexts)! {
            context.Name += importIdSuffix
            context.Context.Cluster += importIdSuffix
            context.Context.AuthInfo += importIdSuffix
            mergedConfig.Contexts.append(context)
        }
        return mergedConfig
    }
        
    func importConfig(configToImportFileUrl: URL) throws {
        let mainConfig = try loadConfig(url: kubeconfig!)
        
        let mergedConfig = try mergeKubeconfigIntoConfig(configToImportFileUrl: configToImportFileUrl, mainConfig: mainConfig!)
        
        try saveConfig(config: mergedConfig)
    }
    
    func useContext(name: String) throws {
        var config = try loadConfig(url: kubeconfig!)
        config?.CurrentContext = name
        try saveConfig(config: config!)
    }
}

func getOrigKubeconfigFileUrl() -> URL? {
    let fileManager = FileManager.default
    do {
        let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
        let origConfigURL = documentDirectory.appendingPathComponent("kubeconfig.orig")
        return origConfigURL
    } catch {
        NSLog("Error: could not get url of original kubeconfig file: \(error)")
        return nil
    }
}
