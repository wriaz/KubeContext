//
//  MenuManager.swift
//  KubeContext
//
//  Created by Turken, Hasan on 12.10.18.
//  Copyright © 2018 Turken, Hasan. All rights reserved.
//

import Foundation
import Cocoa

class MenuManager: NSObject, NSMenuDelegate {
    var manageController: NSWindowController?
    var contextSearchController: ContextSearchWindowController?
    
    override init() {
        super.init()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        if k8s.kubeconfig == nil {
            ConstructInitMenu(menu: menu)
        } else {
            ConstructMainMenu(menu: menu)
        }
    }
    
    private func switchContext(name: String) throws {
        try k8s.useContext(name: name)
        k8s.contextChanged()
    }

    @objc func openContextSearch(_ sender: NSMenuItem) {
        do {
            guard let config = try k8s.getConfig() else {
                alertUserWithWarning(message: "Could not load contexts from the selected kubeconfig.")
                return
            }
            let controller = ContextSearchWindowController(
                contexts: config.Contexts,
                currentContext: config.CurrentContext
            ) { [weak self] name in
                guard let self = self else {
                    return false
                }
                do {
                    try self.switchContext(name: name)
                    return true
                } catch {
                    self.alertUserWithWarning(message: "Could not switch context: \(error)")
                    return false
                }
            }
            contextSearchController = controller
            controller.showWindow(sender)
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(sender)
            controller.focusSearchField()
        } catch {
            alertUserWithWarning(message: "Could not load contexts from the selected kubeconfig: \(error)")
        }
    }
    
    @objc func logClick(_ sender: NSMenuItem) {
        NSLog("Clicked on " + sender.title)
    }
    
    @objc func openManagement(_ sender: NSMenuItem) {
        if (manageController == nil) {
            let storyboard = NSStoryboard(name: NSStoryboard.Name("Manage"), bundle: nil)
            manageController = storyboard.instantiateInitialController() as? NSWindowController
        }

        if (manageController != nil) {
            manageController!.showWindow(sender)
            manageController!.window?.orderFrontRegardless()
        }
        if sender.title == "Import Kubeconfig File" {
            if let a = manageController?.contentViewController as? ManageViewController {
                a.lockButtonAction(self)
            }
        }
    }

    @objc func importConfig(_ sender: NSMenuItem) {
        NSLog("will import file...")
        if k8s == nil {
            alertUserWithWarning(message: "Not able to import config file, kubernetes not initialized!")
            return
        }
        var configToImportFileUrl: URL?
        if testFileToImport == nil {
            configToImportFileUrl = openFolderSelection()
        } else {
            configToImportFileUrl = testFileToImport
        }
        if configToImportFileUrl == nil {
            return
        }
        do {
            try k8s.importConfig(configToImportFileUrl: configToImportFileUrl!)
        } catch {
            alertUserWithWarning(message: "Not able to import config file \(error)")
        }
    }
    
    @objc func selectKubeconfig(_ sender: NSMenuItem) {
        do {
            try selectKubeconfigFile()
        } catch {
            alertUserWithWarning(message: "Could not parse selected kubeconfig file\n \(error)")
        }
    }
    
    func ConstructInitMenu(menu: NSMenu){
        menu.removeAllItems()
        let selectConfigMenuItem = NSMenuItem(title: "Select kubeconfig file", action:  #selector(selectKubeconfig(_:)), keyEquivalent: "c")
        selectConfigMenuItem.target = self
        menu.addItem(selectConfigMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    func ConstructMainMenu(menu: NSMenu){
        menu.removeAllItems()
        let centerParagraphStyle = NSMutableParagraphStyle.init()
        centerParagraphStyle.alignment = .center
        
        // Current Context Title
        let currentContextTitleItem = NSMenuItem(title: "", action: #selector(logClick(_:)), keyEquivalent: "")
        currentContextTitleItem.target=self
        let contextTitle = NSAttributedString.init(string: "Current Context", attributes: [NSAttributedString.Key.paragraphStyle: centerParagraphStyle, NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 14)])
        currentContextTitleItem.attributedTitle = contextTitle
        menu.addItem(currentContextTitleItem)
        
        var config: Config!
        do {
            config = try k8s.getConfig()
        } catch {
            NSLog("Could not parse config file \(error)")
            alertUserWithWarning(message: "Could not parse config file \n \(error)")
            return
        }
        
        
        let ctxs = config.Contexts
        
        let currentContextTextItem = NSMenuItem(title: "", action: #selector(logClick(_:)), keyEquivalent: "")
        currentContextTextItem.target = self
        currentContextTextItem.identifier = NSUserInterfaceItemIdentifier("current-context-name")
        let currentContextText = NSAttributedString.init(string: config.CurrentContext?.wrap(limit: 32) ?? "", attributes: [NSAttributedString.Key.paragraphStyle: centerParagraphStyle])
        currentContextTextItem.attributedTitle = currentContextText
        menu.addItem(currentContextTextItem)
        
        // Seperator
        menu.addItem(NSMenuItem.separator())
        
        // Switch Context
        let switchContextMenuItem = NSMenuItem(title: "Switch Context", action: #selector(openContextSearch(_:)), keyEquivalent: "c")
        switchContextMenuItem.target = self
        menu.addItem(switchContextMenuItem)
        
        // Import Kubeconfig file
        var importAction = #selector(importConfig(_:))
        if ctxs.count >= maxNofContexts {
            importAction = #selector(openManagement(_:))
        }

        let importKubeconfigMenuItem = NSMenuItem(title: "Import Kubeconfig File", action: importAction, keyEquivalent: "i")
        importKubeconfigMenuItem.target = self
        menu.addItem(importKubeconfigMenuItem)
        
        let manageContextMenuItem = NSMenuItem(title: "Manage Contexts", action: #selector(openManagement(_:)), keyEquivalent: "m")
        manageContextMenuItem.target = self
        menu.addItem(manageContextMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    final class ContextSearchWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        private let allContexts: [ContextElement]
        private let currentContext: String?
        private let onSelect: (String) -> Bool
        private var matchingContexts: [ContextElement] = []

        private let searchField = NSSearchField()
        private let tableView = ContextSearchTableView()
        private let scrollView = NSScrollView()
        private let emptyStateLabel = NSTextField(labelWithString: "No matching contexts")

        init(contexts: [ContextElement], currentContext: String?, onSelect: @escaping (String) -> Bool) {
            self.allContexts = contexts
            self.currentContext = currentContext
            self.onSelect = onSelect
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Switch Context"
            window.minSize = NSSize(width: 320, height: 240)
            super.init(window: window)
            configureContent()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private func configureContent() {
            guard let contentView = window?.contentView else {
                return
            }
            contentView.translatesAutoresizingMaskIntoConstraints = false

            searchField.identifier = NSUserInterfaceItemIdentifier("switch-context-search")
            searchField.placeholderString = "Search Contexts"
            searchField.sendsSearchStringImmediately = true
            searchField.target = self
            searchField.action = #selector(searchFieldChanged(_:))
            searchField.delegate = self

            tableView.identifier = NSUserInterfaceItemIdentifier("switch-context-results")
            tableView.headerView = nil
            tableView.rowHeight = 24
            tableView.allowsEmptySelection = true
            tableView.dataSource = self
            tableView.delegate = self
            tableView.target = self
            tableView.action = #selector(selectContext(_:))
            tableView.onEscape = { [weak self] in self?.window?.close() }
            tableView.onSelect = { [weak self] in self?.selectSelectedContext() }
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("context-name"))
            column.width = 380
            tableView.addTableColumn(column)
            tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder

            emptyStateLabel.alignment = .center
            emptyStateLabel.textColor = .secondaryLabelColor
            emptyStateLabel.isHidden = true
            emptyStateLabel.identifier = NSUserInterfaceItemIdentifier("switch-context-empty-state")

            [searchField, scrollView, emptyStateLabel].forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview($0)
            }

            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                searchField.heightAnchor.constraint(equalToConstant: 24),
                scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
                scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
                emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
            ])
            updateMatches()
        }

        func focusSearchField() {
            window?.makeFirstResponder(searchField)
        }

        @objc private func searchFieldChanged(_ sender: NSSearchField) {
            updateMatches()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                moveSelection(by: -1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                moveSelection(by: 1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                selectSelectedContext()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                window?.close()
                return true
            default:
                return false
            }
        }

        private func moveSelection(by offset: Int) {
            guard !matchingContexts.isEmpty else {
                return
            }
            let selectedRow = tableView.selectedRow
            let nextRow = min(max((selectedRow < 0 ? 0 : selectedRow + offset), 0), matchingContexts.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(nextRow)
        }

        private func updateMatches() {
            let result = ContextSearch.matchingContexts(searchText: searchField.stringValue, in: allContexts)
            matchingContexts = result.0
            tableView.reloadData()
            emptyStateLabel.isHidden = !matchingContexts.isEmpty
            if let currentIndex = matchingContexts.firstIndex(where: { $0.Name == currentContext }) {
                tableView.selectRowIndexes(IndexSet(integer: currentIndex), byExtendingSelection: false)
                tableView.scrollRowToVisible(currentIndex)
            } else if !matchingContexts.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                tableView.scrollRowToVisible(0)
            } else {
                tableView.deselectAll(nil)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return matchingContexts.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < matchingContexts.count else {
                return nil
            }
            let identifier = NSUserInterfaceItemIdentifier("context-name-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
                let newCell = NSTableCellView()
                newCell.identifier = identifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                newCell.addSubview(textField)
                newCell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                ])
                return newCell
            }()
            cell.textField?.stringValue = matchingContexts[row].Name
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(matchingContexts[row].Name)
            return cell
        }

        @objc private func selectContext(_ sender: NSTableView) {
            selectSelectedContext()
        }

        private func selectSelectedContext() {
            let selectedRow = tableView.selectedRow
            guard selectedRow >= 0, selectedRow < matchingContexts.count else {
                return
            }
            if onSelect(matchingContexts[selectedRow].Name) {
                window?.close()
            }
        }
    }

    final class ContextSearchTableView: NSTableView {
        var onEscape: (() -> Void)?
        var onSelect: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76:
                onSelect?()
            case 53:
                onEscape?()
            default:
                super.keyDown(with: event)
            }
        }
    }
    
    func alertUserWithWarning(message: String) {
        let alert = NSAlert()
        alert.icon = NSImage.init(named: NSImage.cautionName)
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
