package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ViewTransformTest {
    // A 16:10 Mac in a portrait phone view: letterboxed top and bottom.
    private val view = 1080f to 1800f
    private val content = Box.letterbox(view.first, view.second, 1710f, 1112f)
    private val t = ViewTransform(view.first, view.second, content)
    private fun near(a: Float, b: Float) = assertEquals(a, b, 0.01f)

    @Test fun letterboxCentersAndKeepsAspect() {
        near(0f, content.left); near(1080f, content.width)
        near((1800f - content.height) / 2, content.top)
        near(1710f / 1112f, content.width / content.height)
    }

    @Test fun identityAtOneX() {
        val z = t.clamp(Zoom())
        assertEquals(Zoom(1f, 0f, 0f), z)
        val (nx, ny) = t.toVideo(z, content.left + content.width / 2, content.top + content.height / 4)!!
        near(0.5f, nx); near(0.25f, ny)
    }

    @Test fun outsideTheVideoMapsToNull() {
        assertNull(t.toVideo(Zoom(), 500f, content.top - 1f))
        assertNull(t.toVideo(Zoom(), 500f, content.top + content.height + 1f))
    }

    @Test fun pinchKeepsTheFocalPointStillAndRoundTrips() {
        // At 3x both axes overflow the view, so the clamp leaves the focal point alone.
        val fx = 400f; val fy = 900f
        val before = t.toVideo(Zoom(), fx, fy)!!
        val z = t.pinch(Zoom(), 3f, fx, fy, 0f, 0f)
        near(3f, z.scale)
        val after = t.toVideo(z, fx, fy)!!
        near(before.first, after.first); near(before.second, after.second)
        val (vx, vy) = t.toView(z, 0.3f, 0.6f)
        val back = t.toVideo(z, vx, vy)!!
        near(0.3f, back.first); near(0.6f, back.second)
    }

    @Test fun clampKeepsVideoCoveringTheViewAndLimitsScale() {
        val z = t.clamp(Zoom(9f, 10_000f, 10_000f))
        near(ViewTransform.MAX_SCALE, z.scale)
        // Left edge of the video may not move right of the view's left edge.
        near(0f, content.left * z.scale + z.x)
        val far = t.clamp(Zoom(3f, -100_000f, 0f))
        near(1080f, (content.left + content.width) * far.scale + far.x)
        assertEquals(1f, t.clamp(Zoom(0.2f)).scale)
    }

    @Test fun shortAxisStaysCenteredWhileItFits() {
        // At 1.2x the letterboxed height still fits the tall view, so it stays centered vertically.
        val z = t.clamp(Zoom(1.2f, 0f, -5_000f))
        val top = content.top * z.scale + z.y
        near((1800f - content.height * 1.2f) / 2, top)
    }

    @Test fun followPansOnlyWhenTheCursorLeavesTheMargin() {
        val z = t.clamp(Zoom(3f, -1080f, -1800f))
        val (cx, cy) = t.toVideo(z, 540f, 900f)!! // cursor at the view center
        assertEquals(z, t.follow(z, cx, cy))
        val moved = t.follow(z, 0.95f, cy)
        near(1080f * 0.85f, t.toView(moved, 0.95f, cy).first) // minimal pan: cursor lands exactly on the margin
        near(z.y, moved.y)
        assertEquals(Zoom(), t.follow(Zoom(), 0.99f, 0.99f)) // not zoomed: never pans
    }

    @Test fun followIsClampedAtTheVideoEdge() {
        val z = t.clamp(Zoom(2f, 0f, 0f))
        val f = t.follow(z, 0f, 0.5f)
        near(0f, content.left * f.scale + f.x) // can't pan past the left edge to give the cursor margin
    }

    @Test fun twoFingerClassification() {
        assertEquals(TwoFinger.Undecided, classifyTwoFinger(400f, 405f, 5f))
        assertEquals(TwoFinger.Zoom, classifyTwoFinger(400f, 440f, 5f))
        assertEquals(TwoFinger.Scroll, classifyTwoFinger(400f, 410f, 30f))
        assertEquals(TwoFinger.Zoom, classifyTwoFinger(100f, 115f, 30f)) // spread wins when both happen
        assertEquals(TwoFinger.Undecided, classifyTwoFinger(60f, 70f, 10f)) // jitter floor on a narrow pinch
    }

    @Test fun threeFingerSwipes() {
        assertEquals(null, swipeShortcut(10f, -20f, 100f))
        assertEquals(MacKeys.UP, swipeShortcut(30f, -120f, 100f))
        assertEquals(MacKeys.DOWN, swipeShortcut(0f, 150f, 100f))
        assertEquals(MacKeys.RIGHT, swipeShortcut(-130f, 40f, 100f))
        assertEquals(MacKeys.LEFT, swipeShortcut(130f, 0f, 100f))
    }

    @Test fun trackpadGainIsGentleAndCapped() {
        near(1.2f, trackpadGain(0f))
        assertTrue(trackpadGain(10f) in 1.2f..2.4f)
        near(2.4f, trackpadGain(500f))
    }
}
