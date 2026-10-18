# Sensor sandbox

`/sandbox.html`: a 3D virtual version of the 6-FSR kit. Own entry in `vite.config.ts`; imports `core/`, `hardware/` and `view/foot.ts` read-only.

- `fsr.ts` force -> FSR resistance (power law, open under 0.1 N, saturates) -> 10k divider -> ADC (Uno 10-bit 5 V, ESP32 12-bit 3.3 V, noise). Approximate, see the doc comment. "seen" kPa goes back through `hardware/calibrate.ts`.
- `field.ts` ground-truth field from the MUN104 template and pose (arch, weight shift, roll, kg), gait timing from `core/synth.ts`, fingertip press, coverage error (relative L1 of seen vs true).
- `view.ts` three.js scene: insole heatmap, discs, wires, Nano model, foot, press marker.
- `main.ts` state, panel, input. `layout.ts` the Copy layout JSON.

Use: one question ("Can N sensors see your arch?"), one answer (match score = 100% minus coverage error, plus "They think / Real foot" verdict, orange only when they differ). Pick Flat / Typical / High arch, press Walk, drag sensors (or select, then arrows / Delete). A dismissible hint walks through: drag Inner arch, try another foot, Add sensor. The canvas toggle switches Real pressure / What sensors see. Everything else (pose sliders, press tool, board, electronics table, serial, Copy layout, Connect real kit) is under "For builders". Camera auto-fits insole + foot + board on load, resize and foot change. Styled with `../theme.css` (cursor.com tokens); the canvas reads `--bg` at runtime.

Query params: `arch=flat|normal|high|0..1`, `shift`, `roll` (-1..1), `kg`, `walk=1`, `phase=0..1` (freeze gait), `view=sensors`, `mode=press`, `press=x,y`, `pr`, `pf`, `board=esp32`, `cmap=cividis`, `foot=0`, `theme=light|dark`, `builders=1` (open panel), `hint=0..4` (4 hides).

Real kit: "Connect real kit" (Chrome/Edge) swaps the readings for the device's; sensor count is fixed at 6 then.
