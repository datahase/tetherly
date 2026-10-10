package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeysTest {
    @Test fun usAnsiKeycodes() {
        val expected = mapOf(
            'a' to 0, 's' to 1, 'd' to 2, 'f' to 3, 'h' to 4, 'g' to 5, 'z' to 6, 'x' to 7, 'c' to 8, 'v' to 9, 'b' to 11,
            'q' to 12, 'w' to 13, 'e' to 14, 'r' to 15, 'y' to 16, 't' to 17, '1' to 18, '2' to 19, '3' to 20, '4' to 21,
            '6' to 22, '5' to 23, '=' to 24, '9' to 25, '7' to 26, '-' to 27, '8' to 28, '0' to 29, ']' to 30, 'o' to 31,
            'u' to 32, '[' to 33, 'i' to 34, 'p' to 35, 'l' to 37, 'j' to 38, '\'' to 39, 'k' to 40, ';' to 41, '\\' to 42,
            ',' to 43, '/' to 44, 'n' to 45, 'm' to 46, '.' to 47, '`' to 50, ' ' to 49,
        )
        expected.forEach { (c, code) -> assertEquals("'$c'", code to false, MacKeys.forChar(c)) }
        assertEquals(26, expected.keys.count { it in 'a'..'z' })
    }

    @Test fun shiftedCharactersUseTheBaseKeyPlusShift() {
        assertEquals(0 to true, MacKeys.forChar('A'))
        assertEquals(18 to true, MacKeys.forChar('!'))
        assertEquals(41 to true, MacKeys.forChar(':'))
        assertEquals(44 to true, MacKeys.forChar('?'))
        assertEquals(50 to true, MacKeys.forChar('~'))
    }

    @Test fun nonUsCharactersAreNotMapped() {
        assertNull(MacKeys.forChar('é'))
        assertNull(MacKeys.forChar('ß'))
    }
}

class FnKeysTest {
    @org.junit.Test fun fnTurnsArrowsAndDeleteIntoMacBookEquivalents() {
        org.junit.Assert.assertEquals(listOf(115, 119, 116, 121, MacKeys.FORWARD_DELETE),
            listOf(MacKeys.LEFT, MacKeys.RIGHT, MacKeys.UP, MacKeys.DOWN, MacKeys.DELETE).map(MacKeys::withFn))
        org.junit.Assert.assertEquals(MacKeys.ESCAPE, MacKeys.withFn(MacKeys.ESCAPE))
        org.junit.Assert.assertEquals(12, MacKeys.F_KEYS.toSet().size)
    }
}
