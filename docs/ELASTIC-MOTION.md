# Elastic selection and motion

Native motion based on [Flowing: Adding fidelity to a toggle](https://flowing-v4.vercel.app/components/elastic-toggles-1/article) and the accompanying prompt supplied by Vitor. No new dependency.

Install cards and Uninstall rows use the same 38 × 22 switch visual, with a 14-unit knob, 4-unit inset and 16-unit travel. The existing CheckBox owns the whole click target, keyboard interaction, bindings and UI Automation Toggle pattern. Toggling changes the selection immediately; installation/removal still requires review. Details remains a separate button. Consent and leftover checkboxes retain their existing meaning and appearance.

`ElasticSwitch` in `src/motion.cs` builds the capsule from two circles and a rectangular bridge. Only the bridge scales horizontally. The whole knob can squash vertically. The field, 26% ink fill, two knob colours and final 1-unit ring use existing theme resources. Selection and colour layers fade over 180 ms.

Each flight samples a damped spring into 41 linear keyframes for native WPF animation clocks. Stretch follows speed; a smooth remaining-distance limit softens calm landings. Bounce is reduced before playback to fit both horizontal edges inside the ring. A reversed, already stretched shape can also reduce new stretch to fit its remaining space. Height rebound retains the original bounce. Rounded clipping is a final safety net. Reversals read the currently animated transforms, including inputs before the next WPF clock tick.

| Preset | Stretch | Squash | Bounce | Duration |
| --- | --- | --- | --- | --- |
| Balanced (default) | 0.2 | 0.1 | 0.3 | 720 ms |
| Firm | 0 | 0 | 0 | 220 ms |
| Elastic | 1 | 0.22 | 0.8 | 1100 ms |

The component exposes `Feel`, `PressFeedback` (true), `PressAmount` (0–1, default 0.83), `Changed` and `Settled`. Native `IsPressed` supplies the 150 ms anticipation and cancellation for mouse/keyboard. `Changed` runs with the selection change; expensive additional work belongs in `Settled`. Superseded or unloaded flights discard their completion callback. Reduced motion settles immediately, including a live change to Windows animation/high-contrast preferences.

Button release now uses a continuous sampled spring. Expander layout commits once and the revealed content moves/fades; height is no longer animated. Existing themes, glass, selection flights and result feedback remain.

This is a native adaptation: WPF clocks replace Web Animations API, and UIA replaces ARIA. All transform/opacity keyframes are submitted together without timers or completion-driven animation phases. This does not guarantee that WPF behaves identically to a browser compositor under every GPU/dispatcher workload.

## Check locally

```powershell
.\build-windows.ps1
powershell -NoProfile -STA -File tests/elastic-motion.ps1
powershell -NoProfile -STA -File tests/smoke.ps1
.\dist\1nstall.exe --manager-test
```

The focused test covers all presets, bounds, successive interruptions, UIA state, live reversal, press cancellation, reduced motion, completion callbacks and template recycling. Existing smoke/manager checks cover selection, layout, bindings and app workflows with fictional data. `tests/screenshots.ps1` captures themes; `tests/scrolling.ps1` checks scrolling and navigation.
