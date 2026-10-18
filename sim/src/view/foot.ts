import { BufferAttribute, Mesh, MeshStandardMaterial, type BufferGeometry } from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import type { FootPose } from "../core/gait"
import { edgeDistance, footOutline, inside } from "../core/outline"

const TOE_HINGE = [-10, 25] as const // mm around the pivot over which the toes bend back flat during push-off

/** Plantar contact = scan vertices within this height of the sole plane (GLB units, same band pick_feet.py uses). */
const SOLE_BAND = 3
/** Footprint clearance from the insole outline, mm. The foot is scaled up until it just keeps this much. */
const EDGE_MARGIN = 2
/** A foot that cannot keep the margin above STRICT_MIN_SCALE (a flat arch fills the insole's medial cut-in, and the
 *  generic toe box is narrow) may relax the margin by this much, mm: it ends up overhanging the outline by at most
 *  MAX_OVERHANG - EDGE_MARGIN, at the largest scale that manages that. */
const MAX_OVERHANG = 6
const STRICT_MIN_SCALE = 0.96
const MAX_SCALE = 1.04
const MIN_SCALE = 0.88
/** Ball of the foot as a fraction of the footprint length from the heel (metatarsal heads). */
const BALL_FRACTION = 0.72
/** Contact patches (heel pad, ball) over which the sole is seated on the insole surface, mm radius. */
const SEAT_RADIUS = 12
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

/** Rigid + uniform-scale placement of the scan: p' = k * Rz(theta) p + (dx, dy). */
interface Placement { k: number; theta: number; dx: number; dy: number }

/** Registers the scan's footprint (xy of the vertices below the ankle, scan units) to the insole outline.
 *  Largest uniform scale k (heel-to-toe length and width both count, since every footprint point must clear the outline
 *  by EDGE_MARGIN) for which some small rotation about z and translation keeps the whole footprint inside; among those,
 *  the placement that maximizes the smallest clearance. */
function register(foot: Float32Array): Placement {
  const field = outlineField()
  const pts: number[] = []
  const stride = Math.max(1, Math.floor(foot.length / 2 / 700))
  for (let i = 0; i < foot.length; i += 2 * stride) pts.push(foot[i], foot[i + 1])
  let minY = Infinity, maxY = -Infinity, sx = 0, n = 0
  for (let i = 0; i < foot.length; i += 2) { minY = Math.min(minY, foot[i + 1]); maxY = Math.max(maxY, foot[i + 1]); sx += foot[i]; n++ }
  const cx = sx / n
  let allow = 0
  /** Smallest outline clearance of the footprint plus `allow` mm of tolerance, bailing out early below `floor`. */
  const clearance = (k: number, th: number, dx: number, dy: number, floor: number) => {
    const c = Math.cos(th) * k, s = Math.sin(th) * k
    let m = Infinity
    for (let i = 0; i < pts.length; i += 2) {
      m = Math.min(m, field.at(pts[i] * c - pts[i + 1] * s + dx, pts[i] * s + pts[i + 1] * c + dy) + allow)
      if (m < floor) return m
    }
    return m
  }
  /** Among placements at scale `p.k` that keep the clearance `floor`, the one with the foot centered along the insole and the
   *  axes aligned (small rotation): the clearance search above only guarantees feasibility, not a sensible spot. */
  const centered = (p: Placement, floor: number): Placement => {
    const toeEdge = field.maxY
    let pick = p, cost = Infinity
    for (let th = p.theta - 0.12; th <= p.theta + 0.12; th += 0.0175)
      for (let dx = p.dx - 12; dx <= p.dx + 12; dx += 1.5)
        for (let dy = p.dy - 20; dy <= p.dy + 20; dy += 1.5) {
          if (clearance(p.k, th, dx, dy, floor) < floor) continue
          const c = Math.cos(th) * p.k, s = Math.sin(th) * p.k
          let lo = Infinity, hi = -Infinity
          for (let i = 0; i < pts.length; i += 2) { const y = pts[i] * s + pts[i + 1] * c + dy; lo = Math.min(lo, y); hi = Math.max(hi, y) }
          const cst = Math.abs(lo - field.minY - (toeEdge - hi)) + 60 * Math.abs(th)
          if (cst < cost) { cost = cst; pick = { k: p.k, theta: th, dx, dy } }
        }
    return pick
  }
  /** Best placement at scale k (maximin clearance), searched coarse then fine around the heel-aligned start. */
  const searchAt = (k: number, floor: number): Placement & { m: number } => {
    let at: Placement & { m: number } = { k, theta: 0, dx: 0, dy: 0, m: -Infinity }
    const dx0 = field.cx - cx * k, dy0 = field.minY + EDGE_MARGIN + 2 - minY * k
    for (let th = -0.26; th <= 0.26 + 1e-9; th += 0.026)
      for (let ddx = -26; ddx <= 26; ddx += 3)
        for (let ddy = -16; ddy <= 40; ddy += 3) {
          const m = clearance(k, th, dx0 + ddx, dy0 + ddy, Math.max(at.m, floor))
          if (m > at.m) at = { k, theta: th, dx: dx0 + ddx, dy: dy0 + ddy, m }
        }
    for (const step of [1, 0.5])
      for (let ddx = -2; ddx <= 2; ddx += step)
        for (let ddy = -2; ddy <= 2; ddy += step)
          for (const dth of [-0.0175, 0, 0.0175]) {
            const m = clearance(k, at.theta + dth, at.dx + ddx, at.dy + ddy, Math.max(at.m, floor))
            if (m > at.m) at = { k, theta: at.theta + dth, dx: at.dx + ddx, dy: at.dy + ddy, m }
          }
    return at
  }
  for (const [pass, from, to] of [[0, MAX_SCALE, STRICT_MIN_SCALE], [MAX_OVERHANG, 1, MIN_SCALE]] as const) {
    allow = pass
    for (let k = from; k >= to - 1e-9; k -= 0.01) {
      const at = searchAt(k, EDGE_MARGIN)
      if (at.m >= EDGE_MARGIN) return centered(at, EDGE_MARGIN)
    }
  }
  allow = MAX_OVERHANG
  return searchAt(MIN_SCALE, -Infinity)
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
  /** Height of the sole above the insole base plane; set by `seat`. */
  seatZ = 3

  private constructor(geo: BufferGeometry) {
    this.geo = geo
    this.rest = (geo.getAttribute("position") as BufferAttribute).array.slice() as Float32Array
    this.fit()
    this.mesh = new Mesh(geo, new MeshStandardMaterial({
      color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.3, roughness: 0.6, metalness: 0, transparent: true, opacity: 0.34, depthWrite: false,
    }))
    this.mesh.renderOrder = 2
    this.mesh.frustumCulled = false
    this.pose({ pitch: 0, pivot: 0, lift: 0 })
  }

  /** Registers the rest pose to the insole outline (once, at construction) and closes the open leg cut into a low dome. */
  private fit(): void {
    const r = this.rest
    const footprint: number[] = []
    // Register the silhouette of the foot below the ankle, not just the sole: the foot flares out above the contact patch.
    for (let i = 0; i < r.length; i += 3) if (r[i + 2] < ANKLE_Z) footprint.push(r[i], r[i + 1])
    const { k, theta, dx, dy } = register(Float32Array.from(footprint))
    const c = Math.cos(theta), s = Math.sin(theta)
    // Leg stub: pinch xy toward the stub's center and compress z, so the open cut at the top closes into a dome.
    let top = 0, cx = 0, cy = 0, maxZ = 0
    for (let i = 0; i < r.length; i += 3) {
      maxZ = Math.max(maxZ, r[i + 2])
      if (r[i + 2] > ANKLE_Z) { cx += r[i]; cy += r[i + 1]; top++ }
    }
    cx /= top; cy /= top
    const sole: number[] = []
    for (let i = 0; i < r.length; i += 3) {
      let x = r[i], y = r[i + 1], z = r[i + 2]
      const isSole = z < SOLE_BAND
      if (z > ANKLE_Z) {
        const t = (z - ANKLE_Z) / (maxZ - ANKLE_Z)
        const pinch = Math.cos((t * Math.PI) / 2) ** 0.6
        x = cx + (x - cx) * pinch
        y = cy + (y - cy) * pinch
        z = ANKLE_Z + ANKLE_CAP * Math.sin((t * Math.PI) / 2)
      }
      r[i] = (x * c - y * s) * k + dx
      r[i + 1] = (x * s + y * c) * k + dy
      r[i + 2] = z * k
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
      let need = 0
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
    this.seatZ = Math.max(patch(xAt(heelC), heelC), patch(xAt(ball), ball))
    this.pose(this.last)
  }

  private last: FootPose = { pitch: 0, pivot: 0, lift: 0 }

  /** Material tones for the page theme: pale glass on dark, soft ink on light. */
  setTone(dark: boolean): void {
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
    return new FootModel(geo)
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
  }
}
