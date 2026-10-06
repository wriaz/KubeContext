//
//  KubeContextUITests.swift
//  KubeContextUITests
//
//  Created by Turken, Hasan on 20.10.18.
//  Copyright © 2018 Turken, Hasan. All rights reserved.
//

import XCTest

class KubeContextUITests: XCTestCase {
    var app: XCUIApplication!

    private var testBundle: Bundle {
        Bundle(for: type(of: self))
    }

    private func fixtureURL(named name: String) -> URL? {
        guard let url = testBundle.url(forResource: name, withExtension: "yaml") else {
            XCTFail("Missing UI test fixture: \(name).yaml")
            return nil
        }
        return url
    }

    private func fixtureCurrentContext(named name: String) -> String? {
        guard let url = fixtureURL(named: name) else {
            return nil
        }
        return currentContext(in: url)
    }

    private func currentContext(in kubeconfigURL: URL) -> String? {
        do {
            let contents = try String(contentsOf: kubeconfigURL, encoding: .utf8)
            guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("current-context:") }) else {
                XCTFail("Could not find current-context in kubeconfig at \(kubeconfigURL.path)")
                return nil
            }
            return line.dropFirst("current-context:".count).trimmingCharacters(in: .whitespaces)
        } catch {
            XCTFail("Could not read kubeconfig at \(kubeconfigURL.path): \(error)")
            return nil
        }
    }

    private func activeContextName(from statusItem: XCUIElement) -> String {
        statusItem.click()
        let currentContext = statusItem.menus.menuItems["current-context-name"].label
        statusItem.click()
        return currentContext
    }

    private func assertContexts(in table: XCUIElementQuery, matchFixtureNamed fixtureName: String) {
        guard let url = fixtureURL(named: fixtureName) else {
            return
        }

        let fixtureContent: String
        do {
            fixtureContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("Could not read UI test fixture \(fixtureName).yaml: \(error)")
            return
        }

        let fixtureSections = fixtureContent.components(separatedBy: "contexts:\n")
        guard fixtureSections.count > 1,
              let contexts = fixtureSections[1].components(separatedBy: "\ncurrent-context:").first else {
            XCTFail("Could not find contexts in UI test fixture \(fixtureName).yaml")
            return
        }

        let expectedNames = contexts
            .split(separator: "\n")
            .compactMap { line -> String? in
                let prefix = "  name: "
                guard line.hasPrefix(prefix) else {
                    return nil
                }
                return String(line.dropFirst(prefix.count))
            }
            .map { name -> String in
                guard name.count > 26 else {
                    return name
                }
                return "\(name.prefix(12))...\(name.suffix(11))"
            }

        XCTAssertEqual(table.count, expectedNames.count)
        for name in expectedNames {
            XCTAssertTrue(table[name].exists, "Missing context: \(name)")
        }
    }
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-show-context-name", "YES", "--uitesting"])
        
        app.launch()
        app.activate()
        

        let statusItem = app.statusItems.element
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "KubeContext status item did not become available")
        statusItem.click()
        
        let menuBarsQuery = statusItem.menus
        let selectKubeconfigMenuItem = menuBarsQuery.menuItems["Select kubeconfig file"]
        XCTAssertTrue(selectKubeconfigMenuItem.waitForExistence(timeout: 10), "KubeContext status-bar menu did not become available")
        selectKubeconfigMenuItem.click()
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let menuBarsQuery = statusItem.menus
        let manageContextsMenuItem = menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Manage Contexts"]/*[[".statusItems",".menus.menuItems[\"Manage Contexts\"]",".menuItems[\"Manage Contexts\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/
        manageContextsMenuItem.click()
        let contextManagementWindow = app.windows["Context Management"]
        XCUIElement.perform(withKeyModifiers: .option) {
            contextManagementWindow.buttons["Restore Original"].click()
        }
        
        let alertSheet = contextManagementWindow.sheets["alert"]
        alertSheet.buttons["Yes"].click()
        XCUIApplication().dialogs["alert"].buttons["OK"].click()
        
        
    }

    func testChangeContext() {
        let statusItem = app.statusItems.element
        statusItem.click()
        statusItem.menus.menuItems["Switch Context"].click()

        let switchContextWindow = app.windows["Switch Context"]
        let searchField = switchContextWindow.searchFields["switch-context-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("PROD")

        let results = switchContextWindow.tables["switch-context-results"]
        let productionContext = results.staticTexts["prod-cluster"]
        XCTAssertTrue(productionContext.waitForExistence(timeout: 5))
        XCTAssertFalse(results.staticTexts["minikube"].exists)
        productionContext.click()

        XCTAssertTrue(statusItem.label.contains("prod-cluster"), "The status item should immediately show the selected context")
        statusItem.click()
        XCTAssertTrue(statusItem.menus.menuItems["current-context-name"].label.contains("prod-cluster"))
    }

    func testSwitchContextSearchCanBeClearedAndShowsEmptyState() {
        let statusItem = app.statusItems.element
        statusItem.click()
        statusItem.menus.menuItems["Switch Context"].click()

        let switchContextWindow = app.windows["Switch Context"]
        let searchField = switchContextWindow.searchFields["switch-context-search"]
        let results = switchContextWindow.tables["switch-context-results"]
        XCTAssertTrue(results.staticTexts["minikube"].waitForExistence(timeout: 5))

        searchField.click()
        searchField.typeText("PROD")
        XCTAssertTrue(results.staticTexts["prod-cluster"].waitForExistence(timeout: 5))
        XCTAssertFalse(results.staticTexts["minikube"].exists)

        searchField.clearText()
        XCTAssertTrue(results.staticTexts["minikube"].waitForExistence(timeout: 5))
        XCTAssertTrue(results.staticTexts["prod-cluster"].exists)

        searchField.typeText("no-such-context")
        XCTAssertTrue(switchContextWindow.staticTexts["No matching contexts"].waitForExistence(timeout: 5))

        searchField.clearText()
        XCTAssertTrue(results.staticTexts["minikube"].waitForExistence(timeout: 5))
        switchContextWindow.buttons[XCUIIdentifierCloseWindow].click()
    }

    func testSwitchContextSearchSelectsCurrentContextInitially() {
        guard let currentContext = fixtureCurrentContext(named: "ui-test-config") else {
            return
        }
        let statusItem = app.statusItems.element
        let currentContextBefore = statusItem.label
        statusItem.click()
        statusItem.menus.menuItems["Switch Context"].click()

        let switchContextWindow = app.windows["Switch Context"]
        let results = switchContextWindow.tables["switch-context-results"]
        let currentContextText = results.staticTexts[currentContext]
        XCTAssertTrue(currentContextText.waitForExistence(timeout: 5))
        let currentContextRow = results.descendants(matching: .tableRow)
            .containing(.staticText, identifier: currentContext).firstMatch
        XCTAssertTrue(currentContextRow.exists)
        XCTAssertTrue(currentContextRow.isSelected)
        XCTAssertEqual(statusItem.label, currentContextBefore)

        switchContextWindow.buttons[XCUIIdentifierCloseWindow].click()
    }

    func testSwitchContextKeyboardNavigationAndReturnSelectContext() {
        let statusItem = app.statusItems.element
        statusItem.click()
        statusItem.menus.menuItems["Switch Context"].click()

        let switchContextWindow = app.windows["Switch Context"]
        let searchField = switchContextWindow.searchFields["switch-context-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        let results = switchContextWindow.tables["switch-context-results"]
        let minikube = results.descendants(matching: .tableRow)
            .containing(.staticText, identifier: "minikube").firstMatch
        XCTAssertTrue(minikube.waitForExistence(timeout: 5))
        searchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(minikube.isSelected)
        searchField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(switchContextWindow.waitForNonExistence(timeout: 5))
        let testKubeconfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.ht.kubecontext/Data/Documents/TempData/ui-test-config.yaml")
        XCTAssertEqual(currentContext(in: testKubeconfig), "minikube")
        XCTAssertTrue(statusItem.label.contains("minikube"), "The status item should show the selected context")
    }

    func testSwitchContextEscapeClosesWithoutChangingContext() {
        let statusItem = app.statusItems.element
        let activeContext = activeContextName(from: statusItem)
        statusItem.click()
        statusItem.menus.menuItems["Switch Context"].click()

        let switchContextWindow = app.windows["Switch Context"]
        let searchField = switchContextWindow.searchFields["switch-context-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("cluster")

        let results = switchContextWindow.tables["switch-context-results"]
        let devCluster = results.descendants(matching: .tableRow)
            .containing(.staticText, identifier: "dev-cluster").firstMatch
        XCTAssertTrue(devCluster.waitForExistence(timeout: 5))
        searchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(devCluster.isSelected)
        searchField.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(switchContextWindow.waitForNonExistence(timeout: 5))
        XCTAssertEqual(activeContextName(from: statusItem), activeContext)
    }

    func testSearchContexts() {
        let statusItem = app.statusItems.element
        let activeContext = activeContextName(from: statusItem)
        statusItem.click()
        let menuItems = statusItem.menus.menuItems
        menuItems["Manage Contexts"].click()

        let contextManagementWindow = app.windows["Context Management"]
        let searchField = contextManagementWindow.searchFields["management-search"]
        XCTAssertTrue(searchField.exists)
        let applyButton = contextManagementWindow.buttons["Apply"]
        let revertButton = contextManagementWindow.buttons["Revert"]
        XCTAssertFalse(applyButton.isEnabled)
        XCTAssertFalse(revertButton.isEnabled)

        searchField.click()
        searchField.typeText("MINIKUBE")

        XCTAssertTrue(contextManagementWindow.tables.staticTexts["minikube"].exists)
        XCTAssertFalse(contextManagementWindow.tables.staticTexts["prod-cluster"].exists)
        XCTAssertFalse(applyButton.isEnabled)
        XCTAssertFalse(revertButton.isEnabled)

        searchField.clearText()

        XCTAssertTrue(contextManagementWindow.tables.staticTexts["minikube"].exists)
        XCTAssertTrue(contextManagementWindow.tables.staticTexts["prod-cluster"].exists)
        XCTAssertFalse(applyButton.isEnabled)
        XCTAssertFalse(revertButton.isEnabled)

        let differentContext = activeContext == "minikube" ? "prod-cluster" : "minikube"
        contextManagementWindow.tables.staticTexts[differentContext].click()
        XCTAssertEqual(activeContextName(from: statusItem), activeContext, "Selecting a different managed context must not switch the active context")

        contextManagementWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertFalse(app.alerts["There are changes that have not been applied. Would you like to apply them?"].exists)
    }
    
    func testRenameContext() {
        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        func selectContext(_ name: String) {
            statusItem.click()
            statusItem.menus.menuItems["Switch Context"].click()
            let switchContextWindow = app.windows["Switch Context"]
            let searchField = switchContextWindow.searchFields["switch-context-search"]
            searchField.typeText(name)
            switchContextWindow.tables["switch-context-results"].staticTexts[name].click()
        }
        
        statusItem.click()
        let menuBarsQuery = statusItem.menus
        let manageContextsMenuItem = menuBarsQuery.menuItems["Manage Contexts"]
        manageContextsMenuItem.click()

        
        let contextManagementWindow = app.windows["Context Management"]
        let textField = contextManagementWindow.groups.containing(.textField, identifier:"default").children(matching: .textField).element(boundBy: 0)
        textField.click()
        textField.clearText()
        textField.typeText("docker-of-kubernetes")
        
        let applyButton = contextManagementWindow.buttons["Apply"]
        let revertButton = contextManagementWindow.buttons["Revert"]
        XCTAssertTrue(applyButton.isEnabled)
        XCTAssertTrue(revertButton.isEnabled)
        applyButton.click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        selectContext("docker-of-kubernetes")
        statusItem.click()
        manageContextsMenuItem.click()
        contextManagementWindow.tables.staticTexts["prod-cluster"].click()
        textField.click()
        textField.clearText()
        textField.typeText("my-kube")
        applyButton.click()
        xcuiClosewindowButton.click()
        selectContext("my-kube")
        
        statusItem.click()
        manageContextsMenuItem.click()
        contextManagementWindow.tables.staticTexts["my-kube"].click()
        textField.click()
        textField.clearText()
        textField.typeText("prod-cluster")
        applyButton.click()
        xcuiClosewindowButton.click()
        
        selectContext("prod-cluster")
    }
    
    func testChangeContextDetails() {
        let app = XCUIApplication()
        
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let manageContextsMenuItem = statusItem.menus.menuItems["Manage Contexts"]
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        let gkeDhaasStableStaticText = contextManagementWindow.tables.staticTexts["local-cluster-stable"]
        gkeDhaasStableStaticText.click()
        
        let defaultGroupsQuery = contextManagementWindow.groups.containing(.textField, identifier:"default")
        defaultGroupsQuery.children(matching: .popUpButton).element(boundBy: 0).click()
        
        let minikubeMenuItem = contextManagementWindow/*@START_MENU_TOKEN@*/.menuItems["minikube"]/*[[".groups",".popUpButtons",".menus.menuItems[\"minikube\"]",".menuItems[\"minikube\"]"],[[[-1,3],[-1,2],[-1,1,2],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/
        minikubeMenuItem.click()
        defaultGroupsQuery.children(matching: .popUpButton).element(boundBy: 1).click()
        minikubeMenuItem.click()
        
        let defaultTextField = contextManagementWindow/*@START_MENU_TOKEN@*/.textFields["default"]/*[[".groups.textFields[\"default\"]",".textFields[\"default\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        defaultTextField.doubleClick()
        defaultTextField.clearText()
        defaultTextField.typeText("newns")
        contextManagementWindow.buttons["Apply"].click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["minikube"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"minikube\"]",".staticTexts[\"minikube\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        gkeDhaasStableStaticText.click()
        
        let ns_textfieldname = app.textFields["management-name"]
        XCTAssertEqual(ns_textfieldname.value as! String, "local-cluster-stable")
        
        let ns_textfieldns = app.textFields["management-namespace"]
        XCTAssertEqual(ns_textfieldns.value as! String, "newns")
        
        let ns_popcluster = app.popUpButtons["management-popcluster"]
        XCTAssertEqual(ns_popcluster.value as! String, "minikube")
        
        let ns_popuser = app.popUpButtons["management-popuser"]
        XCTAssertEqual(ns_popuser.value as! String, "minikube")
        
        xcuiClosewindowButton.click()
    }
    
    func testRevertChanges() throws {
        
        let app = XCUIApplication()
        app.statusItems.element.click()
        app.statusItems.element.menus.menuItems["Manage Contexts"].click()
        
        let contextManagementWindow = app.windows["Context Management"]
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["temp-cluster"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"temp-cluster\"]",".staticTexts[\"temp-cluster\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        
        let managementNamespaceGroupsQuery = contextManagementWindow/*@START_MENU_TOKEN@*/.groups.containing(.textField, identifier:"management-namespace")/*[[".groups.containing(.textField, identifier:\"default\")",".groups.containing(.textField, identifier:\"management-namespace\")"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        let textField = managementNamespaceGroupsQuery.children(matching: .textField).element(boundBy: 0)
        textField.click()
        textField.clearText()
        textField.typeText("permanent-cluster")
        managementNamespaceGroupsQuery.children(matching: .popUpButton).element(boundBy: 0).click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.menuItems["docker-for-desktop-cluster"]/*[[".groups",".popUpButtons",".menus.menuItems[\"docker-for-desktop-cluster\"]",".menuItems[\"docker-for-desktop-cluster\"]"],[[[-1,3],[-1,2],[-1,1,2],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/.click()
        managementNamespaceGroupsQuery.children(matching: .popUpButton).element(boundBy: 1).click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.menuItems["real-admin"]/*[[".groups",".popUpButtons",".menus.menuItems[\"real-admin\"]",".menuItems[\"real-admin\"]"],[[[-1,3],[-1,2],[-1,1,2],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/.click()
        let defaultTextField = contextManagementWindow/*@START_MENU_TOKEN@*/.textFields["default"]/*[[".groups.textFields[\"default\"]",".textFields[\"default\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        defaultTextField.doubleClick()
        defaultTextField.clearText()
        defaultTextField.typeText("anotherns")
        contextManagementWindow.buttons["Revert"].click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        
        app.statusItems.element.click()
        app.statusItems.element.menus.menuItems["Manage Contexts"].click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["temp-cluster"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"temp-cluster\"]",".staticTexts[\"temp-cluster\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        
        let ns_textfieldname = app.textFields["management-name"]
        XCTAssertEqual(ns_textfieldname.value as! String, "temp-cluster")
        
        let ns_textfieldns = app.textFields["management-namespace"]
        XCTAssertEqual(ns_textfieldns.value as! String, "default")
        
        let ns_popcluster = app.popUpButtons["management-popcluster"]
        XCTAssertEqual(ns_popcluster.value as! String, "some-other-cluster")
        
        let ns_popuser = app.popUpButtons["management-popuser"]
        XCTAssertEqual(ns_popuser.value as! String, "another-admin")
        
        print("ok")
        
    }
    
    func testAddRemoveContext() {
        print("ok")
        
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let manageContextsMenuItem = statusItem.menus.menuItems["Manage Contexts"]
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["minikube"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"minikube\"]",".staticTexts[\"minikube\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        XCUIApplication().windows["Context Management"].groups["add"].children(matching: .button).element(boundBy: 2).click()
        
        let managementNameTextField = contextManagementWindow/*@START_MENU_TOKEN@*/.textFields["management-name"]/*[[".groups.textFields[\"management-name\"]",".textFields[\"management-name\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        managementNameTextField.click()
        managementNameTextField.clearText()
        managementNameTextField.typeText("new-kube")
        
        let applyButton = contextManagementWindow.buttons["Apply"]
        applyButton.click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        
        let newMinikubeStaticText = contextManagementWindow.tables.staticTexts["new-kube"]
        newMinikubeStaticText.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["docker-for-desktop"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"docker-for-desktop\"]",".staticTexts[\"docker-for-desktop\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        newMinikubeStaticText.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.buttons["remove"]/*[[".groups.buttons[\"remove\"]",".buttons[\"remove\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.click()
        applyButton.click()
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        
        XCTAssert(contextManagementWindow.tables.staticTexts["docker-for-desktop"].exists)
        XCTAssert(contextManagementWindow.tables.staticTexts["minikube"].exists)
        XCTAssert(!contextManagementWindow.tables.staticTexts["new-kube"].exists)
    }
    
    func testRemoveContextWithCleanup() {
        print("ok")
        
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let manageContextsMenuItem = statusItem.menus.menuItems["Manage Contexts"]
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        contextManagementWindow.tables.staticTexts["test-cluster"].click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.buttons["remove"]/*[[".groups.buttons[\"remove\"]",".buttons[\"remove\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.click()
        
        let applyButton = contextManagementWindow.buttons["Apply"]
        applyButton.click()
        
        assertContexts(in: contextManagementWindow.tables.staticTexts, matchFixtureNamed: "ui-test-config-cleaned")
        XCTAssertFalse(contextManagementWindow.tables.staticTexts["test-cluster"].exists)
    }
    
    func testImportFromMenu() {
        print("ok")
        
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let menuBarsQuery = statusItem.menus
        menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Import Kubeconfig File"]/*[[".statusItems",".menus.menuItems[\"Import Kubeconfig File\"]",".menuItems[\"Import Kubeconfig File\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/.click()
        statusItem.click()
        
        let manageContextsMenuItem = menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Manage Contexts"]/*[[".statusItems",".menus.menuItems[\"Manage Contexts\"]",".menuItems[\"Manage Contexts\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["kubernetes-a...es_imported"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"kubernetes-a...es_imported\"]",".staticTexts[\"kubernetes-a...es_imported\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        
        let managementNameTextField = contextManagementWindow/*@START_MENU_TOKEN@*/.textFields["management-name"]/*[[".groups.textFields[\"management-name\"]",".textFields[\"management-name\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        managementNameTextField.doubleClick()
        managementNameTextField.clearText()
        managementNameTextField.typeText("new-added-context")
        contextManagementWindow.buttons["Apply"].click()
        contextManagementWindow.buttons[XCUIIdentifierCloseWindow].click()
        statusItem.click()
        manageContextsMenuItem.click()
        contextManagementWindow.tables.staticTexts["minikube"].click()
        contextManagementWindow.tables.staticTexts["new-added-context"].click()
        
        let ns_textfieldname = app.textFields["management-name"]
        XCTAssertEqual(ns_textfieldname.value as! String, "new-added-context")
        
        let ns_textfieldns = app.textFields["management-namespace"]
        XCTAssertEqual(ns_textfieldns.value as! String, "")
        
        let ns_popcluster = app.popUpButtons["management-popcluster"]
        XCTAssertEqual(ns_popcluster.value as! String, "kubernetes_imported")
        
        let ns_popuser = app.popUpButtons["management-popuser"]
        XCTAssertEqual(ns_popuser.value as! String, "kubernetes-admin_imported")
        
        contextManagementWindow/*@START_MENU_TOKEN@*/.buttons["remove"]/*[[".groups.buttons[\"remove\"]",".buttons[\"remove\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.click()
        let applyButton = contextManagementWindow.buttons["Apply"]
        applyButton.click()
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
    }
    
    func testImportFromManagement() {
        print("ok")
        
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let manageContextsMenuItem = statusItem.menus.menuItems["Manage Contexts"]
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        let importKubeconfigButton = XCUIApplication().windows["Context Management"].groups["add"].children(matching: .button).element(boundBy: 0)
        importKubeconfigButton.click()
        
        let applyButton = contextManagementWindow.buttons["Apply"]
        applyButton.click()
        
        let kubernetesAEsImportedStaticText = contextManagementWindow.tables.staticTexts["kubernetes-a...es_imported"]
        kubernetesAEsImportedStaticText.click()
        
        let removeButton = contextManagementWindow/*@START_MENU_TOKEN@*/.buttons["remove"]/*[[".groups.buttons[\"remove\"]",".buttons[\"remove\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        removeButton.click()
        applyButton.click()
        importKubeconfigButton.click()
        applyButton.click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        kubernetesAEsImportedStaticText.click()
        removeButton.click()
        applyButton.click()
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        
        XCTAssert(!contextManagementWindow.tables.staticTexts["kubernetes-a...es_imported"].exists)
        
        xcuiClosewindowButton.click()
    }
    
    func testRestoreOriginal() {
        print("ok")
        
        let app = XCUIApplication()
        let statusItem = app.statusItems.element
        statusItem.click()
        
        let menuBarsQuery = statusItem.menus
        let manageContextsMenuItem = menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Manage Contexts"]/*[[".statusItems",".menus.menuItems[\"Manage Contexts\"]",".menuItems[\"Manage Contexts\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/
        manageContextsMenuItem.click()
        
        let contextManagementWindow = app.windows["Context Management"]
        let removeButton = contextManagementWindow/*@START_MENU_TOKEN@*/.buttons["remove"]/*[[".groups.buttons[\"remove\"]",".buttons[\"remove\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        removeButton.click()
        removeButton.doubleClick()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["minikube"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"minikube\"]",".staticTexts[\"minikube\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        
        let managementNameTextField = contextManagementWindow/*@START_MENU_TOKEN@*/.textFields["management-name"]/*[[".groups.textFields[\"management-name\"]",".textFields[\"management-name\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        managementNameTextField.doubleClick()
        managementNameTextField.typeText("test")
        
        let applyButton = contextManagementWindow.buttons["Apply"]
        applyButton.click()
        applyButton.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["prod-cluster"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"prod-cluster\"]",".staticTexts[\"prod-cluster\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        
        let managementPopclusterPopUpButton = contextManagementWindow/*@START_MENU_TOKEN@*/.popUpButtons["management-popcluster"]/*[[".groups.popUpButtons[\"management-popcluster\"]",".popUpButtons[\"management-popcluster\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        managementPopclusterPopUpButton.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.menuItems["minikube"]/*[[".groups",".popUpButtons[\"management-popcluster\"]",".menus.menuItems[\"minikube\"]",".menuItems[\"minikube\"]"],[[[-1,3],[-1,2],[-1,1,2],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/.click()
        applyButton.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["local-cluster"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"local-cluster\"]",".staticTexts[\"local-cluster\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        managementPopclusterPopUpButton.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.menuItems["some-other-cluster"]/*[[".groups",".popUpButtons[\"management-popcluster\"]",".menus.menuItems[\"some-other-cluster\"]",".menuItems[\"some-other-cluster\"]"],[[[-1,3],[-1,2],[-1,1,2],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.popUpButtons["management-popuser"]/*[[".groups.popUpButtons[\"management-popuser\"]",".popUpButtons[\"management-popuser\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.click()
        contextManagementWindow.menuItems["real-admin"].click()
        applyButton.click()
        XCUIApplication().windows["Context Management"].groups["add"].children(matching: .button).element(boundBy: 2).click()
        applyButton.click()
        
        let xcuiClosewindowButton = contextManagementWindow.buttons[XCUIIdentifierCloseWindow]
        xcuiClosewindowButton.click()
        statusItem.click()
        manageContextsMenuItem.click()
        XCUIElement.perform(withKeyModifiers: .option) {
            contextManagementWindow.buttons["Restore Original"].click()
        }
        
        let alertSheet = contextManagementWindow.sheets["alert"]
        alertSheet.buttons["Yes"].click()
        XCUIApplication().dialogs["alert"].buttons["OK"].click()
        
        statusItem.click()
        menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Select kubeconfig file"]/*[[".statusItems",".menus.menuItems[\"Select kubeconfig file\"]",".menuItems[\"Select kubeconfig file\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/.click()
        statusItem.click()
        menuBarsQuery.menuItems["Manage Contexts"].click()

        assertContexts(in: contextManagementWindow.tables.staticTexts, matchFixtureNamed: "ui-test-config")
    }
    
    func testChangeKubeconfig() {
        print("ok")
        
        let app = XCUIApplication()
        app.statusItems.element.click()
        
        app.statusItems.element.menus.menuItems["Manage Contexts"].click()
        
        let contextManagementWindow = app.windows["Context Management"]
        let changeButton = contextManagementWindow.buttons["Change"]
        changeButton.click()
        
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["test-cluster"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"test-cluster\"]",".staticTexts[\"test-cluster\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        contextManagementWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["docker-for-desktop"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"docker-for-desktop\"]",".staticTexts[\"docker-for-desktop\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
        changeButton.click()
        contextManagementWindow.click()
        contextManagementWindow.buttons[XCUIIdentifierCloseWindow].click()
        
    }
}

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        
        var deleteString = String()
        for _ in stringValue {
            deleteString += XCUIKeyboardKey.delete.rawValue
        }
        self.typeText(deleteString)
    }
}
