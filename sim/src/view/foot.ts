import { BufferAttribute, Matrix4, Mesh, MeshStandardMaterial, BufferGeometry, type Texture } from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import type { FootPose } from "../core/gait"
import { edgeDistance, footOutline, inside } from "../core/outline"

const TOE_HINGE = [-10, 25] as const // mm around the pivot over which the toes bend back flat during push-off

/** Plantar contact = scan vertices within this height of the sole plane (GLB units, same band pick_feet.py uses). */
const SOLE_BAND = 3
/** Clearance kept between the foot silhouette and the insole outline, mm. */
const EDGE_MARGIN = 2
/** The foot is stretched along y to span the insole: rear of the heel this far from the heel edge, toe tips this far
 *  before the toe edge, mm. */
const HEEL_INSET = 6
const TOE_MARGIN = 6
/** Row-by-row width scale (foot silhouette width -> insole width at the same y) is limited to this range, so the foot is
 *  squeezed or widened but never mangled. */
const MIN_WIDTH_SCALE = 0.72
const MAX_WIDTH_SCALE = 1.12
const ROW_SMOOTH = 10 // mm half-window used to smooth the per-row scale and offset
/** Pre-fit width scale used while searching for the rotation and offset. */
const SEARCH_WIDTH_SCALE = 0.85
/** Ball of the foot as a fraction of the footprint length from the heel (metatarsal heads). */
const BALL_FRACTION = 0.72
/** Contact patches (heel pad, ball) over which the sole is seated on the insole surface, mm radius. */
const SEAT_RADIUS = 12
/** Height (scan units) up to which the foot outline must fit inside the insole outline. */
const SILHOUETTE_Z = 12
const ANKLE_Z = 35 // mm (rest frame, scan units) above which the leg stub is domed over
const ANKLE_CAP = 22 // mm (scan units) the domed leg may rise above ANKLE_Z

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** Signed distance to the insole outline on a 1 mm grid (positive inside), for fast footprint-fit queries. */
function outlineField() {
  const o = footOutline()
  const x0 = Math.floor(Math.min(...o.map((p) => p.x))) - 6, y0 = Math.floor(Math.min(...o.map((p) => p.y))) - 6
  const nx = Math.ceil(Math.max(...o.map((p) => p.x))) + 6 - x0, ny = Math.ceil(Math.max(...o.map((p) => p.y))) + 6 - y0
  const d = new Float32Array(nx * ny)
  for (let j = 0; j < ny; j++)
    for (let i = 0; i < nx; i++) {
      const x = x0 + i, y = y0 + j
      d[j * nx + i] = (inside(o, x, y) ? 1 : -1) * edgeDistance(o, x, y)
    }
  const at = (x: number, y: number) => {
    const i = Math.round(x - x0), j = Math.round(y - y0)
    return i < 0 || j < 0 || i >= nx || j >= ny ? -50 : d[j * nx + i]
  }
  return { at, minY: Math.min(...o.map((p) => p.y)), maxY: Math.max(...o.map((p) => p.y)), cx: (Math.min(...o.map((p) => p.x)) + Math.max(...o.map((p) => p.x))) / 2 }
}

/** Own-scan sole band (mm): a standing scan's sole is a hole fill a few mm above the floor. */
const OWN_SOLE_BAND = 6
/** Height of the ankle cut that is domed shut on an own scan, mm. */
const OWN_DOME = 30
/** Ragged-cut allowance at the top of an own scan's ankle, mm. */
const OWN_CUT_NOISE = 8

/** Rigid + uniform-scale placement of the scan: p' = k * Rz(theta) p + (dx, dy). */
/** Placement of the scan: p' = Rz(theta) * diag(kx, ky) p + (dx, dy), then a per-row width warp `fillX` that stretches
 *  each row of the foot between the insole's medial and lateral edges (so the foot fills the outline). */
interface Placement { kx: number; ky: number; theta: number; dx: number; dy: number; fillX: (x: number, y: number) => number; widthScale: { min: number; max: number } }

const IDENTITY: Placement = { kx: 1, ky: 1, theta: 0, dx: 0, dy: 0, fillX: (x) => x, widthScale: { min: 1, max: 1 } }

/** Registers the scan's silhouette (xy of the vertices up to SILHOUETTE_Z, scan units) to the insole outline, filling it.
 *  1. Length: ky spans heel to toes between the insole ends (HEEL_INSET, TOE_MARGIN), independent of width.
 *  2. Rotation about z and translation: the best maximin clearance at a nominal width squeeze.
 *  3. Width: per y row, the foot's lateral extent is mapped onto the insole's (EDGE_MARGIN inside each edge), with the
 *     row scale clamped to [MIN_WIDTH_SCALE, MAX_WIDTH_SCALE] and smoothed along y. */
function register(foot: Float32Array): Placement {
  const field = outlineField()
  const pts: number[] = []
  const stride = Math.max(1, Math.floor(foot.length / 2 / 700))
  for (let i = 0; i < foot.length; i += 2 * stride) pts.push(foot[i], foot[i + 1])
  let minY = Infinity, maxY = -Infinity, sx = 0, n = 0
  for (let i = 0; i < foot.length; i += 2) { minY = Math.min(minY, foot[i + 1]); maxY = Math.max(maxY, foot[i + 1]); sx += foot[i]; n++ }
  const cx = sx / n
  const ky = (field.maxY - TOE_MARGIN - (field.minY + HEEL_INSET)) / (maxY - minY)
  const kx = SEARCH_WIDTH_SCALE
  const clearance = (th: number, dx: number, dy: number, floor: number) => {
    const c = Math.cos(th), s = Math.sin(th)
    let m = Infinity
    for (let i = 0; i < pts.length; i += 2) {
      const x = pts[i] * kx, y = pts[i + 1] * ky
      m = Math.min(m, field.at(x * c - y * s + dx, x * s + y * c + dy))
      if (m < floor) return m
    }
    return m
  }
  let at = { theta: 0, dx: 0, dy: 0, m: -Infinity }
  const dx0 = field.cx - cx * kx, dy0 = field.minY + HEEL_INSET - minY * ky
  const attempt = (theta: number, dx: number, dy: number) => {
    const m = clearance(theta, dx, dy, at.m)
    if (m > at.m) at = { theta, dx, dy, m }
  }
  for (let th = -0.2; th <= 0.2 + 1e-9; th += 0.0175)
    for (let ddx = -24; ddx <= 24; ddx += 3)
      for (let ddy = -6; ddy <= 6; ddy += 2) attempt(th, dx0 + ddx, dy0 + ddy)
  const c0 = at
  for (let ddx = -2; ddx <= 2; ddx += 0.5)
    for (let ddy = -2; ddy <= 2; ddy += 0.5)
      for (const dth of [-0.01, 0, 0.01]) attempt(c0.theta + dth, c0.dx + ddx, c0.dy + ddy)

  // Per-row width fit, on a 1 mm grid of y over the insole.
  const rows = Math.ceil(field.maxY - field.minY) + 1
  const fmin = new Float32Array(rows).fill(NaN), fmax = new Float32Array(rows).fill(NaN)
  const cs = Math.cos(at.theta), sn = Math.sin(at.theta)
  for (let i = 0; i < foot.length; i += 2) {
    const x = foot[i] * kx, y = foot[i + 1] * ky
    const X = x * cs - y * sn + at.dx, Y = x * sn + y * cs + at.dy
    const r = Math.round(Y - field.minY)
    if (r < 0 || r >= rows) continue
    fmin[r] = Number.isNaN(fmin[r]) ? X : Math.min(fmin[r], X)
    fmax[r] = Number.isNaN(fmax[r]) ? X : Math.max(fmax[r], X)
  }
  const fill = <T extends Float32Array>(a: T) => { // carry the nearest known row into gaps
    let last = NaN
    for (let r = 0; r < rows; r++) { if (Number.isNaN(a[r])) a[r] = last; else last = a[r] }
    last = NaN
    for (let r = rows - 1; r >= 0; r--) { if (Number.isNaN(a[r])) a[r] = last; else last = a[r] }
  }
  fill(fmin); fill(fmax)
  const scale = new Float32Array(rows), shift = new Float32Array(rows) // x' = ic + (x - fc) * scale (ic: insole row center, fc: foot row center)
  for (let r = 0; r < rows; r++) {
    const y = field.minY + r
    let lo = NaN, hi = NaN
    for (let x = -100; x <= 120; x += 0.5) if (field.at(x, y) >= EDGE_MARGIN) { if (Number.isNaN(lo)) lo = x; hi = x }
    if (Number.isNaN(lo)) { scale[r] = 1; continue }
    scale[r] = Math.min(MAX_WIDTH_SCALE, Math.max(MIN_WIDTH_SCALE, (hi - lo) / Math.max(1, fmax[r] - fmin[r])))
    shift[r] = (lo + hi) / 2 // insole row center; made relative to the smoothed foot center below
  }
  const smooth1 = (a: Float32Array) => {
    const out = new Float32Array(rows)
    for (let r = 0; r < rows; r++) {
      let sum = 0, cnt = 0
      for (let k = -ROW_SMOOTH; k <= ROW_SMOOTH; k++) if (r + k >= 0 && r + k < rows) { sum += a[r + k]; cnt++ }
      out[r] = sum / cnt
    }
    return out
  }
  const sScale = smooth1(scale), ic = smooth1(shift)
  const fc = smooth1(Float32Array.from(fmin, (v, r) => (v + fmax[r]) / 2))
  let wmin = Infinity, wmax = -Infinity
  for (let r = 0; r < rows; r++) if (fmax[r] - fmin[r] > 20) { wmin = Math.min(wmin, sScale[r] * kx); wmax = Math.max(wmax, sScale[r] * kx) }
  const fillX = (x: number, y: number) => {
    const t = Math.min(rows - 1, Math.max(0, y - field.minY)), r0 = Math.floor(t), r1 = Math.min(rows - 1, r0 + 1), f = t - r0
    const lerp = (a: Float32Array) => a[r0] * (1 - f) + a[r1] * f
    return lerp(ic) + (x - lerp(fc)) * lerp(sScale)
  }
  return { kx, ky, theta: at.theta, dx: at.dx, dy: at.dy, fillX, widthScale: { min: wmin, max: wmax } }
}

/** A scanned foot (GLB in the canonical frame: sole on z = 0, y heel -> toe) registered to the insole outline and
 *  posable through a step. The registration is computed from the mesh at load time (see `register`), so it does not
 *  depend on how the GLB was centered. Posing rewrites vertex positions on the CPU (about 10k vertices): rotation
 *  about a pivot on the sole (heel or ball), with the toes held flat during push-off so they do not sink. */
export class FootModel {
  readonly mesh: Mesh
  private rest: Float32Array
  private geo: BufferGeometry
  /** Sole-band vertices after registration: [x, y, z] triples. */
  private sole: Float32Array = new Float32Array(0)
  /** Footprint rear (heel contact) and ball of the foot, insole y in mm. */
  heelY = 0
  ballY = 0
  /** Footprint centroid x, mm (axis for roll). */
  centerX = 0
  /** Length scale (y) and the range of the row-wise width scale (x) applied to the scan, relative to the GLB (for inspection). */
  scale: { x: { min: number; max: number }; y: number } = { x: { min: 1, max: 1 }, y: 1 }
  /** Height of the sole above the insole base plane; set by `seat`. */
  seatZ = 3
  /** True for the user's own scan: already in the canonical frame and matched to its own insole, so no registration to the generic outline. */
  private readonly own: boolean
  private soleBand = SOLE_BAND
  /** Own scan: vertex indices at the closed top of the ankle dome. */
  private apex: number[] = []

  /** Photo texture of a realistic scan: drawn opaque and untinted, so theme tones and opacity do not apply. */
  private readonly map: Texture | null

  private constructor(geo: BufferGeometry, own: boolean, map: Texture | null = null) {
    this.own = own
    this.map = map
    if (own) this.soleBand = OWN_SOLE_BAND
    this.geo = geo
    this.rest = (geo.getAttribute("position") as BufferAttribute).array.slice() as Float32Array
    this.fit()
    this.mesh = new Mesh(geo, map
      ? new MeshStandardMaterial({ map, roughness: 0.85, metalness: 0 })
      : new MeshStandardMaterial({
        color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.3, roughness: 0.6, metalness: 0, transparent: true, opacity: 0.34, depthWrite: false,
      }))
    this.mesh.renderOrder = map ? 0 : 2
    this.mesh.frustumCulled = false
    this.pose({ pitch: 0, pivot: 0, lift: 0 })
  }

  /** Registers the rest pose to the insole outline (once, at construction) and closes the open leg cut into a low dome. */
  private fit(): void {
    const r = this.rest
    const footprint: number[] = []
    // Register the foot's outline just above the sole (it flares out over the contact patch), below the malleoli that overhang any insole.
    for (let i = 0; i < r.length; i += 3) if (r[i + 2] < SILHOUETTE_Z) footprint.push(r[i], r[i + 1])
    const { kx, ky, theta, dx, dy, fillX, widthScale } = this.own ? IDENTITY : register(Float32Array.from(footprint))
    this.scale = { x: widthScale, y: ky }
    const kz = Math.sqrt(kx * ky)
    const c = Math.cos(theta), s = Math.sin(theta)
    // Leg stub: pinch xy toward the stub's center and compress z, so the open cut at the top closes into a dome.
    let top = 0, cx = 0, cy = 0, maxZ = 0
    for (let i = 0; i < r.length; i += 3) maxZ = Math.max(maxZ, r[i + 2])
    // A scan keeps its real height; only the top of its ankle cut is domed over.
    const ankleZ = this.own ? maxZ - OWN_DOME : ANKLE_Z, ankleCap = this.own ? OWN_DOME * 0.75 : ANKLE_CAP
    for (let i = 0; i < r.length; i += 3) {
      if (r[i + 2] > ankleZ) { cx += r[i]; cy += r[i + 1]; top++ }
    }
    cx /= top; cy /= top
    const sole: number[] = []
    for (let i = 0; i < r.length; i += 3) {
      let x = r[i], y = r[i + 1], z = r[i + 2]
      const isSole = z < this.soleBand
      if (z > ankleZ) {
        // On a scan the cut is ragged: everything within OWN_CUT_NOISE of the top collapses to the apex so no hole is left.
        const t = Math.min(1, (z - ankleZ) / (maxZ - (this.own ? OWN_CUT_NOISE : 0) - ankleZ))
        const pinch = Math.cos((t * Math.PI) / 2) ** 0.6
        if (this.own && t > 0.95) this.apex.push(i / 3)
        x = cx + (x - cx) * pinch
        y = cy + (y - cy) * pinch
        z = ankleZ + ankleCap * Math.sin((t * Math.PI) / 2)
      }
      const px = x * kx, py = y * ky
      const X = px * c - py * s + dx, Y = px * s + py * c + dy
      r[i] = fillX(X, Y)
      r[i + 1] = Y
      r[i + 2] = z * kz
      if (isSole) sole.push(r[i], r[i + 1], r[i + 2])
    }
    this.sole = Float32Array.from(sole)
    let minY = Infinity, maxY = -Infinity, sx = 0
    for (let i = 0; i < this.sole.length; i += 3) {
      minY = Math.min(minY, this.sole[i + 1]); maxY = Math.max(maxY, this.sole[i + 1]); sx += this.sole[i]
    }
    this.heelY = minY
    this.ballY = minY + BALL_FRACTION * (maxY - minY)
    this.centerX = sx / (this.sole.length / 3)
  }

  /** Rests the sole on the insole surface: lifts the foot so its heel pad and ball clear `heightAt` (the insole's top
   *  surface). The arch is left to interpenetrate slightly. Call whenever the insole changes. */
  seat(heightAt: (x: number, y: number) => number): void {
    const s = this.sole
    const patch = (cx: number, cy: number) => {
      let need = this.own ? -Infinity : 0
      for (let i = 0; i < s.length; i += 3)
        if (Math.hypot(s[i] - cx, s[i + 1] - cy) < SEAT_RADIUS) need = Math.max(need, heightAt(s[i], s[i + 1]) - s[i + 2])
      return need
    }
    const xAt = (y: number) => {
      let sum = 0, n = 0
      for (let i = 0; i < s.length; i += 3) if (Math.abs(s[i + 1] - y) < 8) { sum += s[i]; n++ }
      return n ? sum / n : this.centerX
    }
    const heelC = this.heelY + SEAT_RADIUS + 4, ball = this.ballY
    const seat = Math.max(patch(xAt(heelC), heelC), patch(xAt(ball), ball))
    this.seatZ = Number.isFinite(seat) ? seat : 0
    this.pose(this.last)
  }

  private last: FootPose = { pitch: 0, pivot: 0, lift: 0 }

  /** Material tones for the page theme: pale glass on dark, soft ink on light. */
  setTone(dark: boolean): void {
    if (this.map) return
    const m = this.mesh.material as MeshStandardMaterial
    m.color.set(dark ? 0xffffff : 0x2e2b22)
    m.emissive.set(dark ? 0xffffff : 0x000000)
    m.emissiveIntensity = dark ? 0.3 : 0
    m.opacity = dark ? 0.34 : 0.42
  }

  static async load(url: string): Promise<FootModel> {
    const gltf = await new GLTFLoader().loadAsync(url)
    let geo: BufferGeometry | null = null
    gltf.scene.traverse((o) => { if (!geo && (o as Mesh).isMesh) geo = (o as Mesh).geometry })
    if (!geo) throw new Error(`no mesh in ${url}`)
    return new FootModel(geo, false)
  }

  /** The user's own scan (positions + triangle indices, canonical frame, sole on z = 0). */
  static fromScan(positions: Float32Array, indices: Uint32Array): FootModel {
    const geo = new BufferGeometry()
    geo.setAttribute("position", new BufferAttribute(positions.slice(), 3))
    geo.setIndex(new BufferAttribute(indices, 1))
    return new FootModel(geo, true)
  }

  /** A realistic scan: textured geometry (position, uv, index) already in the canonical frame, plus its photo texture. */
  static fromTextured(geo: BufferGeometry, map: Texture): FootModel {
    return new FootModel(geo, true, map)
  }

  set opacity(v: number) {
    const m = this.mesh.material as MeshStandardMaterial
    m.opacity = v
  }

  /** Poses the foot: `pivot` 0 = heel contact point, 1 = ball of the foot (blended in between during swing). The pivot
   *  stays on the sole plane at the seated height, so the foot rolls on the insole surface. */
  pose(p: FootPose): void {
    this.last = p
    const { pitch, pivot, lift } = p
    const pivotY = this.heelY + pivot * (this.ballY - this.heelY)
    const pos = this.geo.getAttribute("position") as BufferAttribute
    const a = pos.array as Float32Array
    for (let i = 0; i < a.length; i += 3) {
      const x = this.rest[i], y = this.rest[i + 1], z = this.rest[i + 2]
      const th = pitch < 0 ? pitch * (1 - smooth(pivotY + TOE_HINGE[0], pivotY + TOE_HINGE[1], y)) : pitch
      const c = Math.cos(th), s = Math.sin(th)
      const dy = y - pivotY
      a[i] = x
      a[i + 1] = pivotY + dy * c - z * s
      a[i + 2] = this.seatZ + lift + dy * s + z * c
    }
    pos.needsUpdate = true
    this.geo.computeVertexNormals()
    if (this.own) {
      // The dome apex is many vertices at one point, whose faces have no area: give them an up normal instead of noise.
      const nrm = this.geo.getAttribute("normal") as BufferAttribute
      for (const i of this.apex) nrm.setXYZ(i, 0, 0, 1)
    }
  }
}

/** Loads a realistic scan (GLB in the file coordinates of the matching STL, see scripts/convert_usdz.py) and moves it into
 *  the canonical frame with that STL's `ScanResult.toCanonical`. Winding is flipped when the result faces inward (a
 *  mirrored right foot), so it shades like the plain scan. */
export async function loadRealScan(url: string, toCanonical: number[]): Promise<{ geo: BufferGeometry; map: Texture }> {
  const gltf = await new GLTFLoader().loadAsync(url)
  const meshes: Mesh[] = []
  gltf.scene.traverse((o) => { if ((o as Mesh).isMesh) meshes.push(o as Mesh) })
  const mesh = meshes[0]
  const map = mesh ? (mesh.material as MeshStandardMaterial).map : null
  if (!mesh || !map) throw new Error(`no textured mesh in ${url}`)
  mesh.updateWorldMatrix(true, false)
  const geo = mesh.geometry.clone().applyMatrix4(mesh.matrixWorld).applyMatrix4(new Matrix4().fromArray(toCanonical))
  geo.deleteAttribute("normal")
  const p = geo.getAttribute("position") as BufferAttribute, index = geo.getIndex()!
  let volume = 0
  for (let t = 0; t < index.count; t += 3) {
    const [a, b, c] = [index.getX(t), index.getX(t + 1), index.getX(t + 2)]
    const [ax, ay, az, bx, by, bz, cx, cy, cz] = [p.getX(a), p.getY(a), p.getZ(a), p.getX(b), p.getY(b), p.getZ(b), p.getX(c), p.getY(c), p.getZ(c)]
    volume += ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx)
  }
  if (volume < 0) for (let t = 0; t < index.count; t += 3) {
    const b = index.getX(t + 1)
    index.setX(t + 1, index.getX(t + 2))
    index.setX(t + 2, b)
  }
  return { geo, map }
}
