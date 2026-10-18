import "./style.css"
import { colormapCss, type ColormapName } from "./core/colormap"
import { computeIndices, type Indices } from "./core/indices"
import { buildInsole, DEFAULT_INSOLE, type InsoleMesh } from "./core/insole"
import { footOutline } from "./core/outline"
import { copTrajectory, createPressureModel, frameMaps, peakMap, type PressureModel } from "./core/pressure"
import { toBinaryStl } from "./core/stl"
import { synthTrial } from "./core/synth"
import { differenceMap, templateOnGrid } from "./core/template"
import type { FootType, Trial } from "./core/types"
import { loadInsoleData, loadTemplate } from "./data"
import { InsoleScene } from "./view/scene"

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T

const [{ sensors, trials: realTrials }, template] = await Promise.all([loadInsoleData(), loadTemplate()])
const outline = footOutline()
const models: Record<"left" | "right", PressureModel> = {
  left: createPressureModel(sensors.left, outline),
  right: createPressureModel(sensors.right, outline),
}
const footTypes: FootType[] = ["normal", "flat", "high arch"]
const trials: Trial[] = [...footTypes.map((t) => synthTrial(t, sensors.left, template)), ...realTrials]
const templateGrid = templateOnGrid(template, models.left.grid)

/** Everything derived from the selected trial. */
interface Analysis {
  trial: Trial
  model: PressureModel
  maps: Float32Array
  peak: Float32Array
  diff: Float32Array
  cop: Float32Array
  indices: Indices | null
  mesh: InsoleMesh
  peakMax: number
  diffMax: number
}

function analyze(trial: Trial): Analysis {
  const model = models[trial.side]
  const maps = frameMaps(model, trial)
  const peak = peakMap(model, maps, trial.nFrames)
  const diff = differenceMap(model.grid, peak, templateGrid)
  const indices = computeIndices(model.grid, peak)
  return {
    trial, model, maps, peak, diff, indices,
    cop: copTrajectory(model, maps, trial.nFrames),
    mesh: buildInsole(outline, model.grid, peak, indices),
    peakMax: peak.reduce((m, v) => Math.max(m, v), 1),
    diffMax: diff.reduce((m, v) => Math.max(m, Math.abs(v)), 1e-9),
  }
}

// UI state
let a = analyze(trials[1])
let position = 0 // fractional frame
let playing = false
let last = 0
let raf = 0
let dirty = true
let rebuild = true

const canvas = $<HTMLCanvasElement>("view")
const view = new InsoleScene(canvas, () => invalidate())
const el = {
  source: $<HTMLSelectElement>("source"), note: $("source-note"), play: $<HTMLButtonElement>("play"), speed: $<HTMLSelectElement>("speed"),
  time: $("time"), scrub: $<HTMLInputElement>("scrub"), mapmode: $<HTMLSelectElement>("mapmode"), surface: $<HTMLSelectElement>("surface"),
  cmap: $<HTMLSelectElement>("cmap"), patterns: $<HTMLInputElement>("patterns"), sensors: $<HTMLInputElement>("sensors"),
  cop: $<HTMLInputElement>("cop"), legendBar: $("legend-bar"), legendLo: $("legend-lo"), legendMax: $("legend-max"), live: $("live"),
  indices: $("indices"), votes: $("votes"), verdict: $("verdict"), insole: $("insole-info"), download: $<HTMLButtonElement>("download"),
}

// Without a native web equivalent of shouldDifferentiateWithoutColor, high-contrast / forced-colors preferences turn patterns on.
el.patterns.checked = matchMedia("(prefers-contrast: more), (forced-colors: active)").matches

function buildSourceMenu(): void {
  const group = (label: string, items: Trial[]) => {
    const g = document.createElement("optgroup")
    g.label = label
    for (const t of items) g.append(new Option(t.label, t.id))
    el.source.append(g)
  }
  group("Synthetic (MUN104-based)", trials.filter((t) => t.source === "synthetic"))
  group("Real insole, 14 healthy adults", trials.filter((t) => t.source === "real"))
  el.source.value = a.trial.id
}

/** Schedules one frame; the loop keeps itself alive only while playing or while camera damping settles. */
function invalidate(): void {
  if (!raf) raf = requestAnimationFrame(tick)
}

function tick(now: number): void {
  raf = 0
  if (playing) {
    const dt = Math.min(0.1, (now - last) / 1000)
    position = (position + dt * a.trial.fs * Number(el.speed.value)) % a.trial.nFrames
    dirty = true
  }
  last = now
  if (dirty || rebuild) draw()
  if (view.render() || playing) invalidate()
}

function draw(): void {
  const { trial, model } = a
  const frame = Math.min(trial.nFrames - 1, Math.floor(position))
  const size = model.grid.nx * model.grid.ny
  const mode = el.mapmode.value
  const diverging = mode === "diff"
  if (rebuild) {
    view.setInsole(a.mesh, model.grid, trial.sensors)
    rebuild = false
  }
  const map = mode === "peak" ? a.peak : diverging ? a.diff : a.maps.subarray(frame * size, (frame + 1) * size)
  view.setField({
    map, vmax: diverging ? a.diffMax : a.peakMax, colormap: el.cmap.value as ColormapName,
    patterns: el.patterns.checked, diverging, terrain: el.surface.value === "terrain",
  })
  view.setSensorsVisible(el.sensors.checked)
  view.setCop(a.cop, mode === "frame" ? frame + 1 : trial.nFrames, el.cop.checked)
  el.scrub.value = String(frame)
  el.time.textContent = `${Math.round((frame / trial.fs) * 1000)} ms`
  const framePeak = a.maps.subarray(frame * size, (frame + 1) * size).reduce((m, v) => Math.max(m, v), 0)
  el.live.textContent = mode === "frame" ? `frame ${frame + 1}/${trial.nFrames}, peak ${Math.round(framePeak)} kPa` : mode === "peak" ? `peak map, max ${Math.round(a.peakMax)} kPa` : "difference of load share vs MUN104 healthy mean"
  const legend = diverging ? "linear-gradient(90deg, #5aaaff, #0e0e0e, #ff8c1a)" : `linear-gradient(90deg, ${colormapCss(el.cmap.value as ColormapName)})`
  el.legendBar.style.background = legend
  el.legendLo.textContent = diverging ? "less than healthy" : "0"
  el.legendMax.textContent = diverging ? "more than healthy" : `${Math.round(a.peakMax)} kPa`
  dirty = false
}

function renderResults(): void {
  const { trial, indices: i } = a
  el.note.textContent =
    trial.source === "real"
      ? "Real recording: one stance of one healthy adult, 48 FSRs at 125 Hz (Zenodo 21743536). Arch type is not labeled. Sparse sensors cover about 6 cm of foot width, so indices run high on widths."
      : `Synthetic: ${trial.label.replace("Synthetic ", "")} model built from the MUN104 mean of 104 healthy feet. Not measured.`
  const row = (name: string, value: string, cls: string, rule: string) => `<tr><td>${name}</td><td>${value}</td><td>${cls}</td></tr><tr><td colspan="3" class="rule">${rule}</td></tr>`
  el.indices.innerHTML = i
    ? row("Arch index", i.archIndex.toFixed(2), i.archIndexClass, "&gt;0.26 flat, &lt;0.21 high arch") +
      row("Staheli", i.staheli.toFixed(2), i.staheliClass, "&gt;0.89 flat, &lt;0.44 high arch") +
      row("Chippaux-Smirak", `${i.chippauxSmirak.toFixed(0)}%`, i.chippauxSmirakClass, "&gt;45% flat")
    : "<tr><td>Not enough contact to measure.</td></tr>"
  el.votes.textContent = i ? `${i.flatVotes} of 3 indices suggest flat` : ""
  const words = { flat: "Pattern consistent with flat feet", "high arch": "Pattern consistent with a high arch", normal: "Pattern consistent with a typical arch", inconclusive: "Mixed signals, inconclusive" }
  el.verdict.textContent = i ? `${words[i.verdict]}. Screening, not diagnosis. See a clinician if you have pain.` : ""
  const p = DEFAULT_INSOLE
  el.insole.textContent = `Insole: base ${p.base} mm, heel cup ${p.heelCupHeight} mm, arch support ${a.mesh.archHeight.toFixed(1)} mm, ${p.reliefDepth} mm relief under hotspots. Recycled TPU.`
  el.scrub.max = String(trial.nFrames - 1)
}

function select(id: string): void {
  const t = trials.find((x) => x.id === id)
  if (!t) return
  a = analyze(t)
  position = 0
  rebuild = dirty = true
  renderResults()
  invalidate()
}

el.source.addEventListener("change", () => select(el.source.value))
for (const control of [el.mapmode, el.surface, el.cmap, el.patterns, el.sensors, el.cop, el.speed])
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
  const mesh = buildInsole(outline, a.model.grid, a.peak, a.indices, a.trial.side)
  const url = URL.createObjectURL(new Blob([toBinaryStl(mesh)], { type: "model/stl" }))
  const link = Object.assign(document.createElement("a"), { href: url, download: `insole-${a.trial.id}.stl` })
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

buildSourceMenu()
// Optional deep link, e.g. ?source=p3-left&map=diff&surface=terrain&patterns=1&frame=40
const q = new URLSearchParams(location.search)
if (q.has("source")) select(q.get("source")!)
el.source.value = a.trial.id
el.mapmode.value = q.get("map") ?? el.mapmode.value
el.surface.value = q.get("surface") ?? el.surface.value
el.cmap.value = q.get("cmap") ?? el.cmap.value
if (q.has("patterns")) el.patterns.checked = q.get("patterns") === "1"
position = Number(q.get("frame") ?? 0)
renderResults()
view.resize()
invalidate()
