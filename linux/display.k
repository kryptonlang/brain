// linux/display.k -- Wayland display helpers for Brain.
//
// Document state lives in linux/document.k (Objective-K, display-agnostic).
// This module only deals with what a Wayland client needs on top of
// k:wayland: printable-text metrics and key input mapping.
//
// Text input architecture (mirrors foot / Qt):
//   typed text (incl. preedit + IME commits) arrives via text-input-v3
//   (zwp_text_input_v3, bound in brain-linux.ks) -- it is UTF-8 by definition.
//   wl_keyboard only delivers keys that never produce text (Escape, arrows,
//   Backspace, Ctrl combos). A hardcoded ASCII keymap remains as a degraded
//   fallback for compositors without zwp_text_input_manager_v3.
module brain_wl_display

// ASCII-safe rendering string: every byte outside printable ASCII becomes
// "?" so text width math stays stable for UTF-8 documents (one '?' per
// byte). This is a width approximation only -- the document itself keeps raw
// UTF-8 bytes.
func brainWlAscii(source) {
    let builder = sbNew()
    let i = 0
    while i < len(source) {
        let byte = charCode(source[i])
        let c = "?"
        if byte >= 32 && byte <= 126 { c = source[i] }
        if byte == 9 { c = " " }
        builder = sbAppend(builder, c)
        i = brainLinuxNext(source, i)
    }
    emit sbToString(builder)
}

// Build the fallback keymap: X11-style keycodes (evdev + 8) -> ASCII byte of
// the unshifted key. Used only when text-input-v3 is unavailable.
// X11-vestige (future-edit item): X11-style keycode grid (evdev+8) — US
// layout only. The real fix is xkbcommon fed by wl_keyboard.keymap over the
// Wayland wire; replace both this table and brainWlKeysym's mapping when that
// lands. Constants only, not an X11 dependency.
func brainWlKeymap() {
    let b = bufNew(128)
    // letters: qwerty row (kc 24..33)
    bufSetByte(b, 24, 113)  bufSetByte(b, 25, 119)  bufSetByte(b, 26, 101)  bufSetByte(b, 27, 114)
    bufSetByte(b, 28, 116)  bufSetByte(b, 29, 121)  bufSetByte(b, 30, 117)  bufSetByte(b, 31, 105)
    bufSetByte(b, 32, 111)  bufSetByte(b, 33, 112)
    // letters: home row (kc 38..46)
    bufSetByte(b, 38, 97)   bufSetByte(b, 39, 115)  bufSetByte(b, 40, 100)  bufSetByte(b, 41, 102)
    bufSetByte(b, 42, 103)  bufSetByte(b, 43, 104)  bufSetByte(b, 44, 106)  bufSetByte(b, 45, 107)
    bufSetByte(b, 46, 108)
    // letters: bottom row (kc 52..58)
    bufSetByte(b, 52, 122)  bufSetByte(b, 53, 120)  bufSetByte(b, 54, 99)   bufSetByte(b, 55, 118)
    bufSetByte(b, 56, 98)   bufSetByte(b, 57, 110)  bufSetByte(b, 58, 109)
    // digits (kc 10..19)
    bufSetByte(b, 10, 49)   bufSetByte(b, 11, 50)   bufSetByte(b, 12, 51)   bufSetByte(b, 13, 52)
    bufSetByte(b, 14, 53)   bufSetByte(b, 15, 54)   bufSetByte(b, 16, 55)   bufSetByte(b, 17, 56)
    bufSetByte(b, 18, 57)   bufSetByte(b, 19, 48)
    // punctuation
    bufSetByte(b, 20, 45)   // -
    bufSetByte(b, 21, 61)   // =
    bufSetByte(b, 34, 91)   // [
    bufSetByte(b, 35, 93)   // ]
    bufSetByte(b, 47, 59)   // ;
    bufSetByte(b, 48, 39)   // '
    bufSetByte(b, 49, 96)   // `
    bufSetByte(b, 51, 92)   // backslash
    bufSetByte(b, 59, 44)   // ,
    bufSetByte(b, 60, 46)   // .
    bufSetByte(b, 61, 47)   // /
    bufSetByte(b, 65, 32)   // space
    emit b
}

// Key symbols that never arrive through text-input-v3: control keys, and
// Ctrl combos. Symbol values match the X11 keysyms the document layer
// (brainLinuxAction) already understands, so that layer stays unchanged.
// Returns 0 for anything printable -- the caller decides whether the
// ASCII fallback may supply the character.
// X11-vestige (future-edit item): the X11/XKB keysym *values* (65361 Left,
// 65293 Return, ...) are the editor's internal key dialect, carried from the
// X11 port. Migrate brainLinuxAction's symbol constants to evdev/keysym-free
// internal ids when the xkbcommon path replaces the ASCII fallback.
func brainWlKeysym(kmap, kc, shift) {
    if kc == 9 { emit 65307 }    // Escape
    if kc == 36 { emit 65293 }   // Return
    if kc == 23 { emit 65289 }   // Tab
    if kc == 22 { emit 65288 }   // BackSpace
    if kc == 119 { emit 65535 }  // Delete
    if kc == 113 { emit 65361 }  // Left
    if kc == 114 { emit 65363 }  // Right
    if kc == 111 { emit 65362 }  // Up
    if kc == 116 { emit 65364 }  // Down
    if kc == 110 { emit 65360 }  // Home
    if kc == 115 { emit 65367 }  // End
    let c = 0
    if kc >= 0 && kc < 128 { c = bufGetByte(kmap, kc) }
    if c == 0 { emit 0 }
    if shift == 0 { emit c }
    // shifted variants
    if c >= 97 && c <= 122 { emit c - 32 }
    if c == 45 { emit 95 }    // -  -> _
    if c == 96 { emit 126 }   // `  -> ~
    if c == 61 { emit 43 }    // =  -> +
    if c == 91 { emit 123 }   // [  -> {
    if c == 93 { emit 125 }   // ]  -> }
    if c == 59 { emit 58 }    // ;  -> :
    if c == 39 { emit 34 }    // '  -> "
    if c == 92 { emit 124 }   // \  -> |
    if c == 44 { emit 60 }    // ,  -> <
    if c == 46 { emit 62 }    // .  -> >
    if c == 47 { emit 63 }    // /  -> ?
    if c == 49 { emit 33 }    // 1  -> !
    if c == 50 { emit 64 }    // 2  -> @
    if c == 51 { emit 35 }    // 3  -> #
    if c == 52 { emit 36 }    // 4  -> $
    if c == 53 { emit 37 }    // 5  -> %
    if c == 54 { emit 94 }    // 6  -> ^
    if c == 55 { emit 38 }    // 7  -> &
    if c == 56 { emit 42 }    // 8  -> *
    if c == 57 { emit 40 }    // 9  -> (
    if c == 48 { emit 41 }    // 0  -> )
    emit c
}

// Wayland messages can span multiple socket reads.
func brainWlReadExact(fd, target, offset, count, scratch) {
    let used = 0
    while used < count {
        let received = sockRecv(fd, scratch, count - used)
        if brainWlSyscallFailed(received) == 1 { emit 0 }
        if received == 0 { emit 0 }
        let i = 0
        while i < received {
            bufSetByte(target, offset + used + i, bufGetByte(scratch, i))
            i += 1
        }
        used += received
    }
    emit 1
}

func brainWlReadMessage(fd, target, scratch) {
    if brainWlReadExact(fd, target, 0, 8, scratch) == 0 { emit 0 }
    let size = wlSize(target, 0)
    if size < 8 || size > 65532 || size % 4 != 0 { emit 0 }
    if brainWlReadExact(fd, target, 8, size - 8, scratch) == 0 { emit 0 }
    emit size
}

func brainWlRegistry(fd, registry, syncId, target, scratch) {
    wlSync(fd, syncId)
    let message = bufNew(65536)
    let used = 0
    while used < 65536 {
        let size = brainWlReadMessage(fd, message, scratch)
        if size == 0 { emit 0 }
        if wlObject(message, 0) == 1 && wlOpcode(message, 0) == 0 { emit 0 }
        if wlObject(message, 0) == syncId && wlOpcode(message, 0) == 0 { emit used }
        if wlObject(message, 0) == registry && wlOpcode(message, 0) == 0 {
            if used + size > 65536 || size < 24 { emit 0 }
            let stringSize = wlU32(message, 12)
            if stringSize < 1 || 20 + _wlPad4(stringSize) != size { emit 0 }
            let i = 0
            while i < size {
                bufSetByte(target, used + i, bufGetByte(message, i))
                i += 1
            }
            used += size
        }
    }
    emit 0
}

func brainWlEventText(message, size) {
    if size < 12 { emit "" }
    let length = wlU32(message, 8)
    if length == 0 { emit "" }
    if length > size - 12 || bufGetByte(message, 12 + length - 1) != 0 { emit "" }
    emit wlTextInputEventText(message, 0)
}


func brainWlModifiers(depressed, latched, locked) {
    let result = 0
    let bit = 1
    while bit <= 8 {
        if depressed / bit % 2 == 1 || latched / bit % 2 == 1 || locked / bit % 2 == 1 {
            result += bit
        }
        bit *= 2
    }
    emit result
}


// Raw syscall errors are negative machine words. Comparing them as generic
// Krypton values can treat the word as a string pointer on older ELF backends.
func brainWlSyscallFailed(value) {
    let word = bufNew(8)
    bufSetQwordAt(word, 0, value)
    emit bufGetByte(word, 7) == 255
}
