# Sensor sandbox

`/sandbox.html`: a 3D virtual version of the 6-FSR kit. Own entry in `vite.config.ts`; imports `core/`, `hardware/` and `view/foot.ts` read-only.

- `fsr.ts` force -> FSR resistance (power law, open under 0.1 N, saturates) -> 10k divider -> ADC (Uno 10-bit 5 V, ESP32 12-bit 3.3 V, noise). Approximate, see the doc comment. "seen" kPa goes back through `hardware/calibrate.ts`.
- `field.ts` ground-truth field from the MUN104 template and pose (arch, weight shift, roll, kg), gait timing from `core/synth.ts`, fingertip press, coverage error (relative L1 of seen vs true).
- `view.ts` three.js scene: insole heatmap, discs, wires, Nano model, foot, press marker.
- `main.ts` state, panel, input. `layout.ts` the Copy layout JSON.

Use: drag sensors (or select, then arrows / Delete); Add puts a sensor where the error is largest; Shift-drag or Press mode pushes the insole; toggle True pressure vs What the sensors see. Walk uses peaks over the cycle for error and verdicts.

Query params: `arch=flat|normal|high|0..1`, `shift`, `roll` (-1..1), `kg`, `walk=1`, `phase=0..1` (freeze gait), `view=sensors`, `mode=press`, `press=x,y`, `pr`, `pf`, `board=esp32`, `cmap=cividis`, `foot=0`.

Real kit: "Connect real kit" (Chrome/Edge) swaps the readings for the device's; sensor count is fixed at 6 then.
