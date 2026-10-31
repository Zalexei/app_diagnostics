package io.github.zalexei.android_diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class ApiLevelsTest {
    @Test
    fun triggersOfAndroid16NeedApi36() {
        assertFalse(ApiLevels.isTriggerSupported(2, 3_500_000))
        assertTrue(ApiLevels.isTriggerSupported(1, 3_600_000))
        assertTrue(ApiLevels.isTriggerSupported(2, 3_600_000))
    }

    @Test
    fun killTriggersNeedAndroid16Qpr2() {
        assertFalse(ApiLevels.isTriggerSupported(4, 3_600_000))
        assertTrue(ApiLevels.isTriggerSupported(4, 3_600_001))
        assertTrue(ApiLevels.isTriggerSupported(3, 3_700_000))
    }

    @Test
    fun oomAndNewerTriggersNeedApi37() {
        for (type in 7..11) {
            assertFalse(ApiLevels.isTriggerSupported(type, 3_600_001))
            assertTrue(ApiLevels.isTriggerSupported(type, 3_700_000))
        }
    }

    @Test
    fun unknownTriggersAreNeverRegistered() {
        assertNull(ApiLevels.triggerMinSdkFull(0))
        assertNull(ApiLevels.triggerMinSdkFull(99))
        assertFalse(ApiLevels.isTriggerSupported(99, 9_900_000))
        assertEquals(3_600_001, ApiLevels.triggerMinSdkFull(6))
    }
}
