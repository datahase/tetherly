package link.tetherly

import java.io.File

/** protocol/fixtures, passed in by app/build.gradle.kts. */
fun fixture(name: String): String = File(System.getProperty("fixtures") ?: error("fixtures system property not set"), name).readText()
