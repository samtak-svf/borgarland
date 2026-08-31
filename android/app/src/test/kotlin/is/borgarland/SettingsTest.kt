package `is`.borgarland

import `is`.borgarland.data.Settings
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The device's preferences, kept in `filesDir` like the address (#179).
 *
 * The default is the decision: save to the gallery unless the person says
 * otherwise. A missing file reads as the default, never as "off" — the app was
 * installed moments ago and the person has not said anything yet.
 */
class SettingsTest {

    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun theDefaultIsToSaveToTheGallery() {
        val dir = folder.newFolder()
        assertTrue(Settings.saveToGallery(dir))
    }

    @Test
    fun anUnreadableFileReadsAsTheDefault() {
        val dir = folder.newFolder()
        File(dir, "settings.json").writeText("{ not json")
        assertTrue(Settings.saveToGallery(dir))
    }

    @Test
    fun theSettingSurvivesTheRoundTrip() {
        val dir = folder.newFolder()
        assertTrue(Settings.setSaveToGallery(dir, false))
        assertFalse(Settings.saveToGallery(dir))
        assertTrue(Settings.setSaveToGallery(dir, true))
        assertTrue(Settings.saveToGallery(dir))
    }

    @Test
    fun aMissingKeyReadsAsTheDefault() {
        val dir = folder.newFolder()
        File(dir, "settings.json").writeText("{}")
        assertTrue(Settings.saveToGallery(dir))
    }
}
