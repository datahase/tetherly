package link.tetherly

import android.content.Context
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.KeyEvent
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.EditText

/**
 * A real text field that forwards the soft keyboard to the Mac. Committed text goes to [onText]; Backspace, Return
 * and other special keys go to [onKey] as macOS keycodes. IMEs that compose are handled by diffing the composing text.
 * It is a genuine EditText so voice assistants that fill fields from outside the keyboard (Wispr Flow's bubble sets
 * or pastes text through accessibility) find it; whatever they insert is forwarded and the field is emptied again.
 */
class KeyInputView(context: Context) : EditText(context) {
    var onText: (String) -> Unit = {}
    var onKey: (Int) -> Unit = {}
    var onCaptureChanged: (Boolean) -> Unit = {}
    var onWindowFocus: (Boolean) -> Unit = {}
    private var composing = ""

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        isSingleLine = true
        background = null
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable) {
                if (s.isEmpty()) return
                val text = s.toString()
                s.clear()
                onText(text)
            }
        })
    }

    override fun onPointerCaptureChange(hasCapture: Boolean) {
        super.onPointerCaptureChange(hasCapture)
        onCaptureChanged(hasCapture)
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        onWindowFocus(hasWindowFocus)
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        // A plain text field: password-style fields make voice keyboards and assistants switch themselves off.
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_ACTION_NONE
        composing = ""
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean {
                replaceComposing(text.toString())
                composing = ""
                return true
            }

            override fun setComposingText(text: CharSequence, newCursorPosition: Int): Boolean {
                replaceComposing(text.toString())
                return true
            }

            override fun finishComposingText(): Boolean {
                composing = ""
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                repeat(beforeLength.coerceAtMost(64)) { onKey(MacKeys.DELETE) }
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                if (event.action == KeyEvent.ACTION_DOWN) handleKey(event)
                return true
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        handleKey(event)
        return true
    }

    private fun handleKey(event: KeyEvent) {
        val code = when (event.keyCode) {
            KeyEvent.KEYCODE_DEL -> MacKeys.DELETE
            KeyEvent.KEYCODE_FORWARD_DEL -> MacKeys.FORWARD_DELETE
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> MacKeys.RETURN
            KeyEvent.KEYCODE_TAB -> MacKeys.TAB
            KeyEvent.KEYCODE_ESCAPE -> MacKeys.ESCAPE
            KeyEvent.KEYCODE_DPAD_LEFT -> MacKeys.LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> MacKeys.RIGHT
            KeyEvent.KEYCODE_DPAD_UP -> MacKeys.UP
            KeyEvent.KEYCODE_DPAD_DOWN -> MacKeys.DOWN
            else -> null
        }
        if (code != null) onKey(code) else event.unicodeChar.takeIf { it > 0 }?.let { onText(String(Character.toChars(it))) }
    }

    private fun replaceComposing(new: String) {
        var common = composing.commonPrefixWith(new).length
        if (common > 0 && composing[common - 1].isHighSurrogate()) common--
        val removed = composing.substring(common)
        repeat(removed.codePointCount(0, removed.length)) { onKey(MacKeys.DELETE) }
        new.substring(common).takeIf { it.isNotEmpty() }?.let(onText)
        composing = new
    }
}
