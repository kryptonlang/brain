#!/usr/bin/env kr
import "scripts/tooling.k"

just run {
    if sh("uname -s") != "Linux" { print("Run this installer on Linux.")  exit(1) }
    let root = repoRoot()
    let base = env("HOME") + "/.local"
    if argCount() > 0 { base = arg(0) }
    let executable = root + "/dist/brain-linux/brain"
    if shOk("test -x " + quoteArg(executable)) != "1" {
        print("Run kr build_linux.ks first.")
        exit(1)
    }
    let bin = base + "/bin"
    let icons = base + "/share/icons/hicolor/512x512/apps"
    let applications = base + "/share/applications"
    checked("mkdir -p " + quoteArg(bin) + " " + quoteArg(icons) + " " + quoteArg(applications))
    checked("install -m 755 " + quoteArg(executable) + " " + quoteArg(bin + "/brain"))
    checked("install -m 644 " + quoteArg(root + "/codebrain.png") + " " + quoteArg(icons + "/brain.png"))
    let escaped = replace(bin + "/brain", "\\", "\\\\")
    escaped = replace(escaped, "\"", "\\\"")
    escaped = replace(escaped, "$", "\\$")
    escaped = replace(escaped, "`", "\\`")
    escaped = replace(escaped, "%", "%%")
    // Desktop string values unescape once before Exec argument parsing.
    escaped = replace(escaped, "\\", "\\\\")
    let desktop = readFile(root + "/packaging/brain-linux.desktop")
    desktop = replace(desktop, "Exec=brain %f", "Exec=\"" + escaped + "\" %f")
    writeFile(applications + "/brain.desktop", desktop)
    if readFile(applications + "/brain.desktop") != desktop {
        print("Could not write the Brain desktop entry.")
        exit(1)
    }
    print("Installed Brain in " + bin)
}
