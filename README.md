# Qring_flutter



## SUNDR Release Notes 
**Date:** 2026-08-08
`<Sundr-Aug08-R1>`
*Progress against Meditation Mode, Prayer History, Vitals Trends & Alarms UI*

---

* **Meditation & Prayer Sessions:** Direct navigation to session screens; automatic restoration of system "Do Not Disturb" upon completion.
* **Data Persistence:** Resolved database schema inconsistencies for reliable offline/online session history sync. Added actionable empty-state prompts.
* **Vitals Visualization:** Upgraded calmness and heart rate charts to feature dynamic Y-axis scaling, cubic spline curves, and ambient glow effects.
* **UI Refinements:** Expanded the "serenity circle" badge to prevent text truncation and aligned Alarms screen styling with core design tokens.

**Date:** 2026-08-09
`<Sundr-Aug09-R1>`
*FSR pipeline updated and crash fixes enabled*
 
 ---

 * **FSR:** Upgraded the entire fall prediction pipeline to V2 from V1 and made several improvements to its flow
 * **Stability & Bug Fixes:** Resolved unexpected app crashes on Android when connecting the ring or starting a workout in the background. Added missing permissions to ensure seamless background data synchronization.
