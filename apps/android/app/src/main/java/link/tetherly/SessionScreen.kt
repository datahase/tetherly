package link.tetherly

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Matrix
import android.hardware.input.InputManager
import android.view.MotionEvent
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.outlined.PowerSettingsNew
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.material.icons.outlined.Swipe
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.WindowInsets as PlatformInsets
import android.view.WindowInsetsController
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.material.icons.outlined.DesktopMac
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.toArgb
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FitScreen
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.KeyboardCommandKey
import androidx.compose.material.icons.outlined.KeyboardHide
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Mouse
import androidx.compose.material.icons.outlined.ScreenRotation
import androidx.compose.material.icons.outlined.StayCurrentLandscape
import androidx.compose.material.icons.outlined.StayCurrentPortrait
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.delay
import org.json.JSONObject
import kotlin.math.hypot

private val SHORTCUTS = listOf(
    "⌘C" to (8 to setOf(KeyModifier.Cmd)), "⌘V" to (9 to setOf(KeyModifier.Cmd)), "⌘X" to (7 to setOf(KeyModifier.Cmd)),
    "⌘Z" to (6 to setOf(KeyModifier.Cmd)), "⌘A" to (0 to setOf(KeyModifier.Cmd)), "⌘Tab" to (MacKeys.TAB to setOf(KeyModifier.Cmd)),
    "⌘Space" to (MacKeys.SPACE to setOf(KeyModifier.Cmd)), "⌘W" to (13 to setOf(KeyModifier.Cmd)), "⌘Q" to (12 to setOf(KeyModifier.Cmd)),
    "Mission Control" to (MacKeys.UP to setOf(KeyModifier.Ctrl)),
)
private val SPECIAL = listOf(
    "Esc" to MacKeys.ESCAPE, "Tab" to MacKeys.TAB, "←" to MacKeys.LEFT, "→" to MacKeys.RIGHT, "↑" to MacKeys.UP,
    "↓" to MacKeys.DOWN, "⌫" to MacKeys.DELETE, "⏎" to MacKeys.RETURN,
)

/** Local zoom state, read and written by the gesture loop directly so pinch steps never see a stale value. */
private class ZoomHolder {
    var zoom by mutableStateOf(Zoom())
    var following = true // auto-follow the Mac cursor until the user pans by hand
    /** Predicted Mac pointer (normalized), used only to keep it in view while zoomed; the video shows the real one. */
    var cursor by mutableStateOf<Pair<Float, Float>?>(null)
    var lastLocalMove = 0L
    var lastTapUp = 0L
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SessionScreen(vm: MainViewModel, state: SessionState) {
    val s = vm.session
    val notice by s.notice.collectAsState()
    val display by s.display.collectAsState()
    val cursor by s.cursor.collectAsState()
    val videoSize by s.videoSize.collectAsState()
    val settings by s.videoSettings.collectAsState()
    val videoStopped by s.videoStopped.collectAsState()
    val offer by s.offer.collectAsState()
    val outgoing by s.outgoing.collectAsState()
    val incoming by s.incoming.collectAsState()
    val macSound by s.macSound.collectAsState()
    var direct by rememberSaveable { mutableStateOf(false) }
    var keysOpen by rememberSaveable { mutableStateOf(false) }
    var mods by remember { mutableStateOf(emptySet<KeyModifier>()) }
    var keyView by remember { mutableStateOf<KeyInputView?>(null) }
    var picking by remember { mutableStateOf(false) }
    var showGestures by remember { mutableStateOf(false) }
    val imeVisible = WindowInsets.isImeVisible
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val activity = LocalActivity.current

    // Toolbar auto-hides in landscape; any toolbar use or the reveal handle restarts the timer.
    var toolbarPoke by remember { mutableIntStateOf(0) }
    var toolbarVisible by remember { mutableStateOf(true) }
    LaunchedEffect(landscape, toolbarPoke) {
        toolbarVisible = true
        if (landscape) { delay(3_500); toolbarVisible = false }
    }
    fun poke() { toolbarPoke++ }

    val openDoc = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let(vm::sendFile) }
    val createDoc = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        picking = false
        s.answerOffer(uri?.toString())
    }

    BackHandler { s.disconnect() }

    DisposableEffect(vm.orientation) {
        activity?.requestedOrientation = when (vm.orientation) {
            MainViewModel.Orientation.Auto -> ActivityInfo.SCREEN_ORIENTATION_USER // follows the system auto-rotate setting
            MainViewModel.Orientation.Landscape -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            MainViewModel.Orientation.Portrait -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
        }
        onDispose {}
    }
    // Leaving the session restores the orientation the phone had when it started. With system auto-rotate off,
    // handing back "unspecified" leaves some phones stuck in the last forced rotation, so request it explicitly.
    val entryOrientation = remember { activity?.resources?.configuration?.orientation ?: Configuration.ORIENTATION_PORTRAIT }
    DisposableEffect(Unit) {
        onDispose {
            vm.resetOrientation()
            val a = activity ?: return@onDispose
            val autoRotate = android.provider.Settings.System.getInt(a.contentResolver, android.provider.Settings.System.ACCELEROMETER_ROTATION, 0) == 1
            a.requestedOrientation = when {
                autoRotate -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                entryOrientation == Configuration.ORIENTATION_LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                else -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            }
        }
    }
    // Ask for the screen's fastest refresh mode at the current resolution while viewing, so high-fps video shows.
    DisposableEffect(Unit) {
        val window = activity?.window
        val before = window?.attributes?.preferredDisplayModeId ?: 0
        val display = activity?.display
        val current = display?.mode
        val best = display?.supportedModes
            ?.filter { current == null || (it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight) }
            ?.maxByOrNull { it.refreshRate }
        val beforeRate = window?.attributes?.preferredRefreshRate ?: 0f
        // Newer Android groups 60/90/120 into one mode, so the refresh-rate hint is what the OEM policy follows.
        val bestRate = display?.supportedModes?.flatMap { m -> listOf(m.refreshRate) + m.alternativeRefreshRates.toList() }?.maxOrNull() ?: 0f
        if (window != null && best != null) {
            window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId; preferredRefreshRate = bestRate }
        }
        onDispose {
            if (window != null) window.attributes = window.attributes.apply { preferredDisplayModeId = before; preferredRefreshRate = beforeRate }
        }
    }
    // Landscape is immersive: system bars hide and come back with a swipe from the edge.
    DisposableEffect(landscape) {
        val controller = activity?.window?.insetsController
        if (landscape) {
            controller?.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller?.hide(PlatformInsets.Type.systemBars())
        } else {
            controller?.show(PlatformInsets.Type.systemBars())
        }
        onDispose { controller?.show(PlatformInsets.Type.systemBars()) }
    }

    // Sticky modifiers apply to the next key only. With a modifier active, a character becomes a key press.
    fun typed(text: String) {
        if (mods.isEmpty()) {
            text.split('\n').forEachIndexed { i, part ->
                if (i > 0) s.key(MacKeys.RETURN)
                if (part.isNotEmpty()) s.typeText(part)
            }
            return
        }
        val c = text.singleOrNull()
        val mapped = c?.let(MacKeys::forChar)
        if (mapped != null) s.key(mapped.first, if (mapped.second) mods + KeyModifier.Shift else mods) else s.typeText(text)
        mods = emptySet()
    }

    fun special(code: Int) {
        s.key(if (KeyModifier.Fn in mods) MacKeys.withFn(code) else code, mods)
        mods = emptySet()
    }
    val typedState = rememberUpdatedState(::typed)
    val specialState = rememberUpdatedState(::special)

    fun toggleKeyboard() {
        val v = keyView ?: return
        val imm = v.context.getSystemService(InputMethodManager::class.java)
        if (imeVisible) imm.hideSoftInputFromWindow(v.windowToken, 0) else { v.requestFocus(); imm.showSoftInput(v, 0) }
    }

    // Physical mouse: when one is connected, capture it so it drives the Mac instead of Android's own cursor.
    val context = LocalContext.current
    var mouseConnected by remember { mutableStateOf(false) }
    var mouseWanted by rememberSaveable { mutableStateOf(true) }
    var mouseCaptured by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        val im = context.getSystemService(InputManager::class.java)
        fun refresh() { mouseConnected = hasExternalMouse(im) }
        val listener = object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(id: Int) = refresh()
            override fun onInputDeviceRemoved(id: Int) = refresh()
            override fun onInputDeviceChanged(id: Int) = refresh()
        }
        refresh()
        im.registerInputDeviceListener(listener, null)
        onDispose { im.unregisterInputDeviceListener(listener) }
    }
    val mouse = remember { MouseForwarder() }
    LaunchedEffect(mouseConnected, mouseWanted, keyView) {
        val v = keyView ?: return@LaunchedEffect
        if (mouseConnected && mouseWanted) { v.requestFocus(); v.requestPointerCapture() } else v.releasePointerCapture()
    }

    var zoomRef by remember { mutableStateOf<ZoomHolder?>(null) }
    val haptics = LocalHapticFeedback.current

    // The Mac screen with its own touch handling and local zoom; placed by the orientation layout below.
    val videoArea: @Composable (Modifier) -> Unit = { modifier ->
        BoxWithConstraints(modifier) {
            val viewW = constraints.maxWidth.toFloat()
            val viewH = constraints.maxHeight.toFloat()
            // Must stay the same object between redraws: it keys the touch handler, and a new key restarts the
            // gesture mid-swipe (cursor updates and zoom steps redraw up to 60 times a second).
            val transform = remember(viewW, viewH, videoSize) {
                videoSize?.let { (w, h) -> ViewTransform(viewW, viewH, Box.letterbox(viewW, viewH, w.toFloat(), h.toFloat())) }
            }
            // A new view size (rotation, keyboard) or video size starts again at Fit.
            val holder = remember(viewW, viewH, videoSize) { ZoomHolder() }.also { h ->
                if (h.cursor == null) cursor?.let { h.cursor = it.x.toFloat() to it.y.toFloat() }
            }
            SideEffect { zoomRef = holder }

            VideoTexture(vm.decoder, transform, holder.zoom, viewW, viewH)
            if (videoSize == null) {
                SessionLoader((state as? SessionState.Connected)?.host ?: (state as? SessionState.Reconnecting)?.host, Modifier.align(Alignment.Center))
            }

            LaunchedEffect(cursor) {
                val c = cursor ?: return@LaunchedEffect
                // While the finger is moving, the Mac's report lags our own prediction, so trust the prediction.
                if (android.os.SystemClock.uptimeMillis() - holder.lastLocalMove > 150 || holder.cursor == null) {
                    holder.cursor = c.x.toFloat() to c.y.toFloat()
                }
            }
            LaunchedEffect(holder.cursor, transform) {
                val c = holder.cursor ?: return@LaunchedEffect
                if (transform != null && !direct && holder.following) holder.zoom = transform.follow(holder.zoom, c.first, c.second)
            }

            // The touch handler outlives redraws, so it reads these through state to always see current values.
            val onTouchNow = rememberUpdatedState { if (landscape) toolbarVisible = false }
            val onLocalMoveNow = rememberUpdatedState { dx: Float, dy: Float ->
                val d = display
                val c = holder.cursor
                if (d != null && c != null) {
                    holder.cursor = (c.first + dx / d.width.toFloat()).coerceIn(0f, 1f) to (c.second + dy / d.height.toFloat()).coerceIn(0f, 1f)
                }
                holder.lastLocalMove = android.os.SystemClock.uptimeMillis()
            }
            Box(
                Modifier.fillMaxSize().remoteInput(
                    send = s::send, direct = direct, transform = transform, holder = holder, pointsPerDp = 1f,
                    onDragStart = { haptics.performHapticFeedback(HapticFeedbackType.LongPress) },
                    onTouch = { onTouchNow.value() },
                    onLocalMove = { dx, dy -> onLocalMoveNow.value(dx, dy) },
                ),
            )
        }
    }

    val toolbar: @Composable () -> Unit = {
        Toolbar(
            title = when (state) {
                is SessionState.Connected -> state.host
                is SessionState.Reconnecting -> "Reconnecting to ${state.host}"
                else -> ""
            },
            route = when (state) {
                is SessionState.Connected -> if (isTailscaleHost(state.address.host)) "via Tailscale" else "via Wi-Fi"
                else -> null
            },
            direct = direct, zoomed = zoomRef?.zoom?.zoomed == true, keyboardOpen = imeVisible, keysOpen = keysOpen,
            orientation = vm.orientation, landscapeNow = landscape, settings = settings,
            mouseConnected = mouseConnected, mouseCaptured = mouseCaptured,
            onMouse = { poke(); mouseWanted = !mouseCaptured },
            onKeyboard = { poke(); toggleKeyboard() },
            onMissionControl = { poke(); s.send(msg("key", "code" to MacKeys.UP, "modifiers" to org.json.JSONArray(listOf("ctrl")))) },
            onKeys = { poke(); keysOpen = !keysOpen },
            onMode = { poke(); direct = !direct },
            onFit = { poke(); zoomRef?.let { it.zoom = Zoom(); it.following = true } },
            onOrientation = { o -> poke(); vm.lockOrientation(o) },
            onMenu = ::poke,
            onSendClipboard = vm::sendClipboard,
            onGetClipboard = s::requestClipboard,
            onSendFile = { openDoc.launch(arrayOf("*/*")) },
            onQuality = { d -> s.setVideoSettings(settings.copy(maxDimension = d)) },
            onFps = { f -> s.setVideoSettings(settings.copy(fps = f)) },
            maxFps = vm.maxFps,
            onGestures = { showGestures = true },
            onDisconnect = s::disconnect,
            macSound = macSound, onMacSound = { s.setMacSound(!macSound) },
        )
    }

    val notices: @Composable () -> Unit = {
        Column(Modifier.widthIn(max = 560.dp).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (state is SessionState.Reconnecting) Banner("Connection lost. ${state.reason} Retrying, attempt ${state.attempt}.", "Stop") { s.disconnect() }
            videoStopped?.let { Banner(it, "Retry video") { s.retryVideo() } }
            notice?.let { Banner(it, "Dismiss") { s.dismissNotice() } }
            outgoing?.let { Transfer("Sending to Mac", it, s::cancelOutgoing, s::dismissTransfers) }
            incoming?.let { Transfer("Receiving from Mac", it, s::cancelIncoming, s::dismissTransfers) }
        }
    }

    Box(Modifier.fillMaxSize().background(Brand.Ink).imePadding()) {
        Column(Modifier.fillMaxSize()) {
            if (!landscape) {
                Column(
                    Modifier.fillMaxWidth().statusBarsPadding().padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
                ) { toolbar(); notices() }
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val w = constraints.maxWidth.toFloat()
                val h = constraints.maxHeight.toFloat()
                val aspect = videoSize?.let { (vw, vh) -> vw.toFloat() / vh } ?: (16f / 10f)
                val density = LocalDensity.current
                fun Float.dp() = with(density) { toDp() }
                val panelHeight = h - w / aspect
                val side = (w - h * aspect) / 2
                when {
                    // While the keyboard is open, the screen and the key bar get the space; the mouse controls return after.
                    imeVisible -> videoArea(Modifier.fillMaxSize())
                    // Portrait: the Mac screen on top, a laptop-style trackpad in the space below it.
                    !landscape && panelHeight >= with(density) { 180.dp.toPx() } -> Column(Modifier.fillMaxSize()) {
                        videoArea(Modifier.fillMaxWidth().height((w / aspect).dp()))
                        TrackpadPanel(s::send, haptics, Modifier.weight(1f).fillMaxWidth().navigationBarsPadding().padding(12.dp))
                    }
                    // Landscape: scroll strip in the left margin, click buttons and a horizontal strip in the right.
                    landscape && side >= with(density) { 72.dp.toPx() } -> Row(Modifier.fillMaxSize()) {
                        ScrollStrip(vertical = true, send = s::send, modifier = Modifier.width(side.dp()).fillMaxHeight().padding(8.dp))
                        videoArea(Modifier.weight(1f).fillMaxHeight())
                        Column(Modifier.width(side.dp()).fillMaxHeight().padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            MouseButton("Left", "left", s::send, haptics, Modifier.weight(1f).fillMaxWidth())
                            MouseButton("Right", "right", s::send, haptics, Modifier.weight(1f).fillMaxWidth())
                            ScrollStrip(vertical = false, send = s::send, modifier = Modifier.fillMaxWidth().height(64.dp))
                        }
                    }
                    else -> videoArea(Modifier.fillMaxSize())
                }
            }

            val fieldText = MaterialTheme.colorScheme.onSurface.toArgb()
            val fieldHint = MaterialTheme.colorScheme.onSurfaceVariant.toArgb()
            AndroidView(
                factory = { ctx -> KeyInputView(ctx).also { keyView = it } },
                update = { v ->
                    v.onText = { typedState.value(it) }
                    v.onKey = { specialState.value(it) }
                    v.onCaptureChanged = { mouseCaptured = it }
                    v.setOnCapturedPointerListener { _, e -> mouse.handle(e, s::send) }
                    // Capture is dropped when the window loses focus (a dialog, the notification shade); take it back.
                    v.onWindowFocus = { focused -> if (focused && mouseConnected && mouseWanted) { v.requestFocus(); v.requestPointerCapture() } }
                    v.hint = "Type or dictate to your Mac"
                    v.setTextColor(fieldText)
                    v.setHintTextColor(fieldHint)
                },
                // Visible while the keyboard is open so voice assistants (Wispr Flow's bubble) have a field to fill.
                modifier = if (imeVisible) Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(12.dp)).padding(horizontal = 8.dp)
                else Modifier.size(1.dp).alpha(0f),
            )
            if (imeVisible || keysOpen) {
                KeyBar(
                    mods = mods, onMod = { m -> mods = if (m in mods) mods - m else mods + m },
                    onSpecial = ::special, onShortcut = { code, m -> s.key(code, m) },
                    onFnPress = { down -> s.send(msg("modifier", "key" to "fn", "down" to down)) },
                    modifier = if (landscape || imeVisible) Modifier else Modifier.navigationBarsPadding(),
                )
            }
        }

        if (landscape) {
            Column(
                Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AnimatedVisibility(toolbarVisible, enter = fadeIn(), exit = fadeOut()) { toolbar() }
                if (!toolbarVisible) {
                    Surface(
                        onClick = ::poke, shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.5f),
                        contentColor = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.size(40.dp),
                    ) { Box(contentAlignment = Alignment.Center) { Icon(Icons.Outlined.UnfoldMore, contentDescription = "Show controls") } }
                }
                notices()
            }
        }

    }

    if (showGestures) {
        AlertDialog(
            onDismissRequest = { showGestures = false },
            title = { Text("Trackpad gestures") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf(
                        "Move" to "Slide one finger",
                        "Click" to "Tap",
                        "Double-click" to "Tap twice quickly",
                        "Right-click" to "Tap with two fingers",
                        "Drag" to "Double-tap and hold, then slide. Or press and hold, then slide.",
                        "Scroll" to "Slide two fingers",
                        "Zoom this view" to "Pinch with two fingers. Fit resets it.",
                    ).forEach { (what, how) ->
                        Column {
                            Text(what, style = MaterialTheme.typography.titleSmall)
                            Text(how, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showGestures = false }) { Text("Done") } },
        )
    }

    offer?.takeIf { !picking }?.let { o ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text("Receive a file from your Mac?") },
            text = { Text("${o.name}, ${formatSize(o.size)}. Choose where to save it on this phone.") },
            confirmButton = { TextButton(onClick = { picking = true; createDoc.launch(o.name) }) { Text("Choose location") } },
            dismissButton = { TextButton(onClick = { s.answerOffer(null) }) { Text("Decline") } },
        )
    }
}

/** Renders decoded video into a TextureView whose matrix applies the letterbox and the local zoom. */
@Composable
private fun VideoTexture(decoder: VideoDecoder, transform: ViewTransform?, zoom: Zoom, viewW: Float, viewH: Float) {
    AndroidView(
        factory = { ctx ->
            TextureView(ctx).apply {
                keepScreenOn = true
                surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                    var surface: Surface? = null
                    override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                        surface = Surface(st).also(decoder::setSurface) // restarting the decoder requests a keyframe
                    }
                    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                        decoder.setSurface(null)
                        surface?.release()
                        surface = null
                        return true
                    }
                    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
                }
            }
        },
        update = { v ->
            val c = transform?.content ?: return@AndroidView
            if (viewW <= 0f || viewH <= 0f) return@AndroidView
            v.setTransform(Matrix().apply {
                setScale(c.width / viewW * zoom.scale, c.height / viewH * zoom.scale)
                postTranslate(c.left * zoom.scale + zoom.x, c.top * zoom.scale + zoom.y)
            })
        },
        modifier = Modifier.fillMaxSize(),
    )
}

@Composable
private fun Toolbar(
    title: String, route: String?, direct: Boolean, zoomed: Boolean, keyboardOpen: Boolean, keysOpen: Boolean,
    orientation: MainViewModel.Orientation, landscapeNow: Boolean, settings: VideoSettings,
    mouseConnected: Boolean, mouseCaptured: Boolean, onMouse: () -> Unit,
    onKeyboard: () -> Unit, onMissionControl: () -> Unit, onKeys: () -> Unit, onMode: () -> Unit, onFit: () -> Unit, onOrientation: (MainViewModel.Orientation) -> Unit, onMenu: () -> Unit,
    onSendClipboard: () -> Unit, onGetClipboard: () -> Unit, onSendFile: () -> Unit,
    onQuality: (Int) -> Unit, onFps: (Int) -> Unit, onDisconnect: () -> Unit, maxFps: Int, onGestures: () -> Unit,
    macSound: Boolean, onMacSound: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Surface(
        // Translucent colors get no automatic content color, so set it explicitly for both themes.
        shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.8f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp, shadowElevation = 6.dp,
        modifier = Modifier.padding(horizontal = 12.dp),
    ) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        // Scrolls on very narrow screens so every control stays reachable; Disconnect stays pinned outside it.
        Row(Modifier.weight(1f, fill = false).horizontalScroll(rememberScrollState()).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.widthIn(max = 104.dp)) {
                Text(title, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                route?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
            }
            Spacer(Modifier.size(4.dp))
            ToolButton(Icons.Outlined.GridView, "Mission Control: show all windows", onMissionControl)
            ToolButton(if (macSound) Icons.Outlined.VolumeUp else Icons.Outlined.VolumeOff, if (macSound) "Mute Mac sound" else "Play Mac sound", onMacSound, selected = macSound)
            ToolButton(if (keyboardOpen) Icons.Outlined.KeyboardHide else Icons.Outlined.Keyboard, if (keyboardOpen) "Hide keyboard" else "Show keyboard", onKeyboard)
            ToolButton(Icons.Outlined.KeyboardCommandKey, if (keysOpen) "Hide Mac keys" else "Show Mac keys", onKeys, selected = keysOpen)
            ToolButton(if (direct) Icons.Outlined.TouchApp else Icons.Outlined.Swipe, if (direct) "Direct touch, switch to trackpad" else "Trackpad, switch to direct touch", onMode)
            if (mouseConnected) ToolButton(Icons.Outlined.Mouse, if (mouseCaptured) "Mouse controls the Mac. Tap to release" else "Use mouse for the Mac", onMouse, selected = mouseCaptured)
            if (zoomed) ToolButton(Icons.Outlined.FitScreen, "Fit screen", onFit)
            // One toggle: switches to the other orientation and locks it. Sessions start on the system's auto-rotate.
            ToolButton(
                if (landscapeNow) Icons.Outlined.StayCurrentPortrait else Icons.Outlined.StayCurrentLandscape,
                if (landscapeNow) "Switch to portrait" else "Switch to landscape",
                { onOrientation(if (landscapeNow) MainViewModel.Orientation.Portrait else MainViewModel.Orientation.Landscape) },
            )
            Box {
                ToolButton(Icons.Outlined.MoreVert, "More", { onMenu(); menu = true })
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Send clipboard to Mac") }, onClick = { menu = false; onSendClipboard() })
                    DropdownMenuItem(text = { Text("Get Mac clipboard") }, onClick = { menu = false; onGetClipboard() })
                    DropdownMenuItem(text = { Text("Send file") }, onClick = { menu = false; onSendFile() })
                    HorizontalDivider()
                    listOf(1920, 1280, 960).forEach { d ->
                        DropdownMenuItem(text = { Text("Quality ${d}p") }, onClick = { menu = false; onQuality(d) },
                            trailingIcon = { if (settings.maxDimension == d) Text("✓") })
                    }
                    (listOf(maxFps) + listOf(60, 30).filter { it < maxFps }).forEach { f ->
                        DropdownMenuItem(
                            text = { Text(if (f == maxFps) "Smoothest, up to $f fps" else "$f fps") },
                            onClick = { menu = false; onFps(f) },
                            trailingIcon = { if (settings.fps == f) Text("✓") },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(text = { Text("Gestures") }, onClick = { menu = false; onGestures() })
                }
            }
        }
        Surface(
            onClick = onDisconnect, shape = CircleShape, color = MaterialTheme.colorScheme.errorContainer,
            contentColor = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.padding(start = 2.dp, end = 6.dp).size(36.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.PowerSettingsNew, contentDescription = "Disconnect", modifier = Modifier.size(20.dp))
            }
        }
      }
    }
}

@Composable
private fun ToolButton(icon: ImageVector, label: String, onClick: () -> Unit, selected: Boolean = false) {
    IconButton(onClick = onClick) {
        Icon(icon, contentDescription = label, tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun KeyBar(
    mods: Set<KeyModifier>, onMod: (KeyModifier) -> Unit, onSpecial: (Int) -> Unit, onShortcut: (Int, Set<KeyModifier>) -> Unit,
    onFnPress: (Boolean) -> Unit, modifier: Modifier,
) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, modifier = modifier.fillMaxWidth()) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            KeyModifier.entries.forEach { m ->
                if (m == KeyModifier.Fn) FnChip(selected = m in mods, onToggle = { onMod(m) }, onPress = onFnPress)
                else FilterChip(selected = m in mods, onClick = { onMod(m) }, label = { Text(m.label) }, shape = RoundedCornerShape(12.dp))
            }
            // fn shows the function keys, like the top row of a MacBook.
            if (KeyModifier.Fn in mods) MacKeys.F_KEYS.forEachIndexed { i, code ->
                AssistChip(onClick = { onSpecial(code) }, label = { Text("F${i + 1}") }, shape = RoundedCornerShape(12.dp))
            }
            SPECIAL.forEach { (label, code) -> AssistChip(onClick = { onSpecial(code) }, label = { Text(label) }, shape = RoundedCornerShape(12.dp)) }
            SHORTCUTS.forEach { (label, k) -> AssistChip(onClick = { onShortcut(k.first, k.second) }, label = { Text(label) }, shape = RoundedCornerShape(12.dp)) }
        }
    }
}

/**
 * The fn key behaves like the real one: touching sends fn down and lifting sends fn up, so holding it is push-to-talk
 * for dictation apps on the Mac (and a double tap reaches double-tap shortcuts). A tap also makes fn sticky for the
 * next key, for fn + arrows and F1-F12.
 */
@Composable
private fun FnChip(selected: Boolean, onToggle: () -> Unit, onPress: (Boolean) -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = when {
            pressed -> MaterialTheme.colorScheme.primary
            selected -> MaterialTheme.colorScheme.primaryContainer
            else -> MaterialTheme.colorScheme.surfaceContainerHigh
        },
        contentColor = when {
            pressed -> MaterialTheme.colorScheme.onPrimary
            selected -> MaterialTheme.colorScheme.onPrimaryContainer
            else -> MaterialTheme.colorScheme.onSurface
        },
        modifier = Modifier.height(32.dp).semantics { contentDescription = "fn key" }.pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                down.consume()
                pressed = true
                onPress(true)
                val start = down.uptimeMillis
                var up = down.uptimeMillis
                while (true) {
                    val e = awaitPointerEvent()
                    e.changes.forEach { it.consume() }
                    if (e.changes.none { it.pressed }) { up = e.changes.first().uptimeMillis; break }
                }
                onPress(false)
                pressed = false
                if (up - start < 400) onToggle() // a quick tap also arms fn for the next key
            }
        },
    ) {
        Box(Modifier.padding(horizontal = 16.dp), contentAlignment = Alignment.Center) { Text("fn", style = MaterialTheme.typography.labelLarge) }
    }
}

@Composable
private fun Banner(text: String, action: String, onAction: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.95f),
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = onAction) { Text(action) }
        }
    }
}

@Composable
private fun Transfer(label: String, t: TransferUi, cancel: () -> Unit, dismiss: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.95f),
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Column(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 6.dp, bottom = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("$label: ${t.name}", style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(t.status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                }
                if (t.active) TextButton(onClick = cancel) { Text("Cancel") } else TextButton(onClick = dismiss) { Text("OK") }
            }
            if (t.active) LinearProgressIndicator(
                progress = { if (t.size == 0L) 0f else t.done.toFloat() / t.size },
                modifier = Modifier.fillMaxWidth().padding(end = 10.dp),
            )
        }
    }
}

private fun formatSize(bytes: Long) = when {
    bytes >= 1L shl 30 -> "%.1f GB".format(bytes / (1L shl 30).toDouble())
    bytes >= 1L shl 20 -> "%.1f MB".format(bytes / (1L shl 20).toDouble())
    bytes >= 1L shl 10 -> "%.1f KB".format(bytes / 1024.0)
    else -> "$bytes bytes"
}

private fun PointerInputChange.travel() = position - previousPosition

/**
 * Touch → Mac input, plus local zoom. Trackpad: drag moves, tap clicks, two-finger tap right-clicks, long-press then
 * drag holds the button. Two fingers either scroll the Mac or pinch-zoom this view, decided once per gesture by
 * [classifyTwoFinger]. Direct: the finger maps through letterbox and zoom to pointer_abs; touches outside the video
 * are ignored.
 */
private fun Modifier.remoteInput(
    send: (JSONObject) -> Unit, direct: Boolean, transform: ViewTransform?, holder: ZoomHolder, pointsPerDp: Float,
    onDragStart: () -> Unit, onTouch: () -> Unit, onLocalMove: (Float, Float) -> Unit,
) = pointerInput(direct, transform) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        onTouch()
        val slop = viewConfiguration.touchSlop
        val longPress = viewConfiguration.longPressTimeoutMillis
        var maxPointers = 1
        var moved = false
        var dragging = false
        var travel = Offset.Zero
        var accX = 0f
        var accY = 0f
        var scrollX = 0f
        var scrollY = 0f
        var mode = TwoFinger.Undecided
        var startSpan = 0f
        var lastSpan = 0f
        var lastCentroid = Offset.Zero
        var centroidTravel = 0f
        var swipeStart: Offset? = null
        var swipeFingers = 0
        var swiped = false

        fun absolute(p: Offset): Boolean {
            val (x, y) = transform?.toVideo(holder.zoom, p.x, p.y) ?: return false
            send(msg("pointer_abs", "x" to x.toDouble(), "y" to y.toDouble()))
            return true
        }

        fun relative(d: Offset) {
            val dpX = d.x / density
            val dpY = d.y / density
            val k = trackpadGain(hypot(dpX, dpY)) * pointsPerDp
            accX += dpX * k
            accY += dpY * k
            val dx = accX.toInt()
            val dy = accY.toInt()
            accX -= dx
            accY -= dy
            if (dx != 0 || dy != 0) {
                send(msg("pointer", "dx" to dx, "dy" to dy))
                onLocalMove(dx.toFloat(), dy.toFloat())
            }
        }

        fun scroll(d: Offset) {
            scrollX += d.x
            scrollY += d.y
            val dx = scrollX.toInt()
            val dy = scrollY.toInt()
            scrollX -= dx
            scrollY -= dy
            if (dx != 0 || dy != 0) send(msg("scroll", "dx" to dx, "dy" to dy))
        }

        val startedInside = !direct || absolute(down.position)
        // A touch shortly after a tap, in trackpad mode, becomes a drag once it moves (like a laptop trackpad).
        val tapDrag = !direct && down.uptimeMillis - holder.lastTapUp < viewConfiguration.doubleTapTimeoutMillis
        while (true) {
            val waitingForLongPress = !moved && !dragging && maxPointers == 1 && !direct && !tapDrag
            val event = if (waitingForLongPress) {
                val left = longPress - (android.os.SystemClock.uptimeMillis() - down.uptimeMillis)
                withTimeoutOrNull(left.coerceAtLeast(1)) { awaitPointerEvent() }
            } else {
                awaitPointerEvent()
            }
            if (event == null) {
                dragging = true
                onDragStart()
                send(msg("button", "button" to "left", "down" to true))
                continue
            }
            val pressed = event.changes.filter { it.pressed }
            if (pressed.isEmpty()) break
            maxPointers = maxOf(maxPointers, pressed.size)

            // Three or more fingers: one Mission Control / desktop switch per swipe, then nothing else this gesture.
            if (maxPointers >= 3 && !dragging) {
                val centroid = pressed.fold(Offset.Zero) { acc, p -> acc + p.position } / pressed.size.toFloat()
                if (pressed.size != swipeFingers) { swipeStart = centroid; swipeFingers = pressed.size } // a finger landed or lifted
                val start = swipeStart!!
                if (!swiped && pressed.size >= 3) swipeShortcut(centroid.x - start.x, centroid.y - start.y, 48.dp.toPx())?.let {
                    send(msg("key", "code" to it, "modifiers" to org.json.JSONArray(listOf("ctrl"))))
                    swiped = true
                }
                moved = true
                event.changes.forEach { it.consume() }
                continue
            }

            if (pressed.size >= 2 && !dragging) {
                val a = pressed[0].position
                val b = pressed[1].position
                val centroid = (a + b) / 2f
                val span = (a - b).getDistance()
                if (startSpan == 0f) { startSpan = span; lastSpan = span; lastCentroid = centroid }
                centroidTravel += (centroid - lastCentroid).getDistance()
                if (mode == TwoFinger.Undecided) mode = classifyTwoFinger(startSpan, span, centroidTravel)
                if (mode == TwoFinger.Zoom && transform == null) mode = TwoFinger.Scroll // the trackpad panel has nothing to zoom
                when (mode) {
                    TwoFinger.Zoom -> if (transform != null && lastSpan > 0f) {
                        holder.zoom = transform.pinch(holder.zoom, span / lastSpan, centroid.x, centroid.y, centroid.x - lastCentroid.x, centroid.y - lastCentroid.y)
                        holder.following = false
                        moved = true
                    }
                    TwoFinger.Scroll -> { scroll(centroid - lastCentroid); moved = true }
                    TwoFinger.Undecided -> {}
                }
                lastSpan = span
                lastCentroid = centroid
            } else if (pressed.size == 1 && mode == TwoFinger.Undecided) {
                val delta = pressed[0].takeIf { it.previousPressed }?.travel() ?: Offset.Zero
                if (!moved) {
                    travel += delta
                    if (travel.getDistance() > slop) {
                        moved = true
                        if (tapDrag && !dragging) {
                            dragging = true
                            onDragStart()
                            send(msg("button", "button" to "left", "down" to true))
                        }
                    }
                }
                if (moved || dragging) {
                    if (direct) { if (startedInside) absolute(pressed[0].position) } else { relative(delta); holder.following = true }
                }
            }
            event.changes.forEach { it.consume() }
        }
        when {
            dragging -> send(msg("button", "button" to "left", "down" to false))
            moved -> {}
            maxPointers >= 2 -> send(msg("click", "button" to "right", "count" to 1))
            direct && !startedInside -> {}
            else -> {
                send(msg("click", "button" to "left", "count" to 1))
                holder.lastTapUp = android.os.SystemClock.uptimeMillis()
            }
        }
    }
}

/** Laptop-style trackpad for the space under the Mac screen: surface, scroll strips and click buttons. */
@Composable
private fun TrackpadPanel(send: (JSONObject) -> Unit, haptics: androidx.compose.ui.hapticfeedback.HapticFeedback, modifier: Modifier) {
    val holder = remember { ZoomHolder() }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.weight(1f).fillMaxHeight()) {
                Box(
                    Modifier.fillMaxSize().remoteInput(
                        send = send, direct = false, transform = null, holder = holder, pointsPerDp = 1f,
                        onDragStart = { haptics.performHapticFeedback(HapticFeedbackType.LongPress) },
                        onTouch = {}, onLocalMove = { _, _ -> },
                    ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Trackpad", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                }
            }
            ScrollStrip(vertical = true, send = send, modifier = Modifier.width(56.dp).fillMaxHeight())
        }
        ScrollStrip(vertical = false, send = send, modifier = Modifier.fillMaxWidth().height(48.dp))
        Row(Modifier.fillMaxWidth().height(56.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MouseButton("Left", "left", send, haptics, Modifier.weight(1f).fillMaxHeight())
            MouseButton("Right", "right", send, haptics, Modifier.weight(1f).fillMaxHeight())
        }
    }
}

/** Drag along the strip to scroll the Mac; content follows the finger, like two-finger scrolling. */
@Composable
private fun ScrollStrip(vertical: Boolean, send: (JSONObject) -> Unit, modifier: Modifier) {
    var active by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = if (active) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = if (active) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.semantics { contentDescription = if (vertical) "Vertical scroll strip" else "Horizontal scroll strip" }
            .pointerInput(vertical) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    active = true
                    var acc = 0f
                    while (true) {
                        val e = awaitPointerEvent()
                        val c = e.changes.firstOrNull { it.pressed } ?: break
                        val d = c.position - c.previousPosition
                        acc += (if (vertical) d.y else d.x) * 1.6f
                        val n = acc.toInt()
                        acc -= n
                        if (n != 0) send(if (vertical) msg("scroll", "dx" to 0, "dy" to n) else msg("scroll", "dx" to n, "dy" to 0))
                        e.changes.forEach { it.consume() }
                    }
                    active = false
                }
            },
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(if (vertical) Icons.Outlined.SwapVert else Icons.Outlined.SwapHoriz, contentDescription = null)
        }
    }
}

/** A physical-style mouse button: press sends button down, release sends button up, so holding it drags. */
@Composable
private fun MouseButton(label: String, wire: String, send: (JSONObject) -> Unit, haptics: androidx.compose.ui.hapticfeedback.HapticFeedback, modifier: Modifier) {
    var pressed by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = if (pressed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = if (pressed) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
        modifier = modifier.semantics { contentDescription = "$label mouse button" }
            .pointerInput(wire) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false).consume()
                    pressed = true
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    send(msg("button", "button" to wire, "down" to true))
                    while (true) {
                        val e = awaitPointerEvent()
                        e.changes.forEach { it.consume() }
                        if (e.changes.none { it.pressed }) break
                    }
                    send(msg("button", "button" to wire, "down" to false))
                    pressed = false
                }
            },
    ) {
        Box(contentAlignment = Alignment.Center) { Text(label, style = MaterialTheme.typography.labelLarge) }
    }
}

private fun hasExternalMouse(im: InputManager) = im.inputDeviceIds.any { id ->
    val d = im.getInputDevice(id) ?: return@any false
    !d.isVirtual && d.isExternal && d.supportsSource(android.view.InputDevice.SOURCE_MOUSE)
}

/** Turns captured (relative) mouse events into Mac pointer, button and scroll messages. */
private class MouseForwarder {
    private var accX = 0f
    private var accY = 0f

    fun handle(e: MotionEvent, send: (JSONObject) -> Unit): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_HOVER_MOVE -> {
                // In capture mode x/y are relative deltas; batched history arrives first.
                for (i in 0 until e.historySize) { accX += e.getHistoricalX(i); accY += e.getHistoricalY(i) }
                accX += e.x
                accY += e.y
                val dx = accX.toInt()
                val dy = accY.toInt()
                accX -= dx
                accY -= dy
                if (dx != 0 || dy != 0) send(msg("pointer", "dx" to dx, "dy" to dy))
            }
            MotionEvent.ACTION_BUTTON_PRESS, MotionEvent.ACTION_BUTTON_RELEASE -> {
                val wire = when (e.actionButton) {
                    MotionEvent.BUTTON_PRIMARY -> "left"
                    MotionEvent.BUTTON_SECONDARY -> "right"
                    else -> return true
                }
                send(msg("button", "button" to wire, "down" to (e.actionMasked == MotionEvent.ACTION_BUTTON_PRESS)))
            }
            MotionEvent.ACTION_SCROLL -> {
                // One wheel notch is about 48 pixels of scrolling on the Mac. Wheel right scrolls content left.
                val dy = (e.getAxisValue(MotionEvent.AXIS_VSCROLL) * 48).toInt()
                val dx = (-e.getAxisValue(MotionEvent.AXIS_HSCROLL) * 48).toInt()
                if (dx != 0 || dy != 0) send(msg("scroll", "dx" to dx, "dy" to dy))
            }
            else -> return false
        }
        return true
    }
}

/** Shown on the session screen until the first video frame arrives. */
@Composable
private fun SessionLoader(host: String?, modifier: Modifier) {
    Column(modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        LoaderRing(Brand.Orange, Brand.Cream)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(host?.let { "Opening $it" } ?: "Opening your Mac", color = Brand.Cream, style = MaterialTheme.typography.titleMedium)
            Text("Starting the screen stream", color = Brand.Cream.copy(alpha = 0.6f), style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** The one loading mark for connecting and opening a session: the Mac tile breathes inside a thin progress ring. */
@Composable
fun LoaderRing(accent: Color, content: Color) {
    val breath by rememberInfiniteTransition(label = "loader").animateFloat(
        0.9f, 1.08f, infiniteRepeatable(tween(1200, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "breath",
    )
    Box(Modifier.size(104.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(104.dp).graphicsLayer { scaleX = breath; scaleY = breath }.background(accent.copy(alpha = 0.10f), CircleShape))
        CircularProgressIndicator(Modifier.size(84.dp), color = accent, strokeWidth = 2.dp, trackColor = content.copy(alpha = 0.08f))
        Box(Modifier.size(56.dp).background(content.copy(alpha = 0.08f), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.DesktopMac, contentDescription = null, tint = content, modifier = Modifier.size(28.dp))
        }
    }
}
