# Combat one-shots

These original PCM effects were authored for the combat arena. They inherit the
repository license and contain no third-party samples. Files use mono 16-bit
PCM at 24 kHz. The peak sample magnitude is at most 10,242 / 32,768; playback
uses -18 dB per voice and at most eight voices.

| Cue | Start/end frequency (Hz) | Duration (s) |
| --- | --- | --- |
| Arc Bolt | 900 / 300 | 0.13 |
| Chain Lightning | 1500 / 500 | 0.22 |
| Thunder Nova | 170 / 50 | 0.35 |
| Static Ward | 420 / 840 | 0.35 |
| Storm Totem | 220 / 660 | 0.30 |
| Tempest Dash | 1100 / 150 | 0.18 |
| Hit | 180 / 70 | 0.08 |
| Critical | 1200 / 1800 | 0.16 |
| Shock | 1800 / 400 | 0.12 |
| Death | 180 / 35 | 0.30 |
| Elite warning | 250 / 450 | 0.55 |
| Protected | 600 / 1000 | 0.09 |
| Player hurt | 100 / 45 | 0.18 |

The offline authoring recipe integrates the linearly swept frequency into a
phase at 24 kHz. Each sample is `0.28 * min(t / 0.008, 1) * (1 - t / duration)^2
* (sin(phase) + 0.25 * sin(phase * 2.01))`, then scales to signed 16-bit PCM.
The short attack and decaying envelope avoid discontinuities at either end.
No generator or runtime audio synthesis framework is required.
