//
//  AppDelegate.swift
//  KubeContext
//
//  Created by Turken, Hasan on 04.10.18.
//  Copyright © 2018 Turken, Hasan. All rights reserved.
//

import Cocoa
import Yams
import SwiftyStoreKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
    let menuManager = MenuManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            statusBarButton = button
            statusBarButton.image = NSImage(named:NSImage.Name("kubernetes-icon"))
            //button.imageHugsTitle = false
            //button.contentTintColor = NSColor.red
            //button.action = #selector(constructMenu(_:))
        }
        
        let menu = NSMenu()
        menu.delegate = menuManager
        statusItem.menu = menu
        
        if CommandLine.arguments.contains("--uitesting") {
            do {
                try prepareForTesting()
            } catch {
                NSLog("Could not prepare UI test fixtures: \(error)")
                NSApp.terminate(self)
                return
            }
        }
        
        k8s = Kubernetes()
        k8s.contextChanged()
        
        // For testing
        //UserDefaults.standard.set(false, forKey: keyPro)
        //UserDefaults.standard.removeObject(forKey: keyExistingUserPrePro)
        //UserDefaults.standard.set(existingUserPreProFalse, forKey: keyExistingUserPrePro)
        // End of For testing
        
        // Github release - all free
        UserDefaults.standard.set(true, forKey: keyPro)
        
        isPro = UserDefaults.standard.bool(forKey: keyPro)
        isExistingUserPrePro = UserDefaults.standard.integer(forKey: keyExistingUserPrePro)
        if isExistingUserPrePro == existingUserPreProUndefined {
            if k8s.kubeconfig == nil {
                isExistingUserPrePro = existingUserPreProFalse
                UserDefaults.standard.set(existingUserPreProFalse, forKey: keyExistingUserPrePro)
            }
            else {
                isExistingUserPrePro = existingUserPreProTrue
                UserDefaults.standard.set(existingUserPreProTrue, forKey: keyExistingUserPrePro)
            }
        }
        if isPro || isExistingUserPrePro == existingUserPreProTrue {
            maxNofContexts = unlimitedNofContexts
        }
        
        SwiftyStoreKit.completeTransactions(atomically: true) { purchases in
            for purchase in purchases {
                switch purchase.transaction.transactionState {
                case .purchased, .restored:
                    if purchase.needsFinishTransaction {
                        // Deliver content from server, then:
                        SwiftyStoreKit.finishTransaction(purchase.transaction)
                    }
                // Unlock content
                case .failed, .purchasing, .deferred:
                    break // do nothing
                }
            }
        }
    }
    
    func prepareForTesting() throws {
        NSLog ("UI Testing Mode")
        bookmarksFile = "TestBookmarks.dict"
        uiTesting = true
        let fileManager = FileManager.default
        
        var url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = url.appendingPathComponent(bookmarksFile)
        
        if fileManager.isReadableFile(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:true)
        let tempDataUrl = documentDirectory.appendingPathComponent("TempData", isDirectory: true)
        try fileManager.createDirectory(at: tempDataUrl, withIntermediateDirectories: true)
        
        let configURL = tempDataUrl.appendingPathComponent("ui-test-config.yaml")
        let importURL = tempDataUrl.appendingPathComponent("file-to-import.yaml")
        testFileAsConfig = configURL
        testFileToImport = importURL

        let fixtures = [
            ("ui-test-config", configURL),
            ("file-to-import", importURL)
        ]
        for (name, destination) in fixtures {
            guard let source = Bundle.main.url(forResource: name, withExtension: "yaml") else {
                throw NSError(domain: "KubeContextUITests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing bundled UI test fixture: \(name).yaml"
                ])
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
        
        UserDefaults.standard.set(true, forKey: keyPro)
    }
}
