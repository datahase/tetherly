package link.tetherly

enum class KeyModifier(val wire: String, val label: String) { Fn("fn", "fn"), Cmd("cmd", "⌘ Cmd"), Shift("shift", "⇧ Shift"), Opt("alt", "⌥ Opt"), Ctrl("ctrl", "⌃ Ctrl") }

/** macOS virtual keycodes, US ANSI layout. */
object MacKeys {
    const val RETURN = 36
    const val TAB = 48
    const val SPACE = 49
    const val DELETE = 51
    const val ESCAPE = 53
    const val FORWARD_DELETE = 117
    const val LEFT = 123
    const val RIGHT = 124
    const val DOWN = 125
    const val UP = 126

    /** F1…F12. */
    val F_KEYS = listOf(122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111)

    /** What fn turns a key into on a MacBook keyboard: arrows become Home, End, Page Up, Page Down; Delete deletes forward. */
    fun withFn(code: Int): Int = when (code) {
        LEFT -> 115
        RIGHT -> 119
        UP -> 116
        DOWN -> 121
        DELETE -> FORWARD_DELETE
        else -> code
    }

    private val base = mapOf(
        'a' to 0, 's' to 1, 'd' to 2, 'f' to 3, 'h' to 4, 'g' to 5, 'z' to 6, 'x' to 7, 'c' to 8, 'v' to 9,
        'b' to 11, 'q' to 12, 'w' to 13, 'e' to 14, 'r' to 15, 'y' to 16, 't' to 17, '1' to 18, '2' to 19, '3' to 20,
        '4' to 21, '6' to 22, '5' to 23, '=' to 24, '9' to 25, '7' to 26, '-' to 27, '8' to 28, '0' to 29, ']' to 30,
        'o' to 31, 'u' to 32, '[' to 33, 'i' to 34, 'p' to 35, 'l' to 37, 'j' to 38, '\'' to 39, 'k' to 40, ';' to 41,
        '\\' to 42, ',' to 43, '/' to 44, 'n' to 45, 'm' to 46, '.' to 47, '`' to 50, ' ' to SPACE,
        '\n' to RETURN, '\t' to TAB,
    )
    private const val SHIFTED = "~!@#$%^&*()_+{}|:\"<>?"
    private const val UNSHIFTED = "`1234567890-=[]\\;',./"

    /** Keycode for a typed character, and whether Shift is needed to produce it; null if not on a US keyboard. */
    fun forChar(c: Char): Pair<Int, Boolean>? {
        base[c]?.let { return it to false }
        if (c in 'A'..'Z') return base.getValue(c.lowercaseChar()) to true
        val i = SHIFTED.indexOf(c)
        return if (i >= 0) base.getValue(UNSHIFTED[i]) to true else null
    }
}
