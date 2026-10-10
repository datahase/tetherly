package link.tetherly

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Brand tokens sampled from the logo. Orange is the only accent; ink text on orange keeps contrast near 6:1. */
object Brand {
    val Orange = Color(0xFFFD6B0B)
    val OrangeOnLight = Color(0xFFC2510A) // AA-contrast orange for text and icons on light surfaces
    val Ink = Color(0xFF1C1814)
    val Cream = Color(0xFFF7EEDB)
}

private val Dark = darkColorScheme(
    primary = Brand.Orange, onPrimary = Brand.Ink,
    primaryContainer = Color(0xFF4A2A14), onPrimaryContainer = Color(0xFFFFDCC7),
    secondary = Brand.Cream, onSecondary = Brand.Ink,
    secondaryContainer = Color(0xFF3A332C), onSecondaryContainer = Brand.Cream,
    tertiary = Brand.Orange, onTertiary = Brand.Ink,
    background = Brand.Ink, onBackground = Brand.Cream,
    surface = Color(0xFF211D19), onSurface = Brand.Cream,
    surfaceVariant = Color(0xFF2E2924), onSurfaceVariant = Color(0xFFCFC5B4),
    surfaceTint = Color.Transparent,
    surfaceContainerLowest = Color(0xFF171310), surfaceContainerLow = Color(0xFF221E1A),
    surfaceContainer = Color(0xFF27221E), surfaceContainerHigh = Color(0xFF2E2924), surfaceContainerHighest = Color(0xFF38322C),
    outline = Color(0xFF7A6F62), outlineVariant = Color(0xFF3D3731),
    error = Color(0xFFFF8A80), onError = Brand.Ink, errorContainer = Color(0xFF4D1F1C), onErrorContainer = Color(0xFFFFDAD6),
    inverseSurface = Brand.Cream, inverseOnSurface = Brand.Ink, inversePrimary = Brand.OrangeOnLight,
    scrim = Color(0xFF0F0C0A),
)

private val Light = lightColorScheme(
    primary = Brand.OrangeOnLight, onPrimary = Color(0xFFFFFDF8),
    primaryContainer = Color(0xFFFFDCC7), onPrimaryContainer = Color(0xFF3A1A05),
    secondary = Color(0xFF5C5348), onSecondary = Color(0xFFFFFDF8),
    secondaryContainer = Color(0xFFF1EADC), onSecondaryContainer = Brand.Ink,
    tertiary = Brand.OrangeOnLight, onTertiary = Color(0xFFFFFDF8),
    background = Color(0xFFFBF7EE), onBackground = Brand.Ink,
    surface = Color(0xFFFBF7EE), onSurface = Brand.Ink,
    surfaceVariant = Color(0xFFF1EADC), onSurfaceVariant = Color(0xFF5C5348),
    surfaceTint = Color.Transparent,
    surfaceContainerLowest = Color(0xFFFFFDF8), surfaceContainerLow = Color(0xFFF8F3E8),
    surfaceContainer = Color(0xFFF4EEE2), surfaceContainerHigh = Color(0xFFEFE8DA), surfaceContainerHighest = Color(0xFFE9E1D1),
    outline = Color(0xFF8A7F70), outlineVariant = Color(0xFFE2D9C7),
    error = Color(0xFFB3261E), onError = Color(0xFFFFFDF8), errorContainer = Color(0xFFF9DEDC), onErrorContainer = Color(0xFF410E0B),
    inverseSurface = Brand.Ink, inverseOnSurface = Brand.Cream, inversePrimary = Brand.Orange,
    scrim = Color(0xFF0F0C0A),
)

@Composable
fun TetherlyTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)
}
