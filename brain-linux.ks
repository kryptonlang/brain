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
let BRAIN_BAR     = 2173227     // 0x21292b  title / status bar
let BRAIN_ACCENT  = 10912215    // 0xa681d7  caret / accent
let BRAIN_INK     = 15919871    // 0xf2eaff  text
let BRAIN_MUTED   = 9275536     // 0x8d84a8  line numbers
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

// Send the IME the full surrounding text so it can compose (spec allows
// this; documents are capped at 64 KiB).
func brainLinuxSyncSurround(fd, ti) {
    if ti == 0 { emit 1 }
    let source = brainLinuxText(brainLinuxArena, brainLinuxDoc, "source")
    let cur = okKGet(brainLinuxArena, brainLinuxDoc, "cursor")
    wlTextInputSetSurrounding(fd, ti, source, cur, cur)
    wlTextInputCommit(fd, ti)
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
            fbFillRect(px, fbW, sufX, y, 2, BRAIN_FONT_H, BRAIN_ACCENT)
        } else {
            let visible = brainLinuxVisible(brainWlAscii(substring(source, first, last)), brainLinuxLeft, columns)
            if visible != "" { fbDrawText(px, fbW, fbH, font, BRAIN_TEXT_X, y, visible, BRAIN_INK) }
            if row == line && brainLinuxPrompt == "" {
                let x = BRAIN_TEXT_X + (column - brainLinuxLeft) * BRAIN_FONT_W
                fbFillRect(px, fbW, x, y, 2, BRAIN_FONT_H, BRAIN_ACCENT)
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

func brainLinuxWindow(smoke) {
    let fd = wlConnect()
    if fd < 0 { print("Could not connect to Wayland.")  emit 1 }
    let REG = brainLinuxNewId()
    wlGetRegistry(fd, REG)
    // wl_display.sync — the compositor answers with a callback done event
    // AFTER sending the full global list. Without it, one recv() may return
    // only the first global (TCP gives no multi-packet atomicity) and we
    // would bind to id -1.
    let SYNCB = brainLinuxNewId()
    let rb = bufNew(16384)
    let rn = wlSyncRegistry(fd, SYNCB, rb, 16384)
    if rn < 0 { print("Wayland registry handshake failed.")  sockClose(fd)  emit 1 }
    if rn <= 0 { print("Wayland registry handshake failed.")  sockClose(fd)  emit 1 }
    let compName = wlRegistryFind(rb, rn, "wl_compositor")
    let shmName = wlRegistryFind(rb, rn, "wl_shm")
    let wmName = wlRegistryFind(rb, rn, "xdg_wm_base")
    let seatName = wlRegistryFind(rb, rn, "wl_seat")
    if compName < 0 || shmName < 0 || wmName < 0 || seatName < 0 {
        print("Wayland compositor is missing required globals.")  sockClose(fd)  emit 1
    }
    let COMP = brainLinuxNewId(); wlBind(fd, REG, compName, "wl_compositor", 4, COMP)
    let SHM  = brainLinuxNewId(); wlBind(fd, REG, shmName, "wl_shm", 1, SHM)
    let WM   = brainLinuxNewId(); wlBind(fd, REG, wmName, "xdg_wm_base", 1, WM)
    let SEAT = brainLinuxNewId(); wlBind(fd, REG, seatName, "wl_seat", 5, SEAT)
    let KB   = brainLinuxNewId(); wlGetKeyboard(fd, SEAT, KB)
    // zwp_text_input_manager_v3 is optional: without it, typed text falls
    // back to the ASCII keymap (degraded mode).
    let tiName = wlRegistryFind(rb, rn, "zwp_text_input_manager_v3")
    let TINPM = 0
    if tiName >= 0 {
        TINPM = brainLinuxNewId()
        wlBind(fd, REG, tiName, "zwp_text_input_manager_v3", 1, TINPM)
    }
    let SURF = brainLinuxNewId(); wlCreateSurface(fd, COMP, SURF)
    let XS   = brainLinuxNewId(); wlGetXdgSurface(fd, WM, XS, SURF)
    let TOP  = brainLinuxNewId(); wlGetToplevel(fd, XS, TOP)
    wlSetTitle(fd, TOP, "Brain")
    wlSetAppId(fd, TOP, "brain")
    let TINP = 0
    if TINPM != 0 {
        TINP = brainLinuxNewId()
        wlGetTextInput(fd, TINPM, TINP, SEAT)
    }
    wlCommit(fd, SURF)

    let W = 900
    let H = 620
    let kmap = brainWlKeymap()
    let font = wlFontLoad()
    let running = 1
    let configured = 0
    let kbDepressed = 0
    let textActive = 0
    let prevBuf = 0
    let prevPool = 0
    let prevMfd = 0
    let eb = bufNew(65536)
    while running == 1 {
        let en = wlRecvInto(fd, eb, 65536)
        if en <= 0 { running = 0 }
        else {
            let off = 0
            let dirty = 0
            while off + 8 <= en {
                let obj = wlObject(eb, off)
                let op = wlOpcode(eb, off)
                let s = wlSize(eb, off)
                if s < 8 { off = en }
                else {
                    if obj == WM && op == 0 { wlPong(fd, WM, wlU32(eb, off + 8)) }
                    if obj == XS && op == 0 { wlAckConfigure(fd, XS, wlU32(eb, off + 8))  dirty = 1  configured = 1 }
                    if obj == TOP && op == 0 {
                        let cw = wlU32(eb, off + 8)
                        let chh = wlU32(eb, off + 12)
                        if cw > 0 && chh > 0 { W = cw  H = chh }
                    }
                    if obj == TOP && op == 1 {
                        running = brainLinuxQuit()
                        if running == 1 { dirty = 1 }
                    }
                    if obj == 1 && op == 0 { print("Wayland protocol error")  running = 0 }
                    if obj == KB && op == 0 {
                        // keyboard focus gained -- arm text-input
                        if TINP != 0 {
                            wlTextInputEnable(fd, TINP)
                            wlTextInputSetContentType(fd, TINP, 0, 0)
                            brainLinuxSyncSurround(fd, TINP)
                            wlTextInputSetCursorRectangle(fd, TINP, brainLinuxCaretX, brainLinuxCaretY, 2, BRAIN_FONT_H)
                            wlTextInputCommit(fd, TINP)
                        }
                    }
                    if obj == KB && op == 1 { textActive = 0  brainLinuxPreedit = ""  dirty = 1 }
                    if obj == KB && op == 3 {
                        let state = wlU32(eb, off + 20)
                        if state == 1 {
                            let kc = wlKeyToKc(wlU32(eb, off + 16))
                            let shift = kbDepressed % 2
                            let ctrl = (kbDepressed / 4) % 2
                            let symbol = brainWlKeysym(kmap, kc, shift)
                            if textActive == 1 && ctrl == 0 && symbol >= 32 && symbol < 127 {
                                symbol = 0   // text-input delivers printable text
                            }
                            if symbol != 0 {
                                running = brainLinuxAction(symbol, kbDepressed)
                                if running == 1 { dirty = 1 }
                            }
                        }
                    }
                    if obj == KB && op == 4 { kbDepressed = wlU32(eb, off + 12) % 16 }
                    if obj == TINP && op == 0 { textActive = 1 }
                    if obj == TINP && op == 1 { textActive = 0  brainLinuxPreedit = ""  dirty = 1 }
                    if obj == TINP && op == 2 {
                        brainLinuxPreedit = wlTextInputEventText(eb, off)
                        dirty = 1
                    }
                    if obj == TINP && op == 3 {
                        let text = wlTextInputEventText(eb, off)
                        if brainLinuxPrompt != "" {
                            if len(brainLinuxInput) + len(text) < 4096 {
                                let builder = sbNew()
                                builder = sbAppend(builder, brainLinuxInput)
                                builder = sbAppend(builder, text)
                                brainLinuxInput = sbToString(builder)
                            }
                            brainLinuxNotice = ""
                        } else {
                            let cur = okKGet(brainLinuxArena, brainLinuxDoc, "cursor")
                            if brainLinuxReplace(brainLinuxArena, brainLinuxDoc, cur, cur, text) == 0 {
                                brainLinuxNotice = "Document limit is 64 KiB"
                            } else { brainLinuxNotice = "" }
                        }
                        brainLinuxPreedit = ""
                        brainLinuxSyncSurround(fd, TINP)
                        dirty = 1
                    }
                    if obj == TINP && op == 4 {
                        let before = wlU32(eb, off + 8)
                        let after = wlU32(eb, off + 12)
                        if brainLinuxPrompt != "" {
                            // prompt is end-anchored: only the prefix side exists
                            if before > 0 && before <= len(brainLinuxInput) {
                                brainLinuxInput = substring(brainLinuxInput, 0, len(brainLinuxInput) - before)
                            }
                        } else {
                            let source = brainLinuxText(brainLinuxArena, brainLinuxDoc, "source")
                            let cur = okKGet(brainLinuxArena, brainLinuxDoc, "cursor")
                            let from = cur - before
                            if from < 0 { from = 0 }
                            let to = cur + after
                            if to > len(source) { to = len(source) }
                            if from < to {
                                if brainLinuxReplace(brainLinuxArena, brainLinuxDoc, from, to, "") == 0 {
                                    brainLinuxNotice = "Document limit is 64 KiB"
                                } else { brainLinuxNotice = "" }
                            }
                        }
                        brainLinuxSyncSurround(fd, TINP)
                        dirty = 1
                    }
                    // op == 5 (done): the IM events above were applied already
                    off = off + s
                }
            }
            if dirty == 1 && running == 1 && configured == 1 {
                // paint a fresh frame (ids never reused)
                if prevBuf != 0 { wlBufferDestroy(fd, prevBuf)  wlPoolDestroy(fd, prevPool)  sockClose(prevMfd) }
                let stride = W * 4
                let sz = stride * H
                let m = memfdCreate(sz)
                let px = mmapShared(m, sz)
                brainLinuxDraw(px, W, H, font, W, H)
                let pool = brainLinuxNewId()
                let buf = brainLinuxNewId()
                wlCreatePool(fd, SHM, pool, m, sz)
                wlPoolCreateBuffer(fd, pool, buf, 0, W, H, stride, 1)
                wlSurfaceAttach(fd, SURF, buf, 0, 0)
                wlDamage(fd, SURF, 0, 0, W, H)
                wlCommit(fd, SURF)
                if TINP != 0 {
                    wlTextInputSetCursorRectangle(fd, TINP, brainLinuxCaretX, brainLinuxCaretY, 2, BRAIN_FONT_H)
                    wlTextInputCommit(fd, TINP)
                }
                prevBuf = buf
                prevPool = pool
                prevMfd = m
                if smoke == 1 { print("Brain mapped and drew its Wayland editor window")  running = 0 }
            }
        }
    }
    sockClose(fd)
    emit 0
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
