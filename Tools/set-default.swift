import AppKit
import CoreServices
import UniformTypeIdentifiers

let bundleID = "local.jamil.mdmini"
let userApp = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/MD Mini.app")
let systemApp = URL(fileURLWithPath: "/Applications/MD Mini.app")
let app = FileManager.default.fileExists(atPath: userApp.path) ? userApp : systemApp
let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("examples/Welcome.md")
guard FileManager.default.fileExists(atPath: app.path) else { print("MD Mini is not installed"); exit(1) }
let registration = LSRegisterURL(app as CFURL, true)
guard registration == noErr else { print("Registration failed: \(registration)"); exit(1) }
NSWorkspace.shared.setDefaultApplication(at: app, toOpenContentTypeOfFileAt: file) { error in
    if let error { print("Association failed: \(error)"); exit(1) }
    guard let resolved = NSWorkspace.shared.urlForApplication(toOpen: file), Bundle(url: resolved)?.bundleIdentifier?.lowercased() == bundleID else { print("File routing verification failed"); exit(1) }
    print("Verified .md default application: \(resolved.path)")
    exit(0)
}
RunLoop.main.run()
