import AppKit

// Explicit programmatic entry point. `@main` on an NSApplicationDelegate with no main nib leaves
// NSApp.delegate unset (NSApplicationMain has no nib to wire it from), so the delegate's
// applicationDidFinishLaunching never fires and no window/menu/status item is ever created.
// Creating the application and assigning the delegate here guarantees the launch sequence runs.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
