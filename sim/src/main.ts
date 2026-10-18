import "./style.css"
import { colormapCss, type ColormapName } from "./core/colormap"
import { FLAT_POSE, poseFromCop, stancePose, type FootPose } from "./core/gait"
import { computeIndices, type Indices } from "./core/indices"
import { buildInsole, DEFAULT_INSOLE, type InsoleMesh } from "./core/insole"
import { StepTracker, copY } from "./core/live"
import { footOutline } from "./core/outline"
import { copTrajectory, createPressureModel, frameMaps, interpolate, peakMap, sampleGrid, SPARSE_KERNEL, type Grid, type PressureModel } from "./core/pressure"
import { toBinaryStl } from "./core/stl"
import { synthTrial } from "./core/synth"
import { differenceMap, templateOnGrid } from "./core/template"
import type { FootType, Trial } from "./core/types"
import { DISCLAIMER, readArch } from "./core/verdict"
import { loadCadwalk, loadFeet, loadInsoleData, loadTemplate, type CadStep } from "./data"
import { connectDemoDevice, connectSerial, isSerialSupported, SENSOR_POSITIONS } from "./hardware"
import type { LiveSensor } from "./hardware/types"
import { InsoleScene } from "./view/scene"

/** Element lookup that degrades instead of throwing: a missing id logs a warning and returns a detached stand-in. */
const $ = <T extends HTMLElement>(id: string): T => {
  const found = document.getElementById(id)
  if (found) return found as T
  console.warn(`missing element #${id}`)
  return document.createElement("div") as unknown as T
}
const q = new URLSearchParams(location.search)
// ?theme=light|dark forces a theme (for screenshots); otherwise the system theme applies.
if (q.get("theme") === "light" || q.get("theme") === "dark") document.documentElement.dataset.theme = q.get("theme")!
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)")

const [{ sensors, trials: realTrials }, template, feet, cadSteps] = await Promise.all([loadInsoleData(), loadTemplate(), loadFeet(), loadCadwalk()])
const outline = footOutline()
const denseModels: Record<"left" | "right", PressureModel> = {
  left: createPressureModel(sensors.left, outline),
  right: createPressureModel(sensors.right, outline),
}
const templateGrid = templateOnGrid(template, denseModels.left.grid)

type Screen = "watch" | "result" | "insole"
type FootKey = "flatter" | "typical" | "higher"

const EXAMPLES: { n: string; title: string; type: FootType; key: FootKey }[] = [
  { n: "1", title: "Example 1: Flatter arch", type: "flat", key: "flatter" },
  { n: "2", title: "Example 2: Typical arch", type: "normal", key: "typical" },
  { n: "3", title: "Example 3: Higher arch", type: "high arch", key: "higher" },
]
const footUrl = (key: FootKey) => `${import.meta.env.BASE_URL}models/foot-${key}.glb`

/** What is being shown: a recorded or synthetic stance, or a live device. */
interface Session {
  title: string
  side: "left" | "right"
  footKey: FootKey
  trial: Trial | null
  scan: string
  device: LiveSensor | null
  /** A clinic-plate step also has the same step as the 6-sensor kit would read it; the viewer toggles between them. */
  variants?: Record<"plate" | "kit", { trial: Trial; analysis: Analysis }>
}

/** Everything derived from the pressure data (recomputed when the session or the live rolling peak changes). */
interface Analysis {
  model: PressureModel
  maps: Float32Array | null
  peak: Float32Array
  diff: Float32Array
  cop: Float32Array | null
  indices: Indices | null
  mesh: InsoleMesh
  peakMax: number
  diffMax: number
}

/** `sparse` (6-sensor kit): contact widths saturate with so few sensors, so only the arch index decides the verdict. */
function analyzePeak(model: PressureModel, peak: Float32Array, maps: Float32Array | null, cop: Float32Array | null, sparse = false): Analysis {
  const diff = differenceMap(model.grid, peak, templateGrid)
  const full = computeIndices(model.grid, peak)
  const indices = full && sparse ? { ...full, verdict: full.archIndexClass } : full
  return {
    model, maps, peak, diff, cop, indices,
    mesh: buildInsole(outline, model.grid, peak, indices),
    peakMax: peak.reduce((m, v) => Math.max(m, v), 1),
    diffMax: diff.reduce((m, v) => Math.max(m, Math.abs(v)), 1e-9),
  }
}

function analyzeTrial(trial: Trial): Analysis {
  const model = denseModels[trial.side]
  const maps = frameMaps(model, trial)
  return analyzePeak(model, peakMap(model, maps, trial.nFrames), maps, copTrajectory(model, maps, trial.nFrames))
}

/** The same real plate step two ways: the full clinic plate map, and what the 6-FSR kit would read at its sensor positions
 *  (a small patch average per sensor, then the kit's own interpolation). */
function plateVariants(step: CadStep): NonNullable<Session["variants"]> {
  const model = denseModels.left
  const { grid } = model
  const size = grid.nx * grid.ny
  const coarse: Grid = { ...step.grid, mask: new Uint8Array(0) }
  const n = step.frames.length
  const maps = new Float32Array(n * size)
  const plateFrames = step.frames.map((q) => Float32Array.from(q, (v) => v * step.qstep))
  plateFrames.forEach((frame, f) => {
    for (const c of model.cells)
      maps[f * size + c] = sampleGrid(coarse, frame, grid.x0 + ((c % grid.nx) + 0.5) * grid.cell, grid.y0 + (Math.floor(c / grid.nx) + 0.5) * grid.cell)
  })
  const base = { source: "real" as const, side: step.side, fs: step.fs, nFrames: n }
  const plate: Trial = { ...base, id: `plate-${step.id}`, label: step.title, sensors: [], frames: new Float32Array(0) }
  const plateAnalysis = analyzePeak(model, peakMap(model, maps, n), maps, copTrajectory(model, maps, n))

  const patch = [[0, 0], [5, 0], [-5, 0], [0, 5], [0, -5]]
  const frames = new Float32Array(n * SENSOR_POSITIONS.length)
  plateFrames.forEach((frame, f) =>
    SENSOR_POSITIONS.forEach((s, k) => {
      frames[f * SENSOR_POSITIONS.length + k] = patch.reduce((sum, [dx, dy]) => sum + sampleGrid(coarse, frame, s.x + dx, s.y + dy), 0) / patch.length
    }))
  const kit: Trial = { ...base, id: `kit-${step.id}`, label: step.title, sensors: SENSOR_POSITIONS, frames }
  const kitModel = createPressureModel(SENSOR_POSITIONS, outline, SPARSE_KERNEL)
  const kitMaps = frameMaps(kitModel, kit)
  const sensorPeaks = new Float32Array(SENSOR_POSITIONS.length)
  for (let f = 0; f < n; f++) SENSOR_POSITIONS.forEach((_, k) => { sensorPeaks[k] = Math.max(sensorPeaks[k], frames[f * SENSOR_POSITIONS.length + k]) })
  const kitPeak = interpolate(kitModel, sensorPeaks, 0, new Float32Array(size))
  const kitAnalysis = analyzePeak(kitModel, kitPeak, kitMaps, copTrajectory(kitModel, kitMaps, n), true)
  return { plate: { trial: plate, analysis: plateAnalysis }, kit: { trial: kit, analysis: kitAnalysis } }
}

// UI state
let session: Session | null = null
let a: Analysis | null = null
let tracker: StepTracker | null = null
let liveModel: PressureModel | null = null
let unsub: (() => void) | null = null
let screen: Screen = "watch"
let position = 0
let playing = false
let last = 0
let raf = 0
let dirty = true
let rebuild = true
let pose: FootPose = FLAT_POSE
const liveFrame = new Float32Array(denseModels.left.grid.nx * denseModels.left.grid.ny)

const canvas = $<HTMLCanvasElement>("view")
const view = new InsoleScene(canvas, () => invalidate())

/** Scene background and materials follow the page theme (`--bg`, system or data-theme). */
function syncTheme(): void {
  const bg = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
  const c = bg.replace("#", "")
  const lum = c.length === 6 ? (parseInt(c.slice(0, 2), 16) * 0.299 + parseInt(c.slice(2, 4), 16) * 0.587 + parseInt(c.slice(4, 6), 16) * 0.114) / 255 : 0
  view.setTheme(bg, lum < 0.5)
  dirty = true
  invalidate()
}
syncTheme()
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", syncTheme)
new MutationObserver(syncTheme).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })
const el = {
  start: $("start"), app: $("app"), back: $("back"), who: $("who"), play: $<HTMLButtonElement>("play"), showFoot: $<HTMLInputElement>("show-foot"),
  liveBox: $("live-box"), liveStatus: $("live-status"), bars: $("bars"), values: $("values"),
  toResult: $<HTMLButtonElement>("to-result"), toInsole: $<HTMLButtonElement>("to-insole"),
  headline: $("headline"), marker: $("marker"), scale: $("scale"), meaning: $("meaning"), disclaimer: $("disclaimer"),
  support: $("support"), insoleMore: $("insole-more"), download: $<HTMLButtonElement>("download"),
  details: $<HTMLDetailsElement>("details"), indices: $("indices"), votes: $("votes"), scanNote: $("scan-note"),
  speed: $<HTMLSelectElement>("speed"), time: $("time"), scrub: $<HTMLInputElement>("scrub"), mapmode: $<HTMLSelectElement>("mapmode"),
  surface: $<HTMLSelectElement>("surface"), cmap: $<HTMLSelectElement>("cmap"), patterns: $<HTMLInputElement>("patterns"),
  sensors: $<HTMLInputElement>("sensors"), cop: $<HTMLInputElement>("cop"), legendBar: $("legend-bar"), live: $("live"),
  recorded: $<HTMLSelectElement>("recorded"), plateStep: $<HTMLSelectElement>("plate-step"), variantBox: $("variant-box"), connectError: $("connect-error"),
}
const sections: Record<Screen, HTMLElement> = { watch: $("s-watch"), result: $("s-result"), insole: $("s-insole") }
const navButtons = Array.from(document.querySelectorAll<HTMLButtonElement>("nav button"))

// Without a native web equivalent of shouldDifferentiateWithoutColor, high-contrast / forced-colors preferences turn patterns on.
el.patterns.checked = matchMedia("(prefers-contrast: more), (forced-colors: active)").matches
el.legendBar.style.background = `linear-gradient(90deg, ${colormapCss("viridis")})`
if (!isSerialSupported()) {
  $("serial-note").hidden = false
  $<HTMLButtonElement>("connect").disabled = true
}
for (const c of cadSteps) el.plateStep.append(new Option(c.title, c.id))
if (cadSteps.length === 0) ($("go-plate").closest(".tile") as HTMLElement).hidden = true
for (const t of realTrials) el.recorded.append(new Option(`Person ${t.id.slice(1).replace("-", ", ")} foot`, t.id))

/** Schedules one frame; the loop keeps itself alive only while playing, receiving live frames, or while camera damping settles. */
function invalidate(): void {
  if (!raf) raf = requestAnimationFrame(tick)
}

const isLive = () => session?.device != null
const mapMode = () => (screen === "watch" ? el.mapmode.value : el.mapmode.value === "frame" ? "peak" : el.mapmode.value)

function tick(now: number): void {
  raf = 0
  if (!session || !a) return
  if (playing && session.trial) {
    const dt = Math.min(0.1, (now - last) / 1000)
    position = (position + dt * session.trial.fs * Number(el.speed.value)) % session.trial.nFrames
    dirty = true
  }
  last = now
  if (isLive()) dirty = true
  if (dirty || rebuild) draw()
  if (view.render() || (playing && session.trial) || isLive()) invalidate()
}

function draw(): void {
  if (!session || !a) return
  const { model } = a
  const size = model.grid.nx * model.grid.ny
  const mode = mapMode()
  const diverging = mode === "diff"
  const plain = screen === "insole"
  if (rebuild) {
    view.setInsole(a.mesh, model.grid, session.trial?.sensors ?? session.device!.sensors)
    rebuild = false
  }
  view.setPlain(plain)
  view.setFootVisible(el.showFoot.checked && !plain)

  let map: Float32Array, vmax = a.peakMax, frame = 0
  if (session.trial) {
    const t = session.trial
    frame = Math.min(t.nFrames - 1, Math.floor(position))
    map = mode === "peak" ? a.peak : diverging ? a.diff : a.maps!.subarray(frame * size, (frame + 1) * size)
    pose = reducedMotion.matches || screen !== "watch" ? FLAT_POSE : stancePose(frame / t.nFrames)
  } else {
    const live = tracker!
    if (mode === "frame") {
      map = interpolate(liveModel!, live.latest, 0, liveFrame)
      vmax = live.scale()
    } else map = diverging ? a.diff : a.peak
    const target = screen !== "watch" || reducedMotion.matches ? FLAT_POSE : poseFromCop(copY(session.device!.sensors.map((s) => s.y), live.latest))
    pose = { pitch: pose.pitch + (target.pitch - pose.pitch) * 0.35, pivotY: target.pivotY, lift: pose.lift + (target.lift - pose.lift) * 0.35 }
    renderLive()
  }
  view.setFootPose(pose)
  view.setField({
    map, vmax: diverging ? a.diffMax : vmax, colormap: el.cmap.value as ColormapName,
    patterns: el.patterns.checked, diverging, terrain: el.surface.value === "terrain" && !plain,
  })
  view.setSensorsVisible(el.sensors.checked && !plain)
  if (a.cop && session.trial) view.setCop(a.cop, mode === "frame" ? frame + 1 : session.trial.nFrames, el.cop.checked && !plain)
  else view.setCop(new Float32Array(0), 0, false)
  if (session.trial) {
    el.scrub.value = String(frame)
    el.time.textContent = `${Math.round((frame / session.trial.fs) * 1000)} ms`
    const framePeak = a.maps!.subarray(frame * size, (frame + 1) * size).reduce((m, v) => Math.max(m, v), 0)
    el.live.textContent = mode === "frame" ? `frame ${frame + 1}/${session.trial.nFrames}, peak ${Math.round(framePeak)} kPa` : mode === "peak" ? `peak map, max ${Math.round(a.peakMax)} kPa` : "difference of load share vs MUN104 healthy mean"
  } else el.live.textContent = mode === "frame" ? "live frame" : mode === "peak" ? `rolling peak of the last steps, max ${Math.round(a.peakMax)} kPa` : "difference of load share vs MUN104 healthy mean"
  el.legendBar.style.background = diverging ? "linear-gradient(90deg, #5aaaff, #0e0e0e, #ff8c1a)" : `linear-gradient(90deg, ${colormapCss(el.cmap.value as ColormapName)})`
  dirty = false
}

/** Live sensor bars (friendly names) and the step counter. */
function renderLive(): void {
  const s = session!, live = tracker!
  const scale = live.scale()
  const names = s.device!.sensorNames
  if (el.bars.children.length !== names.length)
    el.bars.innerHTML = names.map((n) => `<li><span>${n}</span><span class="bar" aria-hidden="true"><i></i></span><output></output></li>`).join("")
  const lis = el.bars.children
  for (let k = 0; k < names.length; k++) {
    const v = live.latest[k] ?? 0
    ;(lis[k].querySelector("i") as HTMLElement).style.width = `${Math.min(100, (v / scale) * 100)}%`
    lis[k].querySelector("output")!.textContent = String(Math.round(v))
  }
  el.values.innerHTML = names.map((n, k) => `<li><span>${n}</span><span>${Math.round(live.latest[k] ?? 0)}</span></li>`).join("")
  el.liveStatus.textContent = live.ready ? `Got it: ${live.steps} steps seen.` : `Walk a few steps. ${Math.min(live.steps, live.needed)} of ${live.needed} steps seen.`
}

/** Result, insole and details text from the current analysis. */
function renderResults(): void {
  if (!session || !a) return
  const i = a.indices
  const ready = i !== null && (!isLive() || tracker!.ready)
  if (i && ready) {
    const r = readArch(i)
    el.headline.textContent = r.headline
    el.meaning.textContent = r.meaning
    el.marker.style.left = `${r.position * 100}%`
    el.scale.setAttribute("aria-label", `Arch scale from lower to higher. You are at ${r.level}.`)
    el.disclaimer.textContent = DISCLAIMER
    const p = DEFAULT_INSOLE
    el.support.textContent = `Extra arch support: ${Math.round(a.mesh.archHeight)} mm`
    el.insoleMore.textContent = `Cushioned heel cup ${p.heelCupHeight} mm. Softer spots under pressure hotspots. Printed in recycled TPU.`
  } else {
    el.headline.textContent = "Not enough steps yet"
    el.meaning.textContent = ""
    el.disclaimer.textContent = ""
    el.support.textContent = ""
    el.insoleMore.textContent = ""
  }
  const row = (name: string, value: string, cls: string, rule: string) => `<tr><td>${name}</td><td>${value}</td><td>${cls}</td></tr><tr><td colspan="3" class="rule">${rule}</td></tr>`
  el.indices.innerHTML = i
    ? row("Arch index", i.archIndex.toFixed(2), i.archIndexClass, "&gt;0.26 flat, &lt;0.21 high arch") +
      row("Staheli", i.staheli.toFixed(2), i.staheliClass, "&gt;0.89 flat, &lt;0.44 high arch") +
      row("Chippaux-Smirak", `${i.chippauxSmirak.toFixed(0)}%`, i.chippauxSmirakClass, "&gt;45% flat")
    : "<tr><td>Not enough contact to measure.</td></tr>"
  el.votes.textContent = i ? (isLive() ? "6 sensors: the result uses the arch index only." : `${i.flatVotes} of 3 indices suggest flat`) : ""
  el.scanNote.textContent = session.scan
  el.download.disabled = !ready
  el.toInsole.disabled = !ready
  el.toResult.hidden = isLive() && !tracker!.ready
  navButtons.forEach((b) => { b.disabled = isLive() && !tracker!.ready && b.dataset.screen !== "watch" })
  if (session.trial) el.scrub.max = String(session.trial.nFrames - 1)
}

function setScreen(next: Screen): void {
  screen = next
  for (const [name, node] of Object.entries(sections)) node.hidden = name !== next
  navButtons.forEach((b) => (b.dataset.screen === next ? b.setAttribute("aria-current", "step") : b.removeAttribute("aria-current")))
  el.mapmode.value = next === "watch" ? "frame" : "peak"
  el.details.hidden = next === "insole"
  dirty = true
  invalidate()
}

function stopSession(): void {
  unsub?.()
  unsub = null
  void session?.device?.disconnect()
  tracker = liveModel = null
}

function enter(s: Session, model?: PressureModel): void {
  stopSession()
  session = s
  position = 0
  playing = s.trial !== null
  pose = FLAT_POSE
  el.start.hidden = true
  el.app.hidden = false
  el.who.textContent = s.title
  el.play.hidden = s.trial === null
  el.play.textContent = playing ? "Pause" : "Play"
  el.liveBox.hidden = s.device === null
  el.scrub.hidden = s.device !== null
  el.bars.innerHTML = ""
  el.showFoot.checked = true
  el.variantBox.hidden = !s.variants
  const plateRadio = document.querySelector<HTMLInputElement>('input[name="variant"][value="plate"]')
  if (plateRadio) plateRadio.checked = true
  if (s.variants) a = s.variants.plate.analysis
  else if (s.trial) a = analyzeTrial(s.trial)
  else {
    liveModel = model!
    tracker = new StepTracker(s.device!.sensors.length)
    a = analyzePeak(liveModel, new Float32Array(liveFrame.length), null, null, true)
    unsub = s.device!.onFrame((kPa, tMs) => {
      if (tracker!.push(kPa, tMs)) {
        a = analyzePeak(liveModel!, interpolate(liveModel!, tracker!.rolling!, 0, new Float32Array(liveFrame.length)), null, null, true)
        rebuild = true
        renderResults()
      }
      dirty = true
      invalidate()
    })
  }
  void view.setFoot(footUrl(s.footKey)).then(invalidate)
  rebuild = dirty = true
  last = performance.now()
  renderResults()
  setScreen("watch")
  view.resize()
}

function startExample(n: string): void {
  const ex = EXAMPLES.find((e) => e.n === n)
  if (!ex) return
  const p = feet.picks[ex.key]
  const t = synthTrial(ex.type, sensors.left, template)
  enter({
    title: ex.title, side: "left", footKey: ex.key, trial: { ...t, id: `example-${ex.n}`, label: ex.title },
    scan: `Scanned foot: participant ${p.id}, standing arch index ${p.ai.toFixed(2)} (median of ${feet.stats.n} scans: ${feet.stats.percentiles["50"].toFixed(2)}). Pressure is synthetic for this foot type.`,
    device: null,
  })
}

function startRecorded(id: string): void {
  const t = realTrials.find((x) => x.id === id)
  if (!t) return
  enter({
    title: "Recorded walk (real sensor insole)", side: t.side, footKey: "typical", trial: t,
    scan: `${t.label}: one stance of a healthy adult, 48 sensors at 125 Hz (Zenodo 21743536). Arch type is not labeled. The foot shown is a typical scan, not this person.`,
    device: null,
  }) 
}

function startPlate(id: string): void {
  const step = cadSteps.find((c) => c.id === id)
  if (!step) return
  const variants = plateVariants(step)
  const footKey: FootKey = step.id.endsWith("higher") ? "higher" : step.id.endsWith("typical") ? "typical" : "flatter"
  enter({
    title: `Clinic plate walk: ${step.title}`, side: step.side, footKey, trial: variants.plate.trial, variants, device: null,
    scan: `Real step from a clinic pressure plate (CAD WALK, ${step.cohort}, participant ${step.subject}, plate arch index ${step.ai.toFixed(2)}). The 6-sensor view samples the same step at the kit's six spots. The foot shown is a typical scan, not this person.`,
  })
}

/** Switches a plate session between the clinic plate map and the 6-sensor kit reading of the same step. */
function useVariant(key: "plate" | "kit"): void {
  const v = session?.variants?.[key]
  if (!session || !v) return
  session.trial = v.trial
  a = v.analysis
  rebuild = dirty = true
  renderResults()
  invalidate()
}

function startLive(device: LiveSensor, footKey: FootKey): void {
  enter({ title: device.kind === "demo" ? "Demo sensor" : device.name, side: device.side, footKey, trial: null, scan: "Live 6-sensor reading. Values are approximate kPa.", device },
    createPressureModel(device.sensors, outline, SPARSE_KERNEL))
}

const selectedSide = () => (document.querySelector<HTMLInputElement>('input[name="side"]:checked')?.value ?? "left") as "left" | "right"
const demoFoot = () => $<HTMLSelectElement>("demo-foot").value as FootType
const footKeyFor = (t: FootType): FootKey => EXAMPLES.find((e) => e.type === t)!.key

document.querySelectorAll<HTMLButtonElement>("[data-example]").forEach((b) => b.addEventListener("click", () => startExample(b.dataset.example!)))
$("go-plate").addEventListener("click", () => startPlate(el.plateStep.value))
document.querySelectorAll<HTMLInputElement>('input[name="variant"]').forEach((r) => r.addEventListener("change", () => r.checked && useVariant(r.value as "plate" | "kit")))
$("go-recorded").addEventListener("click", () => startRecorded(el.recorded.value))
$("go-demo").addEventListener("click", () => startLive(connectDemoDevice(selectedSide(), demoFoot()), footKeyFor(demoFoot())))
$("connect").addEventListener("click", async () => {
  el.connectError.hidden = true
  try {
    startLive(await connectSerial(selectedSide()), "typical")
  } catch (e) {
    el.connectError.hidden = false
    el.connectError.textContent = `Could not connect: ${e instanceof Error ? e.message : String(e)}`
  }
})
el.back.addEventListener("click", () => {
  stopSession()
  session = null
  playing = false
  el.app.hidden = true
  el.start.hidden = false
})
navButtons.forEach((b) => b.addEventListener("click", () => setScreen(b.dataset.screen as Screen)))
el.toResult.addEventListener("click", () => setScreen("result"))
el.toInsole.addEventListener("click", () => setScreen("insole"))
for (const control of [el.mapmode, el.surface, el.cmap, el.patterns, el.sensors, el.cop, el.speed, el.showFoot])
  control.addEventListener("change", () => { dirty = true; invalidate() })
el.play.addEventListener("click", () => {
  playing = !playing
  el.play.textContent = playing ? "Pause" : "Play"
  last = performance.now()
  invalidate()
})
el.scrub.addEventListener("input", () => {
  position = Number(el.scrub.value)
  dirty = true
  invalidate()
})
el.download.addEventListener("click", () => {
  if (!session || !a) return
  const mesh = buildInsole(outline, a.model.grid, a.peak, a.indices, session.side)
  const url = URL.createObjectURL(new Blob([toBinaryStl(mesh)], { type: "model/stl" }))
  const link = Object.assign(document.createElement("a"), { href: url, download: `insole-${session.title.toLowerCase().replace(/\W+/g, "-")}.stl` })
  link.click()
  URL.revokeObjectURL(url)
})
canvas.addEventListener("keydown", (e) => {
  const step = 0.12
  const moves: Record<string, () => void> = {
    ArrowLeft: () => view.nudge(-step, 0),
    ArrowRight: () => view.nudge(step, 0),
    ArrowUp: () => view.nudge(0, -step),
    ArrowDown: () => view.nudge(0, step),
    "+": () => view.nudge(0, 0, 0.9),
    "=": () => view.nudge(0, 0, 0.9),
    "-": () => view.nudge(0, 0, 1.1),
  }
  const move = moves[e.key]
  if (!move) return
  e.preventDefault()
  move()
  invalidate()
})
new ResizeObserver(() => { view.resize(); invalidate() }).observe(canvas)

// Deep links (for screenshots): ?ex=1|2|3 or ?source=p4-left or ?live=demo&foot=flat&side=right, plus
// screen=watch|result|insole, frame=40 (pauses), details=1, map=, surface=, cmap=, patterns=1.
if (q.has("ex")) startExample(q.get("ex")!)
else if (q.has("plate")) {
  startPlate(q.get("plate")!)
  if (q.get("variant") === "kit") {
    const r = document.querySelector<HTMLInputElement>('input[name="variant"][value="kit"]')
    if (r) r.checked = true
    useVariant("kit")
  }
} else if (q.has("source")) startRecorded(q.get("source")!)
else if (q.get("live") === "demo") {
  const t = (q.get("foot") ?? "normal") as FootType
  startLive(connectDemoDevice((q.get("side") as "left" | "right") ?? "left", t), footKeyFor(t))
}
if (session) {
  if (q.has("frame")) {
    position = Number(q.get("frame"))
    playing = false
    el.play.textContent = "Play"
  }
  const next = (q.get("screen") ?? "watch") as Screen
  // Live sessions need steps first; the link waits for them.
  const go = () => { setScreen(next); el.mapmode.value = q.get("map") ?? el.mapmode.value }
  if (isLive() && next !== "watch") {
    const wait = setInterval(() => { if (tracker?.ready) { clearInterval(wait); go() } }, 100)
  } else go()
  el.surface.value = q.get("surface") ?? el.surface.value
  el.cmap.value = q.get("cmap") ?? el.cmap.value
  if (q.has("patterns")) el.patterns.checked = q.get("patterns") === "1"
  if (q.has("details")) el.details.open = true
  dirty = true
  invalidate()
}
