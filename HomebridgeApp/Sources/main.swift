import Cocoa
import WebKit
import CryptoKit
#if canImport(Security)
import Security
#endif

// Headless CI smoke test: when HB_CI_SMOKE=1 or --ci-smoke is present, run minimal checks and exit
if ProcessInfo.processInfo.environment["HB_CI_SMOKE"] == "1" || CommandLine.arguments.contains("--ci-smoke") {
    // Minimal harness – do not touch NSApp / menu bar
    let app = AppDelegate()
    let changed = app.ensureHttpsConfigIfNeeded()

    let sslDir = (app.userDataDir as NSString).appendingPathComponent("ssl")
    let keyPath = (sslDir as NSString).appendingPathComponent("homebridge.key")
    let certPath = (sslDir as NSString).appendingPathComponent("homebridge.crt")
    let cfgPath = (app.userDataDir as NSString).appendingPathComponent("config.json")

    var issues: [String] = []
    if !FileManager.default.fileExists(atPath: keyPath) { issues.append("missing key") }
    if !FileManager.default.fileExists(atPath: certPath) { issues.append("missing cert") }
    if let data = try? Data(contentsOf: URL(fileURLWithPath: cfgPath)),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let platforms = json["platforms"] as? [[String: Any]] {
        let hasSSL = platforms.contains(where: { ($0["platform"] as? String)?.lowercased() == "config" && ($0["ssl"] as? [String: Any]) != nil })
        if !hasSSL { issues.append("config missing ssl block") }
    } else {
        issues.append("config.json not found or invalid")
    }

    if issues.isEmpty {
        print("CI smoke test OK (changed=\(changed))")
        exit(0)
    } else {
        fputs("CI smoke test failed: \(issues.joined(separator: ", "))\n", stderr)
        exit(1)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var statusMenuItem: NSMenuItem!
    var startMenuItem: NSMenuItem!
    var stopMenuItem: NSMenuItem!
    var statusChecker: Timer?
    
    let userDataDir = NSHomeDirectory() + "/Library/Application Support/Homebridge"
    let configFile = NSHomeDirectory() + "/Library/Application Support/Homebridge/.app-config.json"
    
    var currentPort: Int = 8581
    var currentNodeVersion: String = "v24.x"
    var isServiceRunning: Bool = false
    var nodeVersionMenuItem: NSMenuItem!
    var homebridgeVersionMenuItem: NSMenuItem!
    var uiVersionMenuItem: NSMenuItem!
    var pluginsStatusMenuItem: NSMenuItem!
    var httpsToggleMenuItem: NSMenuItem!
    var httpsTrustStatusMenuItem: NSMenuItem!
    var fixHttpsMenuItem: NSMenuItem!
    var hasUpdates: Bool = false
    private var httpsTrusted: Bool = true
    private var cachedAuthToken: String?
    private var useHTTPS: Bool = false
    private var urlSession: URLSession = URLSession.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from terminating when there are no windows
        NSApp.setActivationPolicy(.accessory)
        
        loadConfig()
        // Ensure HTTPS self-signed cert and config are present (best-effort)
        let httpsChanged = ensureHttpsConfigIfNeeded()
        setupNetworking()
        setupMenuBar()
        
        // Update HTTPS menu item title based on detected state
        httpsToggleMenuItem.title = "HTTPS: \(useHTTPS ? "Enabled" : "Disabled")"
        
        checkServiceStatus()
        // If HTTPS config was just applied and service is running, restart so it picks up SSL
        if httpsChanged && isServiceRunning {
            stopServiceQuiet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startService()
            }
        }
        
        // Check status every 3 seconds
        statusChecker = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkServiceStatus()
        }
    }
    
    @objc func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func loadConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            currentPort = json["uiPort"] as? Int ?? 8581
            currentNodeVersion = json["nodeVersion"] as? String ?? "v20.x"
        }
        
        // Detect if HTTPS is enabled by checking Homebridge config.json
        detectHTTPSFromConfig()
    }
    
    func detectHTTPSFromConfig() {
        let homebridgeConfigPath = (userDataDir as NSString).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: homebridgeConfigPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let platforms = json["platforms"] as? [[String: Any]] else {
            useHTTPS = false
            return
        }
        
        // Check if config platform has SSL configured
        for platform in platforms {
            if (platform["platform"] as? String)?.lowercased() == "config",
               let ssl = platform["ssl"] as? [String: Any],
               ssl["key"] != nil && ssl["cert"] != nil {
                useHTTPS = true
                // Also update port if different
                if let port = platform["port"] as? Int, port != currentPort {
                    currentPort = port
                }
                return
            }
        }
        useHTTPS = false
    }
    
    func saveConfig() {
        let config: [String: Any] = [
            "uiPort": currentPort,
            "nodeVersion": currentNodeVersion
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
            try? FileManager.default.createDirectory(atPath: userDataDir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: configFile))
        }
    }
    
    func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Use the house emoji as icon (or you could use an image)
            button.title = "🏠"
            button.toolTip = "Homebridge"
        }
        
        // Create menu
        menu = NSMenu()
        
        // Status item (shows if running/stopped)
        statusMenuItem = NSMenuItem(title: "⏳ Checking status...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Version info section
        nodeVersionMenuItem = NSMenuItem(title: "Node.js: Checking...", action: nil, keyEquivalent: "")
        nodeVersionMenuItem.isEnabled = false
        menu.addItem(nodeVersionMenuItem)
        
        homebridgeVersionMenuItem = NSMenuItem(title: "Homebridge: Checking...", action: nil, keyEquivalent: "")
        homebridgeVersionMenuItem.isEnabled = false
        menu.addItem(homebridgeVersionMenuItem)
        
        uiVersionMenuItem = NSMenuItem(title: "Homebridge UI: Checking...", action: nil, keyEquivalent: "")
        uiVersionMenuItem.isEnabled = false
        menu.addItem(uiVersionMenuItem)
        
        pluginsStatusMenuItem = NSMenuItem(title: "Plugins: Checking...", action: nil, keyEquivalent: "")
        pluginsStatusMenuItem.isEnabled = false
        menu.addItem(pluginsStatusMenuItem)
        
        // HTTPS trust status (only show when HTTPS is enabled)
        httpsTrustStatusMenuItem = NSMenuItem(title: "HTTPS: Checking trust...", action: nil, keyEquivalent: "")
        httpsTrustStatusMenuItem.isEnabled = false
        httpsTrustStatusMenuItem.isHidden = true
        menu.addItem(httpsTrustStatusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Start Service
        startMenuItem = NSMenuItem(title: "▶ Start Service", action: #selector(startService), keyEquivalent: "s")
        startMenuItem.target = self
        menu.addItem(startMenuItem)
        
        // Stop Service
        stopMenuItem = NSMenuItem(title: "⏹ Stop Service", action: #selector(stopService), keyEquivalent: "t")
        stopMenuItem.target = self
        menu.addItem(stopMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Web UI
        let openUIItem = NSMenuItem(title: "🌐 Open Web UI", action: #selector(openWebUI), keyEquivalent: "o")
        openUIItem.target = self
        menu.addItem(openUIItem)
        
        // Fix HTTPS Trust (shown when HTTPS is enabled but not trusted)
        fixHttpsMenuItem = NSMenuItem(title: "🔒 Fix HTTPS Trust...", action: #selector(fixHttpsTrust), keyEquivalent: "")
        fixHttpsMenuItem.target = self
        fixHttpsMenuItem.isHidden = true
        menu.addItem(fixHttpsMenuItem)

    // Open Terminal (UI)
    let openTerminalItem = NSMenuItem(title: "🖥️ Open Terminal", action: #selector(openTerminal), keyEquivalent: "")
    openTerminalItem.target = self
    menu.addItem(openTerminalItem)
        
        // View Logs
        let logsItem = NSMenuItem(title: "📄 View Logs", action: #selector(viewLogs), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)
        
        // Open Data Folder
        let dataFolderItem = NSMenuItem(title: "📁 Open Data Folder", action: #selector(openDataFolder), keyEquivalent: "d")
        dataFolderItem.target = self
        menu.addItem(dataFolderItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings submenu
        let settingsItem = NSMenuItem(title: "⚙️ Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        
        let portItem = NSMenuItem(title: "UI Port: \(currentPort)", action: #selector(changePort), keyEquivalent: "")
        portItem.target = self
        settingsMenu.addItem(portItem)

    // HTTPS toggle
    let httpsTitle = "HTTPS: " + (useHTTPS ? "Enabled" : "Disabled")
    httpsToggleMenuItem = NSMenuItem(title: httpsTitle, action: #selector(toggleHTTPS), keyEquivalent: "")
        httpsToggleMenuItem.target = self
        settingsMenu.addItem(httpsToggleMenuItem)

        // Regenerate certificate
        let regenCertItem = NSMenuItem(title: "Regenerate Certificate…", action: #selector(regenerateCertificate), keyEquivalent: "")
        regenCertItem.target = self
        settingsMenu.addItem(regenCertItem)

        // Trust certificate in Keychain
        let trustCertItem = NSMenuItem(title: "Trust Certificate in Keychain…", action: #selector(trustCertificateInKeychain), keyEquivalent: "")
        trustCertItem.target = self
        settingsMenu.addItem(trustCertItem)
        
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Homebridge", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func checkServiceStatus() {
        // Sync currentPort from Homebridge config.json if it has changed (authoritative source)
        if let cfgPort = readUIPortFromConfig(), cfgPort != currentPort {
            currentPort = cfgPort
            // Reflect new port in Settings menu ASAP on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let settingsItem = self.menu.item(withTitle: "⚙️ Settings"),
                   let settingsMenu = settingsItem.submenu,
                   let portItem = settingsMenu.item(at: 0) {
                    portItem.title = "UI Port: \(self.currentPort)"
                }
            }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti:\(currentPort)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        var isRunning = false
        do {
            try task.run()
            task.waitUntilExit()
            isRunning = task.terminationStatus == 0
        } catch {
            isRunning = false
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isServiceRunning = isRunning
            
            if isRunning {
                self.statusMenuItem.title = "🟢 Running on port \(self.currentPort)"
                self.startMenuItem.title = "🔄 Restart Service"
                self.startMenuItem.isEnabled = true
                self.stopMenuItem.isEnabled = true
                self.updateMenuBarIcon()
                
                // Check versions when service is running
                self.checkVersions()
                
                // Check HTTPS trust if enabled
                if self.useHTTPS {
                    self.checkHttpsTrust()
                }
            } else {
                self.statusMenuItem.title = "🔴 Stopped"
                self.startMenuItem.title = "▶ Start Service"
                self.startMenuItem.isEnabled = true
                self.stopMenuItem.isEnabled = false
                if let button = self.statusItem.button {
                    button.title = "🏠"
                }
            }
        }
    }

    // Reads the UI port from Homebridge config.json (platforms[platform=="config"].port)
    func readUIPortFromConfig() -> Int? {
        let configPath = (userDataDir as NSString).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let platforms = json["platforms"] as? [[String: Any]] else {
            return nil
        }
        for platform in platforms {
            if (platform["platform"] as? String)?.lowercased() == "config",
               let port = platform["port"] as? Int {
                return port
            }
        }
        return nil
    }
    
    func updateMenuBarIcon() {
        if let button = self.statusItem.button {
            if !httpsTrusted && useHTTPS {
                // Show lock warning when HTTPS isn't trusted
                button.title = "🏠🔓"
            } else if hasUpdates {
                // Show green with a badge indicator
                button.title = "🟢⚠️"
            } else if isServiceRunning {
                button.title = "🟢"
            } else {
                button.title = "🏠"
            }
        }
    }

    // MARK: - Auth Helper (UIX JWT)
    // Create a short-lived cached token using the UIX secret so API calls work when auth is enabled
    func getAuthToken() -> String? {
        // Return cached token if present (very lightweight caching, token has no exp so keep simple)
        if let token = cachedAuthToken { return token }

        let secretsPath = (userDataDir as NSString).appendingPathComponent(".uix-secrets")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: secretsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secretKey = json["secretKey"] as? String, !secretKey.isEmpty else {
            return nil
        }

        // Build header and payload
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "username": "homebridge-macos-pkg",
            "name": "homebridge-macos-pkg",
            "admin": true,
            "instanceId": "xxxxxxxx"
        ]

        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        let headerB64 = headerData.base64URLEncodedString()
        let payloadB64 = payloadData.base64URLEncodedString()
        let signingInput = "\(headerB64).\(payloadB64)"

        // Sign using HMAC-SHA256 with the UIX secret key
        guard let keyData = secretKey.data(using: .utf8) else { return nil }
        let symmetricKey = SymmetricKey(data: keyData)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: symmetricKey)
        let signatureB64 = Data(sig).base64URLEncodedString()

        let token = "\(signingInput).\(signatureB64)"
        cachedAuthToken = token
        return token
    }

    func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        if let token = getAuthToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    func checkVersions() {
        // Check Node.js version
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let bundlePath = Bundle.main.bundlePath as String? else { return }
            
            let nodeBin = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks/node/bin/node")
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: nodeBin)
            task.arguments = ["--version"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    DispatchQueue.main.async {
                        self.nodeVersionMenuItem.title = "Node.js: \(version)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.nodeVersionMenuItem.title = "Node.js: Unknown"
                }
            }
        }
        
        // Check Homebridge and UI versions
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let packageJsonPath = (self.userDataDir as NSString).appendingPathComponent("node_modules/homebridge/package.json")
            let uiPackageJsonPath = (self.userDataDir as NSString).appendingPathComponent("node_modules/homebridge-config-ui-x/package.json")
            
            // Read Homebridge version
            if let data = try? Data(contentsOf: URL(fileURLWithPath: packageJsonPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                DispatchQueue.main.async {
                    self.homebridgeVersionMenuItem.title = "Homebridge: v\(version) ✓"
                }
            } else {
                DispatchQueue.main.async {
                    self.homebridgeVersionMenuItem.title = "Homebridge: Not installed"
                }
            }
            
            // Read UI version
            if let data = try? Data(contentsOf: URL(fileURLWithPath: uiPackageJsonPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                DispatchQueue.main.async {
                    self.uiVersionMenuItem.title = "Homebridge UI: v\(version) ✓"
                }
            } else {
                DispatchQueue.main.async {
                    self.uiVersionMenuItem.title = "Homebridge UI: Not installed"
                }
            }
            
            // Check for outdated plugins
            self.checkPluginUpdates()
        }
    }
    
    func checkPluginUpdates() {
        // If service is running, check via API
        if isServiceRunning {
            checkUpdatesViaAPI { [weak self] totalUpdates in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if totalUpdates == 0 {
                        self.pluginsStatusMenuItem.title = "Plugins: All up to date ✓"
                        self.hasUpdates = false
                    } else {
                        self.pluginsStatusMenuItem.title = "\(totalUpdates) update(s) available ⚠️"
                        self.hasUpdates = true
                    }
                    self.updateMenuBarIcon()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pluginsStatusMenuItem.title = "Plugins: Service not running"
                self.hasUpdates = false
                self.updateMenuBarIcon()
            }
        }
    }
    
    func checkUpdatesViaAPI(completion: @escaping (Int) -> Void) {
        let proto = useHTTPS ? "https" : "http"
        let host = useHTTPS ? "127.0.0.1" : "localhost"
        guard let url = URL(string: "\(proto)://\(host):\(currentPort)/api/status/nodejs") else {
            completion(0)
            return
        }

        let request = authorizedRequest(url)

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, error == nil, let data = data else {
                completion(0)
                return
            }
            
            var updateCount = 0
            
            // Parse the response to check for updates
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check Node.js update
                if let updateAvailable = json["updateAvailable"] as? Bool, updateAvailable {
                    updateCount += 1
                }
            }
            
            // Also check Homebridge core updates
            self.checkHomebridgeUpdate { hasUpdate in
                if hasUpdate {
                    updateCount += 1
                }
                
                // Check plugin updates
                self.checkPluginsUpdateAPI { pluginCount in
                    completion(updateCount + pluginCount)
                }
            }
        }
        task.resume()
    }
    
    func checkHomebridgeUpdate(completion: @escaping (Bool) -> Void) {
        let proto = useHTTPS ? "https" : "http"
        let host = useHTTPS ? "127.0.0.1" : "localhost"
        guard let url = URL(string: "\(proto)://\(host):\(currentPort)/api/status/homebridge-version") else {
            completion(false)
            return
        }

        let request = authorizedRequest(url)

        let task = urlSession.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let updateAvailable = json["updateAvailable"] as? Bool else {
                completion(false)
                return
            }
            completion(updateAvailable)
        }
        task.resume()
    }
    
    func checkPluginsUpdateAPI(completion: @escaping (Int) -> Void) {
        let proto = useHTTPS ? "https" : "http"
        let host = useHTTPS ? "127.0.0.1" : "localhost"
        guard let url = URL(string: "\(proto)://\(host):\(currentPort)/api/plugins") else {
            completion(0)
            return
        }

        let request = authorizedRequest(url)

        let task = urlSession.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data = data,
                  let plugins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(0)
                return
            }
            
            // Count plugins with updateAvailable flag
            let outdatedCount = plugins.filter { plugin in
                return plugin["updateAvailable"] as? Bool == true
            }.count
            
            completion(outdatedCount)
        }
        task.resume()
    }
    
    @objc func changePort() {
        let alert = NSAlert()
        alert.messageText = "Change UI Port"
        alert.informativeText = "Enter the new port for the Homebridge UI:\n\nThe service will automatically restart with the new port."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "\(currentPort)"
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let newPort = Int(input.stringValue), newPort > 0, newPort < 65536 {
                let wasRunning = isServiceRunning
                
                currentPort = newPort
                saveConfig()
                
                // Update config.json
                updateHomebridgeConfig(port: newPort)
                
                // Update menu item
                if let settingsItem = menu.item(withTitle: "⚙️ Settings"),
                   let settingsMenu = settingsItem.submenu,
                   let portItem = settingsMenu.item(at: 0) {
                    portItem.title = "UI Port: \(currentPort)"
                }
                
                // If service was running, restart it
                if wasRunning {
                    statusMenuItem.title = "⏳ Restarting service..."
                    
                    // Stop service
                    stopServiceQuiet()
                    
                    // Wait a moment then start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.startService()
                        
                        // Wait for service to start, then open UI
                        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
                            guard let self = self else { return }
                            if self.isServiceRunning {
                                self.openWebUI()
                            }
                        }
                    }
                }
            }
        }
    }
    
    func stopServiceQuiet() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "hb-service"]
        try? task.run()
        task.waitUntilExit()
    }
    
    func updateHomebridgeConfig(port: Int) {
        let configPath = (userDataDir as NSString).appendingPathComponent("config.json")
        
        // Read existing config
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Update port in platforms section
        if var platforms = config["platforms"] as? [[String: Any]] {
            for (index, var platform) in platforms.enumerated() {
                if platform["platform"] as? String == "config" {
                    platform["port"] = port
                    platforms[index] = platform
                    break
                }
            }
            config["platforms"] = platforms
        }
        
        // Write back
        if let updatedData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // Enable / Disable HTTPS in config and restart if running
    @objc func toggleHTTPS() {
        let enabledBefore = useHTTPS
        var changed = false
        if enabledBefore {
            // Disable: remove ssl block from UI config
            changed = updateHomebridgeConfigSSL(enable: false)
            useHTTPS = false
        } else {
            // Enable: ensure cert and ssl config
            changed = ensureHttpsConfigIfNeeded()
            useHTTPS = true
        }

        // Update menu title
        httpsToggleMenuItem.title = "HTTPS: \(useHTTPS ? "Enabled" : "Disabled")"

        // Restart service if running and config changed
        if changed && isServiceRunning {
            statusMenuItem.title = "⏳ Applying settings..."
            stopServiceQuiet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startService()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.checkServiceStatus()
                }
            }
        }
    }

    func updateHomebridgeConfigSSL(enable: Bool) -> Bool {
        let configPath = (userDataDir as NSString).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var changed = false
        var platforms = (config["platforms"] as? [[String: Any]]) ?? []
        var uiIndex = platforms.firstIndex(where: { ($0["platform"] as? String)?.lowercased() == "config" })
        if uiIndex == nil {
            platforms.append(["platform": "config", "name": "Config", "port": currentPort])
            uiIndex = platforms.count - 1
        }
        if let idx = uiIndex {
            var ui = platforms[idx]
            if enable {
                let sslDir = (userDataDir as NSString).appendingPathComponent("ssl")
                let keyPath = (sslDir as NSString).appendingPathComponent("homebridge.key")
                let certPath = (sslDir as NSString).appendingPathComponent("homebridge.crt")
                // ensure files exist
                _ = ensureHttpsConfigIfNeeded()
                var ssl = (ui["ssl"] as? [String: Any]) ?? [:]
                if (ssl["key"] as? String) != keyPath || (ssl["cert"] as? String) != certPath {
                    ssl["key"] = keyPath
                    ssl["cert"] = certPath
                    ui["ssl"] = ssl
                    platforms[idx] = ui
                    changed = true
                }
            } else {
                if ui["ssl"] != nil {
                    ui.removeValue(forKey: "ssl")
                    platforms[idx] = ui
                    changed = true
                }
            }
        }
        if changed {
            config["platforms"] = platforms
            if let out = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
                try? out.write(to: URL(fileURLWithPath: configPath))
            }
        }
        return changed
    }
    
    @objc func regenerateCertificate() {
        let sslDir = (userDataDir as NSString).appendingPathComponent("ssl")
        let keyPath = (sslDir as NSString).appendingPathComponent("homebridge.key")
        let certPath = (sslDir as NSString).appendingPathComponent("homebridge.crt")
        let caKeyPath = (sslDir as NSString).appendingPathComponent("ca.key")
        let caCertPath = (sslDir as NSString).appendingPathComponent("ca.crt")
        
        // Remove existing certificate files
        if FileManager.default.fileExists(atPath: keyPath) {
            try? FileManager.default.removeItem(atPath: keyPath)
        }
        if FileManager.default.fileExists(atPath: certPath) {
            try? FileManager.default.removeItem(atPath: certPath)
        }
        // Also remove local CA so we fully reissue chain
        if FileManager.default.fileExists(atPath: caKeyPath) {
            try? FileManager.default.removeItem(atPath: caKeyPath)
        }
        if FileManager.default.fileExists(atPath: caCertPath) {
            try? FileManager.default.removeItem(atPath: caCertPath)
        }
        
        // Recreate CA and cert; ensure config points to them
        _ = ensureHttpsConfigIfNeeded()
        useHTTPS = true
        httpsToggleMenuItem.title = "HTTPS: Enabled"
        
        // Trust certificate (prefers trusting CA when present)
        trustCertificateInKeychain()
        
        if isServiceRunning {
            statusMenuItem.title = "⏳ Applying new certificate..."
            stopServiceQuiet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startService()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.checkServiceStatus()
                    // Open the UI to validate HTTPS works
                    self?.openWebUI()
                    self?.showInfo("A new HTTPS certificate has been generated, trusted in your Keychain, and applied. If your browser had issues, quit and reopen it, then try again.")
                }
            }
        } else {
            // Start the service and open UI so user can confirm
            startService()
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
                self?.openWebUI()
            }
        }
    }

    @objc func trustCertificateInKeychain() {
        let sslDir = (userDataDir as NSString).appendingPathComponent("ssl")
        let certPath = (sslDir as NSString).appendingPathComponent("homebridge.crt")
        // Ensure cert exists
        if !FileManager.default.fileExists(atPath: certPath) {
            _ = ensureHttpsConfigIfNeeded()
        }
        if !FileManager.default.fileExists(atPath: certPath) {
            showError("Certificate not found. Try regenerating it first.")
            return
        }

        // Attempt to add as trusted cert to login keychain (prefer trusting CA if present)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let keychainPath = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
            let caCertPath = (sslDir as NSString).appendingPathComponent("ca.crt")
            let certToTrust = FileManager.default.fileExists(atPath: caCertPath) ? caCertPath : certPath

            // First remove any existing localhost certs to avoid duplicates
            let deleteTask = Process()
            deleteTask.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            deleteTask.arguments = ["delete-certificate", "-c", "localhost", "-t", keychainPath]
            try? deleteTask.run()
            deleteTask.waitUntilExit()

            // Now add and explicitly trust for SSL (login keychain)
            let addTask = Process()
            addTask.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            addTask.arguments = [
                "add-trusted-cert",
                "-d",                 // add to keychain and set trust settings
                "-r", "trustRoot",   // trust as root
                "-p", "ssl",         // explicitly trust for SSL
                "-p", "basic",       // and for basic usage
                "-k", keychainPath,
                certToTrust
            ]
            let pipe = Pipe()
            addTask.standardOutput = pipe
            addTask.standardError = pipe
            do {
                try addTask.run()
                addTask.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                // Attempt to also trust in System keychain (requires admin; will prompt)
                var systemTrustMessage = ""
                if addTask.terminationStatus == 0 {
                    let script = "do shell script \"/usr/bin/security add-trusted-cert -d -r trustRoot -p ssl -p basic -k /Library/Keychains/System.keychain \" & quoted form of \"\(certToTrust)\" with administrator privileges"
                    let osa = Process()
                    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    osa.arguments = ["-e", script]
                    let osaPipe = Pipe(); osa.standardOutput = osaPipe; osa.standardError = osaPipe
                    do { try osa.run(); osa.waitUntilExit() } catch {}
                    if osa.terminationStatus == 0 {
                        systemTrustMessage = "\nAlso installed to the System keychain for Safari."
                    }
                }
                DispatchQueue.main.async {
                    if addTask.terminationStatus == 0 {
                        self.showInfo("Certificate trusted in your login Keychain. If Safari was open, quit and reopen it, then try again." + systemTrustMessage)
                    } else {
                        self.showError("Failed to trust certificate. Output:\n\(output)\nYou can also trust it manually in Keychain Access.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError("Failed to run security tool: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func startService() {
        // If service is running, restart it
        if isServiceRunning {
            statusMenuItem.title = "⏳ Restarting service..."
            stopServiceQuiet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startServiceInternal()
            }
            return
        }
        
        startServiceInternal()
    }
    
    func startServiceInternal() {
        // Disable start button and show status
        startMenuItem.isEnabled = false
        statusMenuItem.title = "⏳ Starting service..."
        
        // Get the actual app bundle path
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            showError("Failed to locate app bundle")
            startMenuItem.isEnabled = true
            return
        }
        
        let bundleNodeDir = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks/node/bin")
        
        let script = """
        #!/bin/bash
        set -e
        BUNDLE_NODE_DIR="\(bundleNodeDir)"
        export PATH="$BUNDLE_NODE_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
        NODE_BIN="$BUNDLE_NODE_DIR/node"
        NPM_BIN="$BUNDLE_NODE_DIR/npm"
        
        # Fallback to system node/npm if bundled ones don't exist
        if [ ! -x "$NODE_BIN" ] || [ ! -x "$NPM_BIN" ]; then
            NODE_BIN="$(command -v node || true)"
            NPM_BIN="$(command -v npm || true)"
        fi
        
        if [ -z "$NODE_BIN" ] || [ -z "$NPM_BIN" ]; then
            echo "Node.js or npm not found. Please install Node.js or use a bundle with Node embedded."
            exit 1
        fi
        
        export HOMEBRIDGE_CONFIG_UI_TERMINAL=1
        export HOMEBRIDGE_CONFIG_UI_TERMINAL_ENABLED=1
        cd "\(userDataDir)"
        
        # Install if needed
        if [ ! -d "node_modules/homebridge" ] || [ ! -f "node_modules/homebridge-config-ui-x/dist/bin/hb-service.js" ]; then
            echo "Installing Homebridge packages..."
            "$NPM_BIN" install --no-fund --no-audit homebridge@latest homebridge-config-ui-x@latest
        fi

        # Provide hb-service wrapper in PATH for UI Terminal
        mkdir -p "bin"
        cat > "bin/hb-service" <<HBSERVICE
        #!/usr/bin/env bash
        NODE_BIN="\(bundleNodeDir)/node"
        if [ ! -x "$NODE_BIN" ]; then
            NODE_BIN="\\$(command -v node)"
        fi
        exec "$NODE_BIN" "\(userDataDir)/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js" "\\$@"
        HBSERVICE
        chmod +x "bin/hb-service"
        export PATH="$(pwd)/bin:$PATH"
        
        # Start service in background
        "$NODE_BIN" \
            node_modules/homebridge-config-ui-x/dist/bin/hb-service.js \
            run -I -U "\(userDataDir)" -P "\(userDataDir)/node_modules" \
            > homebridge.log 2>&1 &
        
        echo "Service started with PID $!"
        """
        
        let scriptPath = userDataDir + "/.start-service.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: String.Encoding.utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            showError("Failed to create start script: \(error.localizedDescription)")
            startMenuItem.isEnabled = true
            return
        }
        
        // Run in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptPath]
            
            // Capture output for debugging
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                // Read output
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("Start service output: \(output)")
                    // Also append to log file
                    let logPath = (userDataDir as NSString).appendingPathComponent("start-service-debug.log")
                    try? output.write(toFile: logPath, atomically: true, encoding: String.Encoding.utf8)
                }
                
                DispatchQueue.main.async {
                    if task.terminationStatus != 0 {
                        self.showError("Service failed to start. Check logs at:\n\(self.userDataDir)/homebridge.log\n\(self.userDataDir)/start-service-debug.log")
                        self.startMenuItem.isEnabled = true
                    } else {
                        self.statusMenuItem.title = "⏳ Waiting for service to start..."
                        // Wait longer for service to fully initialize (5 seconds)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.checkServiceStatus()
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError("Failed to start service: \(error.localizedDescription)")
                    self.startMenuItem.isEnabled = true
                }
            }
        }
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func showInfo(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Info"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc func stopService() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "hb-service"]
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Ignore errors - service might not be running
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkServiceStatus()
        }
    }
    
    @objc func openWebUI() {
        if useHTTPS {
            // Validate HTTPS with a clean session (no trust override)
            isHttpsReachable { [weak self] ok in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if ok {
                        NSWorkspace.shared.open(URL(string: "https://127.0.0.1:\(self.currentPort)")!)
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Cannot Open Secure Connection"
                        alert.informativeText = "Your browser may not trust the local HTTPS certificate yet. You can trust the certificate now (recommended) or open the UI over HTTP this time."
                        alert.addButton(withTitle: "Trust Certificate…")
                        alert.addButton(withTitle: "Open via HTTP")
                        alert.addButton(withTitle: "Cancel")
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            self.trustCertificateInKeychain()
                        } else if response == .alertSecondButtonReturn {
                            NSWorkspace.shared.open(URL(string: "http://localhost:\(self.currentPort)")!)
                        }
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "http://localhost:\(currentPort)")!)
        }
    }
    
    @objc func openTerminal() {
        let proto = useHTTPS ? "https" : "http"
        let host = useHTTPS ? "127.0.0.1" : "localhost"
        NSWorkspace.shared.open(URL(string: "\(proto)://\(host):\(currentPort)/platform-tools/terminal")!)
    }

        // Check HTTPS reachability without bypassing trust, to detect real browser behavior
    func isHttpsReachable(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://127.0.0.1:\(currentPort)") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let session = URLSession(configuration: .default) // no delegate: normal trust rules
        let task = session.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, (200..<600).contains(http.statusCode) {
                completion(true)
            } else {
                // Common SSL error codes: -1200..-1206
                _ = error // keep for potential logging
                completion(false)
            }
        }
        task.resume()
    }
    
    // Check and update HTTPS trust status
    func checkHttpsTrust() {
        isHttpsReachable { [weak self] trusted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.httpsTrusted = trusted
                self.updateHttpsTrustUI()
            }
        }
    }
    
    // Update menu items and icon based on HTTPS trust status
    func updateHttpsTrustUI() {
        if useHTTPS {
            httpsTrustStatusMenuItem.isHidden = false
            fixHttpsMenuItem.isHidden = httpsTrusted
            
            if httpsTrusted {
                httpsTrustStatusMenuItem.title = "HTTPS: Trusted ✓"
            } else {
                httpsTrustStatusMenuItem.title = "HTTPS: Not Trusted ⚠️"
            }
        } else {
            httpsTrustStatusMenuItem.isHidden = true
            fixHttpsMenuItem.isHidden = true
        }
        updateMenuBarIcon()
    }
    
    @objc func fixHttpsTrust() {
        let alert = NSAlert()
        alert.messageText = "Fix HTTPS Trust"
        alert.informativeText = "This will trust the Homebridge HTTPS certificate in your keychain and may prompt for admin access to install into the System keychain for better Safari compatibility."
        alert.addButton(withTitle: "Trust Certificate")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            trustCertificateInKeychain()
            // Recheck after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.checkHttpsTrust()
            }
        }
    }

    @objc func viewLogs() {
        let logPath = userDataDir + "/homebridge.log"
        if FileManager.default.fileExists(atPath: logPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        } else {
            let alert = NSAlert()
            alert.messageText = "No Logs Found"
            alert.informativeText = "Log file will be created when service starts."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc func openDataFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: userDataDir)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Utilities
extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - HTTPS & Networking Helpers
extension AppDelegate: URLSessionDelegate {
    // Create a URLSession that trusts the self-signed cert for localhost only
    func setupNetworking() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           (challenge.protectionSpace.host == "localhost" || challenge.protectionSpace.host == "127.0.0.1"),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }

    // Ensure ssl cert exists and config.json includes ssl key/cert
    @discardableResult
    func ensureHttpsConfigIfNeeded() -> Bool {
        let sslDir = (userDataDir as NSString).appendingPathComponent("ssl")
        let keyPath = (sslDir as NSString).appendingPathComponent("homebridge.key")
        let certPath = (sslDir as NSString).appendingPathComponent("homebridge.crt")
        let caKeyPath = (sslDir as NSString).appendingPathComponent("ca.key")
        let caCertPath = (sslDir as NSString).appendingPathComponent("ca.crt")
        let csrPath = (sslDir as NSString).appendingPathComponent("homebridge.csr")
        var changed = false

        // Create ssl directory
        try? FileManager.default.createDirectory(atPath: sslDir, withIntermediateDirectories: true)

        let keyExists = FileManager.default.fileExists(atPath: keyPath)
        let certExists = FileManager.default.fileExists(atPath: certPath)
        let caExists = FileManager.default.fileExists(atPath: caCertPath) && FileManager.default.fileExists(atPath: caKeyPath)

        // Write openssl config used for SAN and CA
        let cnfPath = (sslDir as NSString).appendingPathComponent("openssl.cnf")
        let cnf = """
        [req]
        default_bits = 2048
        prompt = no
        default_md = sha256
        distinguished_name = dn
        req_extensions = v3_req

        [dn]
        C = US
        ST = Local
        L = Local
        O = Homebridge
        CN = localhost

        [v3_req]
        keyUsage = keyEncipherment, dataEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names

        [alt_names]
        DNS.1 = localhost
        IP.1 = 127.0.0.1
        IP.2 = ::1

        [v3_ca]
        basicConstraints = critical, CA:true
        keyUsage = critical, keyCertSign, cRLSign
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid:always,issuer
        """
        try? cnf.write(toFile: cnfPath, atomically: true, encoding: .utf8)

        // Ensure a local CA exists (for better Safari compatibility)
        if !caExists {
            let caProc = Process()
            caProc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            caProc.arguments = [
                "req", "-x509", "-nodes", "-days", "3650",
                "-newkey", "rsa:2048",
                "-subj", "/C=US/ST=Local/L=Local/O=Homebridge/CN=Homebridge Local CA",
                "-keyout", caKeyPath,
                "-out", caCertPath,
                "-extensions", "v3_ca",
                "-config", cnfPath
            ]
            let pipe = Pipe(); caProc.standardOutput = pipe; caProc.standardError = pipe
            do { try caProc.run(); caProc.waitUntilExit() } catch {}
            changed = true
        }

        // Ensure server key and a CA-signed certificate exist
        if !keyExists {
            let genKey = Process()
            genKey.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            genKey.arguments = ["genrsa", "-out", keyPath, "2048"]
            try? genKey.run(); genKey.waitUntilExit()
            changed = true
        }

        if !certExists {
            // CSR
            let csr = Process()
            csr.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            csr.arguments = [
                "req", "-new",
                "-key", keyPath,
                "-out", csrPath,
                "-config", cnfPath
            ]
            try? csr.run(); csr.waitUntilExit()

            // Sign with local CA
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            sign.arguments = [
                "x509", "-req", "-in", csrPath,
                "-CA", caCertPath, "-CAkey", caKeyPath, "-CAcreateserial",
                "-out", certPath, "-days", "825",
                "-extensions", "v3_req", "-extfile", cnfPath
            ]
            try? sign.run(); sign.waitUntilExit()
            // Cleanup CSR
            try? FileManager.default.removeItem(atPath: csrPath)
            changed = true
        }

        // Update config.json
        let cfgPath = (userDataDir as NSString).appendingPathComponent("config.json")
        var cfgChanged = false
        var cfg: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cfgPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cfg = json
        }
        var platforms = (cfg["platforms"] as? [[String: Any]]) ?? []
        var uiIndex = platforms.firstIndex(where: { ($0["platform"] as? String)?.lowercased() == "config" })
        if uiIndex == nil {
            platforms.append(["platform": "config", "name": "Config", "port": currentPort])
            uiIndex = platforms.count - 1
        }
        if let idx = uiIndex {
            var ui = platforms[idx]
            var ssl = (ui["ssl"] as? [String: Any]) ?? [:]
            if (ssl["key"] as? String) != keyPath || (ssl["cert"] as? String) != certPath {
                ssl["key"] = keyPath
                ssl["cert"] = certPath
                ui["ssl"] = ssl
                platforms[idx] = ui
                cfg["platforms"] = platforms
                cfgChanged = true
            }
        }
        if cfgChanged {
            if let out = try? JSONSerialization.data(withJSONObject: cfg, options: .prettyPrinted) {
                try? out.write(to: URL(fileURLWithPath: cfgPath))
            }
        }

        self.useHTTPS = FileManager.default.fileExists(atPath: keyPath) && FileManager.default.fileExists(atPath: certPath)
        return changed || cfgChanged
    }
}
