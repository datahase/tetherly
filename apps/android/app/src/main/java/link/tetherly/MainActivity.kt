package link.tetherly

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material.icons.outlined.VpnLock
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.AlertDialog
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) openLink(intent)
        setContent {
            TetherlyTheme {
                vm.pendingLink?.let { link ->
                    PairLinkSheet(
                        link = link,
                        onPair = { vm.pendingLink = null; vm.session.pairFromLink(link) },
                        onCancel = { vm.pendingLink = null },
                    )
                }
                when (val state = vm.session.state.collectAsState().value) {
                    is SessionState.Pairing -> PairingScreen(vm.session, state)
                    is SessionState.Connected, is SessionState.Reconnecting -> SessionScreen(vm, state)
                    is SessionState.Connecting -> ConnectingScreen(vm.session, state)
                    else -> HomeScreen(vm, state, ::scanQr)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openLink(intent)
    }

    /** Links can come from any app or web page, so they only propose a pairing; the user must confirm it. */
    private fun openLink(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val link = PairLink.parse(intent.dataString ?: return)
        if (link == null) vm.session.showNotice("That isn't a valid Tetherly pairing code.") else vm.pendingLink = link
    }

    private fun pairWith(text: String) {
        val link = PairLink.parse(text)
        if (link == null) vm.session.showNotice("That isn't a valid Tetherly pairing code.") else vm.session.pairFromLink(link)
    }

    /** Google code scanner: Play services shows the camera UI, so this app needs no CAMERA permission. */
    private fun scanQr() {
        fun unavailable() = vm.session.showNotice("The QR scanner isn't available. Pair by address instead.")
        try {
            val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
            GmsBarcodeScanning.getClient(this, options).startScan()
                .addOnSuccessListener { code -> code.rawValue?.let(::pairWith) }
                .addOnFailureListener { unavailable() }
        } catch (_: RuntimeException) {
            // SDK initialization can fail synchronously, before it returns a Task.
            unavailable()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(vm: MainViewModel, state: SessionState, onScan: () -> Unit) {
    val session = vm.session
    val macs by session.macs.collectAsState()
    val notice by session.notice.collectAsState()
    val busy = state is SessionState.Connecting
    // A paired Mac seen on the network is shown once, as a paired Mac, and connects via its fresh address.
    val pairedNames = macs.map { it.hostName }.toSet()
    val nearby = vm.devices.filter { it !in pairedNames }
    var moreOpen by rememberSaveable { mutableStateOf(false) }

    fun connect(mac: PairedMac) = vm.connectBest(mac)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        BrandMark(30)
                        Text("Tetherly", fontWeight = FontWeight.SemiBold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
      PullToRefreshBox(isRefreshing = vm.refreshing, onRefresh = vm::refresh, modifier = Modifier.fillMaxSize().padding(padding)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            StatusCard(state, notice, onCancel = session::disconnect, onDismiss = session::dismissNotice)
            ReleaseNotes()

            val primary = macs.firstOrNull()
            if (primary == null) {
                WelcomeCard(busy, onScan)
            } else {
                MacHero(
                    mac = primary, reach = vm.reachOf(primary),
                    connecting = vm.resolving == primary.hostName,
                    enabled = !busy, onConnect = { connect(primary) }, onForget = { session.forget(primary.pin) },
                )
                if (macs.size > 1) {
                    Section("Other Macs") {
                        macs.drop(1).forEach { mac ->
                            val r = vm.reachOf(mac)
                            MacRow(
                                icon = Icons.Outlined.Laptop, title = mac.hostName,
                                subtitle = reachLabel(r, mac), monoSubtitle = r == MainViewModel.Reach.Offline,
                                busy = vm.resolving == mac.hostName, primary = "Connect", primaryEnabled = !busy, onPrimary = { connect(mac) },
                                menu = listOf("Forget this Mac" to { session.forget(mac.pin) }),
                            )
                        }
                    }
                }
                OutlinedButton(
                    onClick = onScan, enabled = !busy, shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Icon(Icons.Outlined.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.size(10.dp))
                    Text("Pair another Mac")
                }
            }

            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
                Column {
                    Row(
                        Modifier.fillMaxWidth().clickable { moreOpen = !moreOpen }.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Other ways to connect", style = MaterialTheme.typography.titleSmall)
                            Text(
                                if (nearby.isEmpty()) "Enter an address or a Tailscale name" else "${nearby.size} nearby, or enter an address",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Icon(if (moreOpen) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, contentDescription = if (moreOpen) "Collapse" else "Expand")
                    }
                    AnimatedVisibility(moreOpen) {
                        Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            val showNearby = vm.discovery == MainViewModel.Discovery.Failed || vm.devices.isEmpty() || nearby.isNotEmpty()
                            if (showNearby) Text("Nearby", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (showNearby) when {
                                vm.discovery == MainViewModel.Discovery.Failed -> Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(vm.discoveryError ?: "Can't search this network.", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                                    TextButton(onClick = vm::startDiscovery) { Text("Try again") }
                                }
                                vm.devices.isEmpty() -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("Looking for Macs on this Wi-Fi", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    LinearProgressIndicator(Modifier.fillMaxWidth())
                                }
                                else -> nearby.forEach { name ->
                                    MacRow(
                                        icon = Icons.Outlined.Lan, title = name,
                                        subtitle = if (vm.resolving == name) "Finding address" else "On this network",
                                        busy = vm.resolving == name, primary = "Pair", primaryEnabled = !busy,
                                        onPrimary = { vm.connectDiscovered(name, pair = true) },
                                        menu = listOf("Connect without pairing" to { vm.connectDiscovered(name, pair = false) }),
                                    )
                                }
                            }
                            AddressForm(busy, session)
                        }
                    }
                }
            }
            Text(
                if (vm.tailscaleOn) "Tailscale is on. Pull down to search again." else "Pull down to search again.",
                Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(12.dp))
        }
      }
    }
}

private fun reachLabel(r: MainViewModel.Reach, mac: PairedMac) = when (r) {
    MainViewModel.Reach.Wifi -> "Available on Wi-Fi"
    MainViewModel.Reach.Tailscale -> "Available via Tailscale"
    MainViewModel.Reach.Offline -> "Not reachable. Last seen at ${mac.address}"
}

/** The main paired Mac, with the one action people come here for. */
@Composable
private fun MacHero(mac: PairedMac, reach: MainViewModel.Reach, connecting: Boolean, enabled: Boolean, onConnect: () -> Unit, onForget: () -> Unit) {
    val onNetwork = reach != MainViewModel.Reach.Offline
    var menu by remember { mutableStateOf(false) }
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Box(Modifier.size(56.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Laptop, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(30.dp))
                }
                Column(Modifier.weight(1f).padding(start = 14.dp)) {
                    Text(mac.hostName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        // A real state indicator: green only when the Mac is advertising on this network right now.
                        Box(Modifier.size(8.dp).clip(RoundedCornerShape(4.dp)).background(if (onNetwork) Color(0xFF3FB950) else MaterialTheme.colorScheme.outline))
                        Spacer(Modifier.size(8.dp))
                        Icon(
                            if (reach == MainViewModel.Reach.Tailscale) Icons.Outlined.VpnLock else Icons.Outlined.Wifi,
                            contentDescription = null, modifier = Modifier.size(16.dp).padding(end = 2.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.size(4.dp))
                        Text(
                            reachLabel(reach, mac),
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, contentDescription = "More options for ${mac.hostName}") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Forget this Mac") }, onClick = { menu = false; onForget() })
                    }
                }
            }
            Button(onClick = onConnect, enabled = enabled, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text(if (connecting) "Finding your Mac" else "Connect", style = MaterialTheme.typography.titleSmall)
            }
        }
    }
}

/**
 * Connecting (or starting a pairing) gets one calm full screen: the Mac's name and route rather than its IP, the
 * same ring the session shows while its video starts, and a way out.
 */
@Composable
private fun ConnectingScreen(session: SessionController, state: SessionState.Connecting) {
    val macs by session.macs.collectAsState()
    val host = state.address.host
    val name = macs.firstOrNull { m -> HostAddress.parse(m.address)?.host == host || m.routes.any { it.ip == host } }?.hostName
    val tailscale = isTailscaleHost(host)
    BackHandler { session.disconnect() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            LoaderRing(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(28.dp))
            Text(
                (if (state.pairing) "Pairing with " else "Connecting to ") + (name ?: host),
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(12.dp))
            Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (tailscale) Icons.Outlined.VpnLock else Icons.Outlined.Wifi, contentDescription = null,
                        modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.size(6.dp))
                    Text(
                        if (tailscale) "Over Tailscale" else "Over Wi-Fi",
                        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Text(
                if (state.pairing) "Setting up a secure pairing" else "Securing the connection",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            OutlinedButton(
                onClick = session::disconnect, shape = RoundedCornerShape(12.dp),
                modifier = Modifier.widthIn(max = 360.dp).fillMaxWidth().height(52.dp),
            ) { Text("Cancel", style = MaterialTheme.typography.titleSmall) }
        }
    }
}

/** First run: what to do on the Mac, then one clear action here. */
@Composable
private fun WelcomeCard(busy: Boolean, onScan: () -> Unit) {
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            BrandMark(52)
            Text("Control your Mac from this phone", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
            listOf(
                Icons.Outlined.Laptop to "Open Tetherly on your Mac",
                Icons.Outlined.QrCode to "Click Pair New Device",
                Icons.Outlined.QrCodeScanner to "Scan the code and compare the numbers",
            ).forEach { (icon, text) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.size(12.dp))
                    Text(text, style = MaterialTheme.typography.bodyLarge)
                }
            }
            Button(onClick = onScan, enabled = !busy, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Icon(Icons.Outlined.QrCodeScanner, contentDescription = null)
                Spacer(Modifier.size(10.dp))
                Text("Scan QR to pair", style = MaterialTheme.typography.titleSmall)
            }
        }
    }
}

/** Confirms a pairing link that arrived from outside the app before anything connects. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PairLinkSheet(link: PairLink, onPair: () -> Unit, onCancel: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onCancel,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                BrandMark(48)
                Column {
                    Text("Pair with this Mac?", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        link.name.ifBlank { "Unnamed Mac" }, style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Address", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    link.addresses.forEach { Text(it.toString(), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyLarge) }
                }
            }
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.Shield, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                    Text(
                        "This link was opened from another app. Continue only if you just scanned it from Tetherly on your own Mac. You will still compare a code on both screens.",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
            Button(onClick = onPair, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("Pair", style = MaterialTheme.typography.titleSmall)
            }
            OutlinedButton(onClick = onCancel, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("Cancel", style = MaterialTheme.typography.titleSmall)
            }
        }
    }
}

@Composable
private fun BrandMark(sizeDp: Int) {
    Box(Modifier.size(sizeDp.dp).clip(RoundedCornerShape(8.dp)).background(Brand.Ink), contentAlignment = Alignment.Center) {
        Image(painterResource(R.mipmap.ic_launcher_foreground), contentDescription = null, modifier = Modifier.size((sizeDp * 1.6).dp))
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

@Composable
private fun StatusCard(state: SessionState, notice: String?, onCancel: () -> Unit, onDismiss: () -> Unit) {
    when {
        state is SessionState.Failed || notice != null -> {
            val text = (state as? SessionState.Failed)?.message ?: notice!!
            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.errorContainer) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
                    Spacer(Modifier.size(12.dp))
                    Text(text, Modifier.weight(1f), color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodyMedium)
                    if (notice != null) TextButton(onClick = onDismiss) { Text("Dismiss") }
                }
            }
        }
    }
}

@Composable
private fun MacRow(
    icon: ImageVector, title: String, subtitle: String, monoSubtitle: Boolean = false, busy: Boolean = false,
    primary: String, primaryEnabled: Boolean, onPrimary: () -> Unit, menu: List<Pair<String, () -> Unit>>,
) {
    var open by remember { mutableStateOf(false) }
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column {
            Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 4.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                    Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                }
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontFamily = if (monoSubtitle) FontFamily.Monospace else null, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                FilledTonalButton(onClick = onPrimary, enabled = primaryEnabled, shape = RoundedCornerShape(12.dp)) { Text(primary) }
                Box {
                    IconButton(onClick = { open = true }) { Icon(Icons.Outlined.MoreVert, contentDescription = "More options for $title") }
                    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                        menu.forEach { (label, action) -> DropdownMenuItem(text = { Text(label) }, onClick = { open = false; action() }) }
                    }
                }
            }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun EmptyState(icon: ImageVector, title: String, body: String, searching: Boolean = false, action: Pair<String, () -> Unit>? = null) {
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.size(12.dp))
                Text(title, style = MaterialTheme.typography.titleSmall)
            }
            Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (searching) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 6.dp))
            action?.let { (label, run) -> TextButton(onClick = run) { Text(label) } }
        }
    }
}

@Composable
private fun AddressForm(busy: Boolean, session: SessionController) {
    var address by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    fun go(pair: Boolean) {
        if (HostAddress.parse(address) == null) {
            error = if (address.isBlank()) "Enter your Mac's address first." else "Use an IP address, hostname or Tailscale name, optionally with :port."
            return
        }
        error = null
        session.connect(address, pair = pair)
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        OutlinedTextField(
            value = address,
            onValueChange = { address = it; error = null },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Mac address") },
            placeholder = { Text("192.168.1.20") },
            supportingText = { Text(error ?: "Works on Wi-Fi and over Tailscale.") },
            isError = error != null,
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = { go(pair = false) }),
        )
        // Both actions stay enabled and validate on press, so the form never shows dead grey buttons.
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = { go(pair = false) }, enabled = !busy, shape = RoundedCornerShape(12.dp),
                modifier = Modifier.weight(1f).height(48.dp),
            ) {
                Text("Connect")
                Spacer(Modifier.size(8.dp))
                Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null, modifier = Modifier.size(18.dp))
            }
            FilledTonalButton(
                onClick = { go(pair = true) }, enabled = !busy, shape = RoundedCornerShape(12.dp),
                modifier = Modifier.weight(1f).height(48.dp),
            ) {
                Icon(Icons.Outlined.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text("Pair")
            }
        }
    }
}

@Composable
private fun PairingScreen(session: SessionController, state: SessionState.Pairing) {
    BackHandler { session.cancelPairing() }
    Scaffold { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BrandMark(56)
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Pair with ${state.host}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                Text(
                    when {
                        state.sas == null -> "Setting up a secure connection"
                        !state.confirmed -> "Check that your Mac shows exactly this code."
                        state.macApproved -> "Your Mac approved. Finishing."
                        else -> "Now click Allow on your Mac."
                    },
                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            val sas = state.sas
            if (sas == null) {
                LinearProgressIndicator(Modifier.widthIn(max = 280.dp).fillMaxWidth())
            } else {
                Row(
                    Modifier.semantics { contentDescription = "Pairing code ${sas.joinToString(" ")}" },
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    sas.forEach {
                        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                            Text(
                                "$it", Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                                fontFamily = FontFamily.Monospace, fontSize = 30.sp, fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                }
            }
            if (sas != null && !state.confirmed) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = session::confirmPairing, shape = RoundedCornerShape(12.dp), modifier = Modifier.widthIn(min = 220.dp).height(48.dp)) { Text("Codes match") }
                    TextButton(onClick = session::cancelPairing) { Text("Cancel") }
                }
                Text(
                    "If the codes differ, cancel. Someone may be trying to intercept the connection.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                if (sas != null) LinearProgressIndicator(Modifier.widthIn(max = 280.dp).fillMaxWidth())
                TextButton(onClick = session::cancelPairing) { Text("Cancel") }
            }
        }
    }
}

@Composable
private fun ReleaseNotes() {
    val releaseNotesText = "- Initial public release.\n- Pair your phone with your Mac and control its desktop.\n- Transfer files and clipboard content between paired devices." // RELEASE_NOTES_TEXT
    val context = LocalContext.current
    val info = remember(context) { context.packageManager.getPackageInfo(context.packageName, 0) }
    var open by rememberSaveable { mutableStateOf(false) }
    TextButton(onClick = { open = true }) { Text("Version ${info.versionName} (${info.longVersionCode}) · Changelog") }
    if (open) AlertDialog(
        onDismissRequest = { open = false },
        title = { Text("Changelog · ${info.versionName}") },
        text = { Text(releaseNotesText) },
        confirmButton = { TextButton(onClick = { open = false }) { Text("Done") } },
        dismissButton = { TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://www.tetherly.link/changelog"))) }) { Text("Full changelog") } },
    )
}
