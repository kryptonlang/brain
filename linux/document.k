// Objective-K owns document state independently of the display connection.
module brain_linux_document

func brainLinuxQuote(text) {
    emit "'" + replace(text, "'", "'\"'\"'") + "'"
}

func brainLinuxText(arena, document, field) {
    let handle = okKGet(arena, document, field)
    let length = okKRead(arena, handle, 8)
    let offset = okKOffset(arena, handle) + 32
    let builder = sbNew()
    let i = 0
    while i < length {
        builder = sbAppend(builder, fromCharCode(bufGetByte(arena, offset + i)))
        i += 1
    }
    emit sbToString(builder)
}

// Assign a text field, interning the string first (doKText takes an arena
// text handle, not a raw string). The runtime retains the handle; the
// caller releases its own.
func brainLinuxAssignText(arena, document, name, text) {
    let handle = okKText(arena, text)
    doKText(arena, document, name, handle)
    doKReleaseText(arena, handle)
    emit 1
}

func brainLinuxDocument(arena) {
    let kind = okKClass(arena, "BrainDocument", 0)
    doKRegister(arena, kind)
    let document = okKNew(arena, kind)
    brainLinuxAssignText(arena, document, "path", "")
    brainLinuxAssignText(arena, document, "source", "")
    brainLinuxAssignText(arena, document, "saved", "")
    doKSet(arena, document, "cursor", 0)
    doKSet(arena, document, "dirty", 0)
    emit document
}

// A byte-count check detects both read failures and binary NUL truncation.
func brainLinuxOpen(arena, document, path) {
    let quoted = brainLinuxQuote(path)
    if shellRun("test -f " + quoted + " && test -r " + quoted) != 0 {
        emit "File is not readable"
    }
    let count = trim(exec("stat -Lc %s -- " + quoted))
    if count == "" || toInt(count) > 65536 { emit "File exceeds 64 KiB or size is unavailable" }
    let source = readFile(path)
    if len(source) != toInt(count) { emit "Could not read a complete text file" }
    brainLinuxAssignText(arena, document, "source", source)
    brainLinuxAssignText(arena, document, "saved", source)
    brainLinuxAssignText(arena, document, "path", path)
    doKSet(arena, document, "cursor", 0)
    doKSet(arena, document, "dirty", 0)
    emit ""
}

func brainLinuxSave(arena, document, path, overwrite) {
    let quoted = brainLinuxQuote(path)
    if shellRun("test -L " + quoted) == 0 { emit "Cannot save through a symbolic link" }
    let exists = shellRun("test -e " + quoted)
    if exists == 0 && overwrite == 0 { emit "That file already exists" }
    if exists == 0 && shellRun("test -f " + quoted) != 0 { emit "Destination is not a regular file" }
    if overwrite == 1 {
        let saved = brainLinuxText(arena, document, "saved")
        let size = trim(exec("stat -c %s -- " + quoted))
        if exists != 0 || size == "" || toInt(size) != len(saved) || readFile(path) != saved {
            emit "File changed on disk. Use Save As."
        }
    }
    let template = path + ".brain.XXXXXX"
    if substring(template, 0, 1) != "/" { template = "./" + template }
    let temporary = trim(exec("mktemp -- " + brainLinuxQuote(template)))
    if temporary == "" { emit "Could not create a temporary file beside the destination" }
    let source = brainLinuxText(arena, document, "source")
    let staging = brainLinuxQuote(temporary)
    writeFile(temporary, source)
    let size = trim(exec("stat -c %s -- " + staging))
    let failed = size == "" || toInt(size) != len(source) || readFile(temporary) != source
    if failed == 0 && exists == 0 {
        failed = shellRun("chmod --reference=" + quoted + " -- " + staging) != 0
    }
    if failed == 0 {
        let flags = "-T"
        if overwrite == 0 { flags = "-nT" }
        failed = shellRun("mv " + flags + " -- " + staging + " " + quoted) != 0
        if shellRun("test -e " + staging) == 0 { failed = 1 }
    }
    if failed == 1 {
        shellRun("rm -f -- " + staging)
        emit "Save failed"
    }
    brainLinuxAssignText(arena, document, "path", path)
    brainLinuxAssignText(arena, document, "saved", source)
    doKSet(arena, document, "dirty", 0)
    emit ""
}

func brainLinuxReplace(arena, document, first, last, inserted) {
    let source = brainLinuxText(arena, document, "source")
    if len(source) - (last - first) + len(inserted) > 65536 { emit 0 }
    let builder = sbNew()
    builder = sbAppend(builder, substring(source, 0, first))
    builder = sbAppend(builder, inserted)
    builder = sbAppend(builder, substring(source, last, len(source)))
    brainLinuxAssignText(arena, document, "source", sbToString(builder))
    doKSet(arena, document, "cursor", first + len(inserted))
    doKSet(arena, document, "dirty", 1)
    emit 1
}

func brainLinuxPrevious(source, cursor) {
    if cursor == 0 { emit 0 }
    let first = cursor - 1
    while first > 0 {
        let byte = charCode(source[first])
        if byte < 128 || byte >= 192 { break }
        first -= 1
    }
    emit first
}

func brainLinuxNext(source, cursor) {
    if cursor >= len(source) { emit len(source) }
    let next = cursor + 1
    while next < len(source) {
        let byte = charCode(source[next])
        if byte < 128 || byte >= 192 { break }
        next += 1
    }
    emit next
}
