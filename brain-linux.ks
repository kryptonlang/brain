import "k:objk_runtime"
import "k:wayland"
import "linux/document.k"
import "linux/display.k"

// Linux desktop entry point. Document state belongs to Objective-K;
// rendering is k:wayland (raw wl_shm framebuffer), text input is
// zwp_text_input_v3 when the compositor exposes it, with a hardcoded ASCII
// keymap as a degraded fallback (no UTF-8 without text-input-v3).
let brainLinuxArena = 0
let brainLinuxDoc = 0
let brainLinuxNotice = ""
let brainLinuxPrompt = ""
let brainLinuxInput = ""
let brainLinuxQuitArmed = 0
let brainLinuxTop = 0
let brainLinuxLeft = 0
let brainLinuxPreedit = ""      // IME composing text, raw UTF-8 bytes
let brainLinuxCaretX = 52       // maintained by the draw pass, fed to text-input
let brainLinuxCaretY = 54
let brainLinuxId = 2            // Wayland object id allocator (module-level lets
                                 // work in the main module; NOT in imported ones)
func brainLinuxNewId() {
    let id = brainLinuxId
    brainLinuxId = brainLinuxId + 1
    emit id
}

// Theme (packed 0xRRGGBB)
let BRAIN_CANVAS  = 1445919     // 0x16101f  background
let BRAIN_BAR     = 2169643     // 0x211b2b  title / status bar
let BRAIN_ACCENT  = 10912215    // 0xa681d7  caret / accent
let BRAIN_INK     = 15919871    // 0xf2eaff  text
let BRAIN_MUTED   = 9274536     // 0x8d84a8  line numbers
let BRAIN_LINEH   = 18
let BRAIN_FONT_W  = 8
let BRAIN_FONT_H  = 16
let BRAIN_TEXT_X  = 52
let BRAIN_GUTTER  = 10

func brainLinuxResult(error, success) {
    brainLinuxNotice = success
    if error != "" { brainLinuxNotice = error }
}

func brainLinuxQuit() {
    if okKGet(brainLinuxArena, brainLinuxDoc, "dirty") == 0 || brainLinuxQuitArmed == 1 { emit 0 }
    brainLinuxQuitArmed = 1
    brainLinuxNotice = "Unsaved changes. Press Ctrl+Q again to discard."
    emit 1
}

// X11-vestige (future-edit item): brainLinuxAction compares against X11/XKB
// keysym *values* (65361 Left, 65363 Right, 65362 Up/Down, 65360 Home, 65367
// End, 65307 Esc, 65293 Return, 65288 BackSpace, 65535 Delete). This is the
// editor's internal key dialect inherited from the X11 port. Keeping the
// values is safe (constants only, no X11 dep) but they should migrate to
// plain internal ids when the input stack is redone on xkbcommon.
func brainLinuxAction(symbol, modifiers) {
    let arena = brainLinuxArena
    let document = brainLinuxDoc
    let control = modifiers / 4 % 2
    if control == 1 && (symbol == 113 || symbol == 81) { emit brainLinuxQuit() }
    brainLinuxQuitArmed = 0
    if brainLinuxPrompt != "" {
        if symbol == 65307 {
            brainLinuxPrompt = ""
        } else if symbol == 65293 && brainLinuxInput != "" {
            let error = ""
            if brainLinuxPrompt == "Open" {
                error = brainLinuxOpen(arena, document, brainLinuxInput)
                brainLinuxResult(error, "Opened")
            } else {
                error = brainLinuxSave(arena, document, brainLinuxInput, 0)
                brainLinuxResult(error, "Saved")
            }
            if error == "" { brainLinuxPrompt = "" }
        } else if symbol == 65288 && len(brainLinuxInput) > 0 {
            brainLinuxInput = substring(brainLinuxInput, 0, brainLinuxPrevious(brainLinuxInput, len(brainLinuxInput)))
        } else if control == 0 && symbol >= 32 && symbol < 127 && len(brainLinuxInput) < 4096 {
            let builder = sbNew()
            builder = sbAppend(builder, brainLinuxInput)
            builder = sbAppend(builder, fromCharCode(symbol))
            brainLinuxInput = sbToString(builder)
        }
        emit 1
    }
    if control == 1 {
        if symbol == 111 || symbol == 79 {
            if okKGet(arena, document, "dirty") == 1 {
                brainLinuxNotice = "Save changes before opening another file."
            } else {
                brainLinuxPrompt = "Open"
                brainLinuxInput = ""
            }
        }
        if symbol == 115 || symbol == 83 {
            let path = brainLinuxText(arena, document, "path")
            if path == "" || modifiers % 2 == 1 {
                brainLinuxPrompt = "Save As"
                brainLinuxInput = path
            } else { brainLinuxResult(brainLinuxSave(arena, document, path, 1), "Saved") }
        }
        emit 1
    }

    let source = brainLinuxText(arena, document, "source")
    let cursor = okKGet(arena, document, "cursor")
    let start = cursor
    while start > 0 && charCode(source[start - 1]) != 10 { start -= 1 }
    let finish = cursor
    while finish < len(source) && charCode(source[finish]) != 10 { finish += 1 }

    if symbol == 65361 { cursor = brainLinuxPrevious(source, cursor) }
    else if symbol == 65363 { cursor = brainLinuxNext(source, cursor) }
    else if symbol == 65360 { cursor = start }
    else if symbol == 65367 { cursor = finish }
    else if symbol == 65362 || symbol == 65364 {
        let column = len(brainWlAscii(substring(source, start, cursor)))
        let destination = start
        if symbol == 65362 && start > 0 {
            destination = start - 1
            while destination > 0 && charCode(source[destination - 1]) != 10 { destination -= 1 }
        }
        if symbol == 65364 && finish < len(source) { destination = finish + 1 }
        if destination != start {
            cursor = destination
            while column > 0 && cursor < len(source) && charCode(source[cursor]) != 10 {
                cursor = brainLinuxNext(source, cursor)
                column -= 1
            }
        }
    } else {
        let first = cursor
        let last = cursor
        let inserted = ""
        if symbol == 65288 { first = brainLinuxPrevious(source, cursor) }
        else if symbol == 65535 { last = brainLinuxNext(source, cursor) }
        else if symbol == 65293 { inserted = fromCharCode(10) }
        else if symbol == 65289 { inserted = "    " }
        else if symbol >= 32 && symbol < 127 { inserted = fromCharCode(symbol) }
        if first != last || inserted != "" {
            if brainLinuxReplace(arena, document, first, last, inserted) == 0 {
                brainLinuxNotice = "Document limit is 64 KiB"
            } else { brainLinuxNotice = "" }
        }
        emit 1
    }
    doKSet(arena, document, "cursor", cursor)
    emit 1
}

func brainLinuxVisible(text, start, limit) {
    if start >= len(text) || limit < 1 { emit "" }
    if limit > 255 { limit = 255 }
    let last = start + limit
    if last > len(text) { last = len(text) }
    emit substring(text, start, last)
}

// Keep the surrounding text within the protocol's 4000-byte limit.
func brainLinuxSyncSurround(fd, ti) {
    if ti == 0 { emit 1 }
    let source = brainLinuxText(brainLinuxArena, brainLinuxDoc, "source")
    let cursor = okKGet(brainLinuxArena, brainLinuxDoc, "cursor")
    if brainLinuxPrompt != "" { source = brainLinuxInput  cursor = len(source) }
    let first = cursor - 1800
    if first < 0 { first = 0 }
    while first < cursor && charCode(source[first]) >= 128 && charCode(source[first]) < 192 { first += 1 }
    let last = cursor + 1800
    if last > len(source) { last = len(source) }
    while last < len(source) && charCode(source[last]) >= 128 && charCode(source[last]) < 192 { last -= 1 }
    wlTextInputSetSurrounding(fd, ti, substring(source, first, last), cursor - first, cursor - first)
    wlTextInputCommit(fd, ti)
    emit 1
}

func brainLinuxCommitText(text, before, after) {
    if brainLinuxPrompt != "" {
        let length = len(brainLinuxInput)
        if before > length || after != 0 { emit 0 }
        let first = length - before
        if first < length && charCode(brainLinuxInput[first]) >= 128 && charCode(brainLinuxInput[first]) < 192 { emit 0 }
        if first + len(text) > 4096 { emit 0 }
        let builder = sbNew()
        builder = sbAppend(builder, substring(brainLinuxInput, 0, first))
        builder = sbAppend(builder, text)
        brainLinuxInput = sbToString(builder)
    } else {
        let source = brainLinuxText(brainLinuxArena, brainLinuxDoc, "source")
        let cursor = okKGet(brainLinuxArena, brainLinuxDoc, "cursor")
        if before > cursor || after > len(source) - cursor { emit 0 }
        let first = cursor - before
        let last = cursor + after
        if first < len(source) && charCode(source[first]) >= 128 && charCode(source[first]) < 192 { emit 0 }
        if last < len(source) && charCode(source[last]) >= 128 && charCode(source[last]) < 192 { emit 0 }
        if first != last || text != "" {
            if brainLinuxReplace(brainLinuxArena, brainLinuxDoc, first, last, text) == 0 { emit 0 }
        }
    }
    brainLinuxQuitArmed = 0
    brainLinuxNotice = ""
    emit 1
}

func brainLinuxDraw(px, fbW, fbH, font, width, height) {
    let columns = (width - 56) / BRAIN_FONT_W
    if columns < 1 { columns = 1 }
    if columns > 240 { columns = 240 }
    let rows = (height - 72) / BRAIN_LINEH
    if rows < 1 { rows = 1 }

    let arena = brainLinuxArena
    let document = brainLinuxDoc
    let source = brainLinuxText(arena, document, "source")
    let path = brainLinuxText(arena, document, "path")
    if path == "" { path = "Untitled" }
    if okKGet(arena, document, "dirty") == 1 { path = path + " *" }
    let cursor = okKGet(arena, document, "cursor")
    let line = 0
    let lineStart = 0
    let i = 0
    while i < cursor {
        if charCode(source[i]) == 10 { line += 1  lineStart = i + 1 }
        i += 1
    }
    let column = len(brainWlAscii(substring(source, lineStart, cursor)))
    if line < brainLinuxTop { brainLinuxTop = line }
    if line >= brainLinuxTop + rows { brainLinuxTop = line - rows + 1 }
    if column < brainLinuxLeft { brainLinuxLeft = column }
    if column >= brainLinuxLeft + columns { brainLinuxLeft = column - columns + 1 }

    fbClear(px, fbW, fbH, BRAIN_CANVAS)
    fbFillRect(px, fbW, 0, 0, width, 38, BRAIN_BAR)
    fbFillRect(px, fbW, 0, height - 24, width, 24, BRAIN_BAR)
    fbDrawText(px, fbW, fbH, font, 12, 11, brainLinuxVisible("Brain  /  " + brainWlAscii(path), 0, columns - 2), BRAIN_INK)

    let row = 0
    let y = 54
    let first = 0
    while row < brainLinuxTop && first < len(source) {
        if charCode(source[first]) == 10 { row += 1 }
        first += 1
    }
    let preCols = 0
    if brainLinuxPreedit != "" { preCols = len(brainWlAscii(brainLinuxPreedit)) }
    while row < brainLinuxTop + rows && first <= len(source) {
        let last = first
        while last < len(source) && charCode(source[last]) != 10 { last += 1 }
        fbDrawText(px, fbW, fbH, font, BRAIN_GUTTER, y, toStr(row + 1), BRAIN_MUTED)
        if row == line && brainLinuxPreedit != "" {
            // Splice the preedit text in at the caret: prefix - preedit - suffix.
            let prefix = brainWlAscii(substring(source, first, cursor))
            let suffix = brainWlAscii(substring(source, cursor, last))
            let prefixVis = brainLinuxVisible(prefix, brainLinuxLeft, columns)
            if prefixVis != "" { fbDrawText(px, fbW, fbH, font, BRAIN_TEXT_X, y, prefixVis, BRAIN_INK) }
            let ax = BRAIN_TEXT_X + (len(prefix) - brainLinuxLeft) * BRAIN_FONT_W
            if ax < BRAIN_TEXT_X { ax = BRAIN_TEXT_X }
            fbDrawText(px, fbW, fbH, font, ax, y, brainWlAscii(brainLinuxPreedit), BRAIN_ACCENT)
            let sufX = ax + preCols * BRAIN_FONT_W + 4
            if suffix != "" && sufX < width {
                let sufStart = 0
                if brainLinuxLeft > len(prefix) + preCols { sufStart = brainLinuxLeft - len(prefix) - preCols }
                if sufStart < len(suffix) {
                    fbDrawText(px, fbW, fbH, font, sufX, y, brainLinuxVisible(suffix, sufStart, columns), BRAIN_INK)
                }
            }
            brainLinuxCaretX = sufX
            brainLinuxCaretY = y
            if sufX >= 0 && sufX + 2 <= width && y + BRAIN_FONT_H <= height { fbFillRect(px, fbW, sufX, y, 2, BRAIN_FONT_H, BRAIN_ACCENT) }
        } else {
            let visible = brainLinuxVisible(brainWlAscii(substring(source, first, last)), brainLinuxLeft, columns)
            if visible != "" { fbDrawText(px, fbW, fbH, font, BRAIN_TEXT_X, y, visible, BRAIN_INK) }
            if row == line && brainLinuxPrompt == "" {
                let x = BRAIN_TEXT_X + (column - brainLinuxLeft) * BRAIN_FONT_W
                if x >= 0 && x + 2 <= width && y + BRAIN_FONT_H <= height { fbFillRect(px, fbW, x, y, 2, BRAIN_FONT_H, BRAIN_ACCENT) }
                brainLinuxCaretX = x
                brainLinuxCaretY = y
            }
        }
        y += BRAIN_LINEH
        first = last + 1
        row += 1
    }

    let status = brainLinuxNotice
    if status == "" { status = "Ctrl+O Open    Ctrl+S Save    Ctrl+Shift+S Save As    Ctrl+Q Quit" }
    if brainLinuxPrompt != "" {
        status = brainLinuxPrompt + ": " + brainLinuxInput
        if brainLinuxNotice != "" { status = status + "  [" + brainLinuxNotice + "]" }
    }
    fbDrawText(px, fbW, fbH, font, 12, height - 20, brainLinuxVisible(brainWlAscii(status), 0, columns - 2), BRAIN_INK)
    emit 1
}

func brainLinuxFrameNew(fd, shm) {
    let capacity = 4096 * 2160 * 4
    let memory = memfdCreate(capacity)
    if brainWlSyscallFailed(memory) == 1 { emit 0 }
    let pixels = mmapShared(memory, capacity)
    if brainWlSyscallFailed(pixels) == 1 { sockClose(memory)  emit 0 }
    let pool = brainLinuxNewId()
    wlCreatePool(fd, shm, pool, memory, capacity)
    let frame = structNew()
    frame = setField(frame, "memory", memory)
    frame = setField(frame, "pixels", pixels)
    frame = setField(frame, "pool", pool)
    frame = setField(frame, "buffer", 0)
    frame = setField(frame, "width", 0)
    frame = setField(frame, "height", 0)
    emit setField(frame, "busy", 0)
}

func brainLinuxPresentFrame(fd, surface, frame, font, width, height) {
    let buffer = getField(frame, "buffer")
    if buffer == 0 || getField(frame, "width") != width || getField(frame, "height") != height {
        if buffer != 0 { wlBufferDestroy(fd, buffer) }
        buffer = brainLinuxNewId()
        wlPoolCreateBuffer(fd, getField(frame, "pool"), buffer, 0, width, height, width * 4, 1)
        frame = setField(frame, "buffer", buffer)
        frame = setField(frame, "width", width)
        frame = setField(frame, "height", height)
    }
    brainLinuxDraw(getField(frame, "pixels"), width, height, font, width, height)
    wlSurfaceAttach(fd, surface, buffer, 0, 0)
    wlDamage(fd, surface, 0, 0, width, height)
    wlCommit(fd, surface)
    emit setField(frame, "busy", 1)
}

func brainLinuxWindow(smoke) {
    let fd = wlConnect()
    if brainWlSyscallFailed(fd) == 1 { print("Could not connect to Wayland.")  emit 1 }
    let registry = brainLinuxNewId()
    wlGetRegistry(fd, registry)
    let syncId = brainLinuxNewId()
    let messages = bufNew(65536)
    let scratch = bufNew(65536)
    let registrySize = brainWlRegistry(fd, registry, syncId, messages, scratch)
    if registrySize == 0 { print("Wayland registry handshake failed.")  sockClose(fd)  emit 1 }
    let compositorName = wlRegistryFind(messages, registrySize, "wl_compositor")
    let shmName = wlRegistryFind(messages, registrySize, "wl_shm")
    let wmName = wlRegistryFind(messages, registrySize, "xdg_wm_base")
    let seatName = wlRegistryFind(messages, registrySize, "wl_seat")
    if compositorName < 0 || shmName < 0 || wmName < 0 {
        print("Wayland compositor is missing required globals.")  sockClose(fd)  emit 1
    }
    let compositor = brainLinuxNewId()
    wlBind(fd, registry, compositorName, "wl_compositor", 4, compositor)
    let shm = brainLinuxNewId()
    wlBind(fd, registry, shmName, "wl_shm", 1, shm)
    let wm = brainLinuxNewId()
    wlBind(fd, registry, wmName, "xdg_wm_base", 1, wm)
    let seat = 0
    let keyboard = 0
    if seatName >= 0 {
        seat = brainLinuxNewId()
        wlBind(fd, registry, seatName, "wl_seat", 5, seat)
    }
    let managerName = wlRegistryFind(messages, registrySize, "zwp_text_input_manager_v3")
    let manager = 0
    if managerName >= 0 && seat != 0 {
        manager = brainLinuxNewId()
        wlBind(fd, registry, managerName, "zwp_text_input_manager_v3", 1, manager)
    }
    let surface = brainLinuxNewId()
    wlCreateSurface(fd, compositor, surface)
    let shellSurface = brainLinuxNewId()
    wlGetXdgSurface(fd, wm, shellSurface, surface)
    let top = brainLinuxNewId()
    wlGetToplevel(fd, shellSurface, top)
    wlSetTitle(fd, top, "Brain")
    wlSetAppId(fd, top, "brain")
    _wlSend2(fd, top, 7, 4096, 2160)
    _wlSend2(fd, top, 8, 320, 160)
    let input = 0
    if manager != 0 {
        input = brainLinuxNewId()
        wlGetTextInput(fd, manager, input, seat)
    }
    wlCommit(fd, surface)

    // Alternate two fixed allocations. A compositor may retain the current
    // buffer until its replacement arrives.
    let firstFrame = brainLinuxFrameNew(fd, shm)
    let secondFrame = brainLinuxFrameNew(fd, shm)
    if firstFrame == 0 || secondFrame == 0 { sockClose(fd)  emit 1 }
    let width = 900
    let height = 620
    let dirty = 1
    let configured = 0
    let modifiers = 0
    let activeInput = 0
    let kmap = brainWlKeymap()
    let font = wlFontLoad()
    let pendingText = ""
    let pendingPreedit = ""
    let pendingBefore = 0
    let pendingAfter = 0
    let running = 1
    let result = 0
    while running == 1 {
        let size = brainWlReadMessage(fd, messages, scratch)
        if size == 0 { result = 1  break }
        let obj = wlObject(messages, 0)
        let op = wlOpcode(messages, 0)
        if obj == 1 && op == 0 { print("Wayland protocol error")  result = 1  break }
        if obj == wm && op == 0 && size == 12 { wlPong(fd, wm, wlU32(messages, 8)) }
        if obj == shellSurface && op == 0 && size == 12 {
            wlAckConfigure(fd, shellSurface, wlU32(messages, 8))
            dirty = 1
            configured = 1
        }
        if obj == top && op == 0 && size >= 20 {
            let nextWidth = wlU32(messages, 8)
            let nextHeight = wlU32(messages, 12)
            if nextWidth > 0 { width = nextWidth }
            if nextHeight > 0 { height = nextHeight }
            if width < 64 || height < 80 || width > 4096 || height > 2160 {
                print("Wayland window size is outside supported bounds.")  result = 1  break
            }
            dirty = 1
        }
        if obj == top && op == 1 {
            running = brainLinuxQuit()
            if running == 1 { dirty = 1 }
        }
        if op == 0 && obj == getField(firstFrame, "buffer") { firstFrame = setField(firstFrame, "busy", 0) }
        if op == 0 && obj == getField(secondFrame, "buffer") { secondFrame = setField(secondFrame, "busy", 0) }
        if obj == seat && seat != 0 && op == 0 && size == 12 {
            let capabilities = wlU32(messages, 8)
            if capabilities / 2 % 2 == 1 && keyboard == 0 {
                keyboard = brainLinuxNewId()
                wlGetKeyboard(fd, seat, keyboard)
            }
        }
        if obj == keyboard && keyboard != 0 {
            if op == 2 { modifiers = 0 }
            if op == 4 && size == 28 {
                modifiers = brainWlModifiers(wlU32(messages, 12), wlU32(messages, 16), wlU32(messages, 20))
            }
            if op == 3 && size == 24 && wlU32(messages, 20) == 1 {
                let symbol = brainWlKeysym(kmap, wlKeyToKc(wlU32(messages, 16)), modifiers % 2)
                if modifiers / 2 % 2 == 1 {
                    if symbol >= 97 && symbol <= 122 { symbol -= 32 }
                    else if symbol >= 65 && symbol <= 90 { symbol += 32 }
                }
                let control = modifiers / 4 % 2
                if activeInput == 1 && control == 0 && symbol >= 32 && symbol < 127 { symbol = 0 }
                if symbol != 0 {
                    running = brainLinuxAction(symbol, modifiers)
                    dirty = 1
                    if activeInput == 1 && running == 1 { brainLinuxSyncSurround(fd, input) }
                }
            }
        }
        if obj == input && input != 0 {
            if op == 0 {
                activeInput = 1
                wlTextInputEnable(fd, input)
                wlTextInputSetContentType(fd, input, 0, 0)
                brainLinuxSyncSurround(fd, input)
            }
            if op == 1 {
                activeInput = 0
                brainLinuxPreedit = ""
                pendingText = ""
                pendingPreedit = ""
                pendingBefore = 0
                pendingAfter = 0
                dirty = 1
            }
            if op == 2 { pendingPreedit = brainWlEventText(messages, size) }
            if op == 3 { pendingText = brainWlEventText(messages, size) }
            if op == 4 && size == 16 {
                pendingBefore = wlU32(messages, 8)
                pendingAfter = wlU32(messages, 12)
            }
            if op == 5 && activeInput == 1 {
                if brainLinuxCommitText(pendingText, pendingBefore, pendingAfter) == 0 {
                    brainLinuxNotice = "Input change exceeds document bounds"
                }
                brainLinuxPreedit = pendingPreedit
                pendingText = ""
                pendingPreedit = ""
                pendingBefore = 0
                pendingAfter = 0
                dirty = 1
                brainLinuxSyncSurround(fd, input)
            }
        }
        if dirty == 1 && running == 1 && configured == 1 && (getField(firstFrame, "busy") == 0 || getField(secondFrame, "busy") == 0) {
            if getField(firstFrame, "busy") == 0 {
                firstFrame = brainLinuxPresentFrame(fd, surface, firstFrame, font, width, height)
            } else {
                secondFrame = brainLinuxPresentFrame(fd, surface, secondFrame, font, width, height)
            }
            dirty = 0
            if input != 0 && activeInput == 1 {
                wlTextInputSetCursorRectangle(fd, input, brainLinuxCaretX, brainLinuxCaretY, 2, BRAIN_FONT_H)
                wlTextInputCommit(fd, input)
            }
            if smoke == 1 { print("Brain mapped and drew its Wayland editor window")  running = 0 }
        }
    }
    sockClose(getField(firstFrame, "memory"))
    sockClose(getField(secondFrame, "memory"))
    sockClose(fd)
    emit result
}

just run {
    brainLinuxArena = okKRuntime(1048576)
    brainLinuxDoc = brainLinuxDocument(brainLinuxArena)
    let smoke = 0
    if argCount() > 0 && arg(0) == "--window-smoke" { smoke = 1 }
    if argCount() > 0 && smoke == 0 {
        let error = brainLinuxOpen(brainLinuxArena, brainLinuxDoc, arg(0))
        if error != "" { print(error)  exit(1) }
    }
    exit(brainLinuxWindow(smoke))
}
