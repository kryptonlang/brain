import "k:objk_runtime"
import "../linux/document.k"

func checkLinux(ok, message) {
    if ok == 0 { print("FAIL: " + message)  exit(1) }
}

just run {
    let root = arg(0)
    let arena = okKRuntime(1048576)
    let document = brainLinuxDocument(arena)
    let path = root + "/number's.txt"
    let text = "12345\n🦋\n"
    writeFile(path, text)
    checkLinux(brainLinuxOpen(arena, document, path) == "", "open path containing apostrophe")
    checkLinux(brainLinuxText(arena, document, "source") == text, "preserve numeric text and UTF-8")
    checkLinux(brainLinuxReplace(arena, document, 0, 0, "6") == 1, "insert")
    checkLinux(brainLinuxSave(arena, document, path, 1) == "", "atomic save")
    checkLinux(readFile(path) == "612345\n🦋\n", "saved contents")
    writeFile(path, "external")
    checkLinux(brainLinuxSave(arena, document, path, 1) != "", "reject conflicting external edit")
    checkLinux(readFile(path) == "external", "preserve conflicting file")
    let newPath = root + "/new $(touch injected).txt"
    checkLinux(brainLinuxSave(arena, document, newPath, 0) == "", "save new literal filename")
    checkLinux(brainLinuxSave(arena, document, newPath, 0) != "", "reject existing Save As target")
    checkLinux(shellRun("test ! -e injected") == 0, "filename cannot execute shell substitutions")
    checkLinux(brainLinuxPrevious("a🦋b", 5) == 1, "previous UTF-8 boundary")
    checkLinux(brainLinuxNext("a🦋b", 1) == 5, "next UTF-8 boundary")
    checkLinux(brainLinuxOpen(arena, document, root + "/absent") != "", "unreadable file")
    checkLinux(brainLinuxText(arena, document, "path") == newPath, "failed open retains document")
    let i = 0
    while i < 1000 {
        checkLinux(brainLinuxReplace(arena, document, 0, 1, "7") == 1, "repeat text ownership")
        i += 1
    }
    print("PASS: Linux document ownership, UTF-8, literal paths, atomic saves, conflict protection")
}
