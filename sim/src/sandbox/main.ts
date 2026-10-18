import "./sandbox.css"
import { colormapCss, type ColormapName } from "../core/colormap"
import { stancePose, type FootPose } from "../core/gait"
import { computeIndices } from "../core/indices"
import { edgeDistance, footOutline, inside } from "../core/outline"
import { createPressureModel, interpolate, sampleGrid, SPARSE_KERNEL, type PressureModel } from "../core/pressure"
import type { Template } from "../core/template"
import { readArch, type ArchLevel } from "../core/verdict"
import { connectSerial, isSerialSupported, SENSOR_NAMES, SENSOR_POSITIONS, type SerialSensor } from "../hardware"
import { addPress, coverageError, DEFAULT_POSE, standingField, walkingField, WALK_SECONDS, worstSpot, type Pose, type Press } from "./field"
import { BOARDS, DISC_SAMPLES, readFsr, serialText, type BoardId, type FsrReading } from "./fsr"
import { insoleBounds, layoutJson, type SensorDef } from "./layout"
import { SandboxScene, SENSOR_COLORS } from "./view"

const MAX_SENSORS = 16
const $ = <T extends Element>(sel: string) => document.querySelector<T>(sel)!

const el = {
  canvas: $<HTMLCanvasElement>("#c"),
  labels: $<HTMLElement>("#labels"),
  arch: $<HTMLInputElement>("#arch"), shift: $<HTMLInputElement>("#shift"), roll: $<HTMLInputElement>("#roll"), kg: $<HTMLInputElement>("#kg"),
  pr: $<HTMLInputElement>("#pr"), pf: $<HTMLInputElement>("#pf"),
  walk: $<HTMLInputElement>("#walk"), showFoot: $<HTMLInputElement>("#showfoot"),
  cmap: $<HTMLSelectElement>("#cmap"), board: $<HTMLSelectElement>("#board"),
  err: $<HTMLElement>("#r-err"), verdictTrue: $<HTMLElement>("#r-true"), verdictSeen: $<HTMLElement>("#r-seen"),
  tbody: $<HTMLTableSectionElement>("#tbl tbody"), serial: $<HTMLElement>("#serial"), pins: $<HTMLElement>("#pins"), status: $<HTMLElement>("#status"),
  add: $<HTMLButtonElement>("#add"), remove: $<HTMLButtonElement>("#remove"), reset: $<HTMLButtonElement>("#reset"),
  copy: $<HTMLButtonElement>("#copy"), connect: $<HTMLButtonElement>("#connect"), tare: $<HTMLButtonElement>("#tare"), camera: $<HTMLButtonElement>("#camera"),
  legendMax: $<HTMLElement>("#lg-max"), legendBar: $<HTMLElement>("#lg-bar"), len: $<HTMLElement>("#len"),
}

// ---- state -----------------------------------------------------------------------------------------------------------

const query = new URLSearchParams(location.search)
const archParam = query.get("arch")
const ARCH_WORDS: Record<string, number> = { flat: 0, normal: 0.5, high: 1 }
const num = (key: string, fallback: number) => {
  const v = Number(query.get(key))
  return query.has(key) && Number.isFinite(v) ? v : fallback
}

const state = {
  pose: {
    arch: archParam !== null && archParam in ARCH_WORDS ? ARCH_WORDS[archParam] : num("arch", DEFAULT_POSE.arch),
    shift: num("shift", DEFAULT_POSE.shift),
    roll: num("roll", DEFAULT_POSE.roll),
    kg: num("kg", DEFAULT_POSE.kg),
  } satisfies Pose,
  walk: query.get("walk") === "1",
  /** Fixed gait phase (0..1) for screenshots; null = real time. */
  walkPhase: query.has("phase") ? num("phase", 0) : null,
  showFoot: query.get("foot") !== "0",
  view: (["sensors", "seen"].includes(query.get("view") ?? "") ? "seen" : "true") as "true" | "seen",
  mode: query.get("mode") === "press" ? "press" : "orbit" as "orbit" | "press",
  pressRadius: num("pr", 8),
  pressForce: num("pf", 20),
  press: null as { x: number; y: number } | null,
  board: (query.get("board") === "esp32" ? "esp32" : "uno") as BoardId,
  cmap: (query.get("cmap") === "cividis" ? "cividis" : "viridis") as ColormapName,
  sensors: [] as SensorDef[],
  selected: null as number | null,
  live: null as SerialSensor | null,
  liveKPa: null as Float32Array | null,
}

const gainFor = (index: number) => 1 + 0.1 * Math.sin(index * 7.13 + 1.7)
const defaultSensors = (): SensorDef[] => SENSOR_POSITIONS.map((p, i) => ({ name: SENSOR_NAMES[i], x: p.x, y: p.y, gain: gainFor(i) }))
state.sensors = defaultSensors()
const pressParam = query.get("press")?.split(",").map(Number)
if (pressParam?.length === 2 && pressParam.every(Number.isFinite)) state.press = { x: pressParam[0], y: pressParam[1] }

// ---- world -----------------------------------------------------------------------------------------------------------

const outline = footOutline()
const { length: insoleLength } = insoleBounds(outline)
const template: Template = await (await fetch(`${import.meta.env.BASE_URL}data/mun104.json`)).json()
const grid = createPressureModel(SENSOR_POSITIONS, outline).grid
const size = grid.nx * grid.ny
const truth = new Float32Array(size), seen = new Float32Array(size)
const truePeak = new Float32Array(size), seenPeak = new Float32Array(size)

let stand = standingField(grid, template, state.pose)
let vmax = 100
let model: PressureModel = createPressureModel(state.sensors, outline, SPARSE_KERNEL)
let readings: FsrReading[] = []
let phase = 0

let needsCompute = true
let poseDirty = true
let layoutDirty = true
let sensorUiDirty = true
let resetPeaks = true
let dragging: "sensor" | "press" | null = null
let raf = 0
const t0 = performance.now()

function schedule(): void {
  if (!raf) raf = requestAnimationFrame(frame)
}

/** Marks inputs as changed and requests a frame. */
function invalidate(what: { pose?: boolean; layout?: boolean; ui?: boolean } = {}): void {
  needsCompute = true
  resetPeaks = true
  poseDirty ||= what.pose ?? false
  layoutDirty ||= what.layout ?? false
  sensorUiDirty ||= (what.layout ?? false) || (what.ui ?? false)
  schedule()
}

// ---- input (registered before OrbitControls so a drag on a sensor or a press can claim the pointer first) -----------------

let scene: SandboxScene
const sensorAt = (e: PointerEvent): number | null => {
  const r = el.canvas.getBoundingClientRect()
  let best: number | null = null, bestD = 18
  state.sensors.forEach((s, i) => {
    const p = scene.screenOf(scene.surfacePoint(s.x, s.y))
    if (!p) return
    const d = Math.hypot(p.x - (e.clientX - r.left), p.y - (e.clientY - r.top))
    if (d < bestD) [best, bestD] = [i, d]
  })
  return best
}

const pressing = (e: { shiftKey: boolean }) => state.mode === "press" || e.shiftKey

el.canvas.addEventListener("pointerdown", (e) => {
  if (e.button !== 0) return
  el.canvas.focus({ preventScroll: true })
  if (pressing(e)) {
    const p = scene.pickInsole(e.clientX, e.clientY)
    if (!p) return
    state.press = p
    dragging = "press"
  } else {
    const i = sensorAt(e)
    if (i === null) return
    select(i)
    dragging = "sensor"
  }
  scene.controls.enabled = false
  el.canvas.setPointerCapture(e.pointerId)
  e.stopPropagation()
  invalidate()
}, { capture: true })

el.canvas.addEventListener("pointermove", (e) => {
  if (!dragging) {
    el.canvas.style.cursor = !pressing(e) && sensorAt(e) !== null ? "pointer" : ""
    return
  }
  const p = scene.pickInsole(e.clientX, e.clientY)
  if (!p) return
  if (dragging === "press") state.press = p
  else if (state.selected !== null && inside(outline, p.x, p.y) && edgeDistance(outline, p.x, p.y) > 7) {
    Object.assign(state.sensors[state.selected], { x: p.x, y: p.y })
    invalidate({ layout: true })
    return
  }
  invalidate()
})

const endDrag = (e: PointerEvent) => {
  if (!dragging) return
  if (dragging === "press") state.press = null
  dragging = null
  scene.controls.enabled = true
  if (el.canvas.hasPointerCapture(e.pointerId)) el.canvas.releasePointerCapture(e.pointerId)
  invalidate()
}
el.canvas.addEventListener("pointerup", endDrag)
el.canvas.addEventListener("pointercancel", endDrag)

el.canvas.addEventListener("keydown", (e) => {
  const sel = state.selected
  if (sel === null) return
  const step = e.shiftKey ? 10 : 2
  const arrow: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] }
  if (e.key in arrow) {
    const s = state.sensors[sel]
    const x = s.x + arrow[e.key][0], y = s.y + arrow[e.key][1]
    if (inside(outline, x, y) && edgeDistance(outline, x, y) > 7) Object.assign(s, { x, y })
    invalidate({ layout: true })
  } else if (e.key === "Delete" || e.key === "Backspace") removeSelected()
  else if (e.key === "Escape") select(null)
  else return
  e.preventDefault()
})

scene = new SandboxScene(el.canvas, grid, outline, schedule)
new ResizeObserver(() => {
  scene.resize()
  schedule()
}).observe(el.canvas)

// ---- sensors ---------------------------------------------------------------------------------------------------------

function select(i: number | null): void {
  state.selected = i
  invalidate({ ui: true })
}

function removeSelected(): void {
  if (state.live || state.selected === null || state.sensors.length <= 1) return
  state.sensors.splice(state.selected, 1)
  state.selected = null
  invalidate({ layout: true })
}

function addSensor(): void {
  if (state.live || state.sensors.length >= MAX_SENSORS) return
  const spot = worstSpot(grid, truePeak, seenPeak, state.sensors) ?? { x: 3, y: 105 }
  state.sensors.push({ name: `S${state.sensors.length + 1}`, ...spot, gain: gainFor(state.sensors.length) })
  state.selected = state.sensors.length - 1
  invalidate({ layout: true })
}

el.add.addEventListener("click", addSensor)
el.remove.addEventListener("click", removeSelected)
el.reset.addEventListener("click", () => {
  if (state.live) return
  state.sensors = defaultSensors()
  state.selected = null
  invalidate({ layout: true })
})

// ---- panel controls --------------------------------------------------------------------------------------------------

const ARCH_WORD = ["flat", "low", "normal", "raised", "high"]
const pct = (v: number) => `${Math.round(Math.abs(v) * 100)}%`

function syncControls(): void {
  const p = state.pose
  el.arch.value = String(p.arch)
  el.shift.value = String(p.shift)
  el.roll.value = String(p.roll)
  el.kg.value = String(p.kg)
  el.pr.value = String(state.pressRadius)
  el.pf.value = String(state.pressForce)
  el.walk.checked = state.walk
  el.showFoot.checked = state.showFoot
  el.cmap.value = state.cmap
  el.board.value = state.board
  $<HTMLInputElement>(`input[name="view"][value="${state.view}"]`).checked = true
  $<HTMLInputElement>(`input[name="mode"][value="${state.mode}"]`).checked = true
  $<HTMLOutputElement>("#o-arch").value = ARCH_WORD[Math.round(p.arch * 4)]
  $<HTMLOutputElement>("#o-shift").value = Math.abs(p.shift) < 0.02 ? "even" : `${p.shift > 0 ? "toes" : "heel"} ${pct(p.shift)}`
  $<HTMLOutputElement>("#o-roll").value = Math.abs(p.roll) < 0.02 ? "neutral" : `${p.roll > 0 ? "out" : "in"} ${pct(p.roll)}`
  $<HTMLOutputElement>("#o-kg").value = `${p.kg} kg`
  $<HTMLOutputElement>("#o-pr").value = `${state.pressRadius} mm`
  $<HTMLOutputElement>("#o-pf").value = `${state.pressForce} N`
}

for (const key of ["arch", "shift", "roll", "kg"] as const)
  el[key].addEventListener("input", () => {
    state.pose[key] = Number(el[key].value)
    syncControls()
    invalidate({ pose: true })
  })
for (const key of ["pr", "pf"] as const)
  el[key].addEventListener("input", () => {
    if (key === "pr") state.pressRadius = Number(el.pr.value)
    else state.pressForce = Number(el.pf.value)
    syncControls()
    invalidate()
  })
document.querySelectorAll<HTMLButtonElement>("[data-preset]").forEach((b) =>
  b.addEventListener("click", () => {
    state.pose.arch = Number(b.dataset.preset)
    syncControls()
    invalidate({ pose: true })
  }),
)
el.walk.addEventListener("change", () => {
  state.walk = el.walk.checked
  invalidate({ pose: true })
})
el.showFoot.addEventListener("change", () => {
  state.showFoot = el.showFoot.checked
  scene.setFootVisible(state.showFoot)
  schedule()
})
document.querySelectorAll<HTMLInputElement>('input[name="view"]').forEach((r) =>
  r.addEventListener("change", () => {
    state.view = r.value === "seen" ? "seen" : "true"
    needsCompute = true
    schedule()
  }),
)
document.querySelectorAll<HTMLInputElement>('input[name="mode"]').forEach((r) =>
  r.addEventListener("change", () => {
    state.mode = r.value === "press" ? "press" : "orbit"
  }),
)
el.cmap.addEventListener("change", () => {
  state.cmap = el.cmap.value === "cividis" ? "cividis" : "viridis"
  el.legendBar.style.background = `linear-gradient(90deg, ${colormapCss(state.cmap)})`
  needsCompute = true
  schedule()
})
el.board.addEventListener("change", () => {
  state.board = el.board.value === "esp32" ? "esp32" : "uno"
  scene.setBoard(state.board === "esp32")
  invalidate({ ui: true })
})
let topView = false
el.camera.addEventListener("click", () => {
  topView = !topView
  scene.setCamera(topView ? "top" : "3d")
  el.camera.textContent = topView ? "3D view" : "Top view"
  schedule()
})
el.copy.addEventListener("click", async () => {
  const text = layoutJson(state.sensors, outline, state.board)
  try {
    await navigator.clipboard.writeText(text)
    el.status.textContent = `Copied ${state.sensors.length} sensor positions.`
  } catch {
    el.status.textContent = "Clipboard blocked by the browser."
  }
})

// Real kit over Web Serial: replaces the simulated readings with the device's.
if (isSerialSupported()) el.connect.hidden = false
el.connect.addEventListener("click", async () => {
  if (state.live) {
    await state.live.disconnect()
    state.live = state.liveKPa = null
    el.connect.textContent = "Connect real kit"
    el.tare.hidden = true
    el.status.textContent = "Disconnected."
    updateButtons()
    invalidate({ ui: true })
    return
  }
  try {
    const dev = await connectSerial("left")
    if (state.sensors.length !== dev.sensors.length) state.sensors = defaultSensors()
    state.live = dev
    state.view = "seen"
    syncControls()
    dev.onFrame((kPa) => {
      state.liveKPa = kPa.slice()
      needsCompute = true
      schedule()
    })
    el.connect.textContent = "Disconnect"
    el.tare.hidden = false
    el.status.textContent = `Connected: ${dev.name}. Tare with the foot off.`
    updateButtons()
    invalidate({ layout: true })
  } catch (err) {
    el.status.textContent = err instanceof Error ? err.message : "Could not connect."
  }
})
el.tare.addEventListener("click", () => {
  state.live?.calibrator.tare()
  el.status.textContent = "Taring, keep the foot off."
})

function updateButtons(): void {
  const n = state.sensors.length
  el.add.disabled = !!state.live || n >= MAX_SENSORS
  el.remove.disabled = !!state.live || state.selected === null || n <= 1
  el.reset.disabled = !!state.live
}

// ---- table and labels ------------------------------------------------------------------------------------------------

const colorOf = (i: number) => SENSOR_COLORS[i % SENSOR_COLORS.length]
let rowCells: HTMLElement[][] = []
let labelEls: HTMLElement[] = []
let boardLabel: HTMLElement

function rebuildSensorUi(): void {
  el.tbody.replaceChildren()
  rowCells = state.sensors.map((s, i) => {
    const tr = document.createElement("tr")
    tr.classList.toggle("sel", i === state.selected)
    const th = document.createElement("th")
    th.scope = "row"
    const b = document.createElement("button")
    b.type = "button"
    b.className = "name"
    b.setAttribute("aria-pressed", String(i === state.selected))
    b.setAttribute("aria-label", `Select sensor ${i + 1}, ${s.name}`)
    const sw = document.createElement("i")
    sw.style.background = colorOf(i)
    b.append(sw, `${i + 1} ${s.name}`)
    b.addEventListener("click", () => select(i === state.selected ? null : i))
    th.append(b)
    const cells = Array.from({ length: 5 }, () => document.createElement("td"))
    tr.append(th, ...cells)
    el.tbody.append(tr)
    return cells
  })
  el.labels.replaceChildren()
  labelEls = state.sensors.map((s, i) => {
    const d = document.createElement("div")
    d.className = "lbl" + (i === state.selected ? " sel" : "")
    const sw = document.createElement("i")
    sw.style.background = colorOf(i)
    d.append(sw, `${i + 1} ${s.name}`)
    el.labels.append(d)
    return d
  })
  boardLabel = document.createElement("div")
  boardLabel.className = "lbl"
  boardLabel.textContent = BOARDS[state.board].label
  el.labels.append(boardLabel)
  const n = state.sensors.length
  el.pins.textContent = n > 8 ? "Beyond 8 sensors you need an analog multiplexer (CD74HC4067)." : n > 6 ? "An Uno has 6 analog pins, a Nano has 8." : ""
  updateButtons()
}

function placeLabels(): void {
  const put = (d: HTMLElement, p: { x: number; y: number } | null) => {
    d.style.display = p ? "" : "none"
    if (p) d.style.transform = `translate(${p.x.toFixed(0)}px, ${p.y.toFixed(0)}px) translate(-50%, -100%)`
  }
  state.sensors.forEach((s, i) => put(labelEls[i], scene.screenOf(scene.surfacePoint(s.x, s.y, 12))))
  put(boardLabel, scene.screenOf(scene.boardAnchor()))
}

// ---- per-frame compute -----------------------------------------------------------------------------------------------

const LEVEL_TEXT: Record<ArchLevel, string> = { lower: "Lower arch", typical: "Typical", higher: "Higher arch" }
const archOf = (map: Float32Array) => {
  const idx = computeIndices(grid, map)
  return idx ? readArch(idx).level : null
}
const setText = (node: HTMLElement, text: string) => {
  if (node.textContent !== text) node.textContent = text
}

const footUrl = (arch: number) => `${import.meta.env.BASE_URL}models/foot-${arch < 0.3 ? "flatter" : arch > 0.7 ? "higher" : "typical"}.glb`
let footKey = ""

function staticPose(p: Pose): FootPose {
  return { pitch: -0.1 * p.shift, pivotY: p.shift > 0 ? 185 : 0, lift: 0 }
}

function compute(now: number): void {
  const pose = state.pose
  if (poseDirty) {
    stand = standingField(grid, template, pose)
    vmax = Math.ceil((Math.max(...stand) * 1.3) / 10) * 10
    setText(el.legendMax, `${vmax} kPa`)
    poseDirty = false
  }
  if (layoutDirty) {
    model = createPressureModel(state.sensors, outline, SPARSE_KERNEL)
    layoutDirty = false
  }
  if (state.walk) {
    phase = state.walkPhase ?? ((now - t0) / 1000 / WALK_SECONDS) % 1
    walkingField(grid, stand, phase, truth)
  } else truth.set(stand)
  const press: Press | null = state.press ? { ...state.press, radius: state.pressRadius, newtons: state.pressForce } : null
  if (press) addPress(grid, truth, press)

  // Sensors: true pressure on each active area -> FSR -> divider -> ADC -> app's kPa estimate.
  const board = BOARDS[state.board]
  readings = state.sensors.map((s) => {
    let sum = 0
    for (const [dx, dy] of DISC_SAMPLES) sum += sampleGrid(grid, truth, s.x + dx, s.y + dy)
    return readFsr(sum / DISC_SAMPLES.length, s.gain, board)
  })
  const est = state.live?.sensors.length === readings.length && state.liveKPa ? state.liveKPa : Float32Array.from(readings, (r) => r.seenKPa)
  interpolate(model, est, 0, seen)

  // Over a walk, verdicts and error use the per-cell peak over the cycle (as the app does for a whole stance).
  if (resetPeaks) {
    truePeak.fill(0)
    seenPeak.fill(0)
    resetPeaks = false
  }
  if (state.walk)
    for (let c = 0; c < size; c++) {
      truePeak[c] = Math.max(truePeak[c], truth[c])
      seenPeak[c] = Math.max(seenPeak[c], seen[c])
    }
  else {
    truePeak.set(truth)
    seenPeak.set(seen)
  }

  const err = coverageError(grid, truePeak, seenPeak)
  const aTrue = archOf(truePeak), aSeen = archOf(seenPeak)
  setText(el.err, state.live || Number.isNaN(err) ? "n/a" : `${Math.round(err * 100)}%`)
  setText(el.verdictTrue, aTrue ? LEVEL_TEXT[aTrue] : "No reading")
  setText(el.verdictSeen, (aSeen ? LEVEL_TEXT[aSeen] : "No reading") + (aTrue !== aSeen ? " (differs)" : ""))

  if (sensorUiDirty) {
    rebuildSensorUi()
    scene.setSensors(state.sensors.map((s, i) => ({ x: s.x, y: s.y, color: colorOf(i) })), state.selected)
    sensorUiDirty = false
  }
  readings.forEach((r, i) => {
    const c = rowCells[i]
    if (!c) return
    if (state.live) [c[0].textContent, c[1].textContent, c[2].textContent, c[3].textContent] = ["-", "-", "-", "-"]
    else {
      setText(c[0], r.kPa.toFixed(0))
      setText(c[1], r.ohms >= 10e6 ? "open" : (r.ohms / 1000).toFixed(1))
      setText(c[2], r.volts.toFixed(2))
      setText(c[3], String(r.adc))
    }
    setText(c[4], est[i].toFixed(0))
  })
  setText(
    el.serial,
    state.live ? `live from ${state.live.name}\nP,${Array.from(state.liveKPa ?? [], (v) => v.toFixed(0)).join(",")} (kPa)` : serialText(board, readings.map((r) => r.adc)),
  )

  scene.paint(grid, state.view === "true" ? truth : seen, vmax, state.cmap)
  scene.setPress(press)
  const pose3d = state.walk ? stancePose(phase) : staticPose(pose)
  scene.poseFoot(pose3d, pose.roll)
  const key = footUrl(pose.arch)
  if (key !== footKey) {
    footKey = key
    scene.setFoot(key).then(schedule, () => (el.status.textContent = "Foot model failed to load."))
  }
  needsCompute = false
}

function frame(now: number): void {
  raf = 0
  if (needsCompute || state.walk) compute(now)
  const moving = scene.render()
  placeLabels()
  if (moving || state.walk) schedule()
}

// ---- go --------------------------------------------------------------------------------------------------------------

el.len.textContent = String(Math.round(insoleLength))
el.legendBar.style.background = `linear-gradient(90deg, ${colormapCss(state.cmap)})`
scene.setBoard(state.board === "esp32")
scene.setFootVisible(state.showFoot)
syncControls()
scene.resize()
schedule()
