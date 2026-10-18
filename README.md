# archy

Check your arch. Print your insole. DubHacks '26.

| Path | What |
| --- | --- |
| `ios/` | The archy iPhone app: onboarding, LiDAR foot scan, hand measurements, insole design, foot training. |
| `sim/` | The web demo at https://tryarchy.vercel.app: pressure sensors to heatmap to arch result to printable insole. |
| `hardware/` | 6-sensor DIY pressure insole and firmware. |
| `datasets/` | Open foot-pressure and foot-scan datasets, fetch and analysis scripts. |
| `services/voice/` | Optional narration proxy for the app's read-aloud. |
| `docs/` | Research notes and the agent workflow. |

The iOS scan exports an STL; it is not wired into the web demo yet (the web demo accepts an STL upload).
