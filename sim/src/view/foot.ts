import { BufferAttribute, Mesh, MeshStandardMaterial, type BufferGeometry } from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import type { FootPose } from "../core/gait"
import { footOutline } from "../core/outline"

/** Height of the foot sole above z = 0 (top of the insole base), mm. */
const REST_Z = 3
const TOE_HINGE = [-10, 25] as const // mm around the pivot over which the toes bend back flat during push-off

/** Fits the scan to the generic insole outline: foot length is FIT_LENGTH of the insole length, centered across it,
 *  heel inset from the insole's heel edge. Scans are about 251 mm with a 85 mm leg stub, so the open cut is closed into a low dome instead of a boot shaft. */
const FIT_LENGTH = 0.93
const HEEL_INSET = 8 // mm
const ANKLE_Z = 35 // mm (rest frame, scan units) above which the leg stub is domed over
const ANKLE_CAP = 22 // mm (scan units) the domed leg may rise above ANKLE_Z

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** A scanned foot (GLB in the canonical frame: sole on z = 0, y heel -> toe) that can be posed through a step.
 *  Posing rewrites vertex positions on the CPU (about 10k vertices): rotation about the pivot, with the toes
 *  held flat during push-off so they do not sink through the floor. */
export class FootModel {
  readonly mesh: Mesh
  private rest: Float32Array
  private geo: BufferGeometry

  private constructor(geo: BufferGeometry) {
    this.geo = geo
    this.rest = (geo.getAttribute("position") as BufferAttribute).array.slice() as Float32Array
    this.fit()
    this.mesh = new Mesh(geo, new MeshStandardMaterial({
      color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.3, roughness: 0.6, metalness: 0, transparent: true, opacity: 0.34, depthWrite: false,
    }))
    this.mesh.renderOrder = 2
    this.mesh.frustumCulled = false
    this.pose({ pitch: 0, pivotY: 0, lift: 0 })
  }

  /** Scales, centers and trims the rest pose in place (once, at construction). */
  private fit(): void {
    const o = footOutline()
    const ys = o.map((p) => p.y), xs = o.map((p) => p.x)
    const insoleMinY = Math.min(...ys), insoleLen = Math.max(...ys) - insoleMinY
    const insoleCx = (Math.min(...xs) + Math.max(...xs)) / 2
    const r = this.rest
    let minY = Infinity, maxY = -Infinity, minX = Infinity, maxX = -Infinity
    for (let i = 0; i < r.length; i += 3) {
      minX = Math.min(minX, r[i]); maxX = Math.max(maxX, r[i])
      minY = Math.min(minY, r[i + 1]); maxY = Math.max(maxY, r[i + 1])
    }
    const k = (FIT_LENGTH * insoleLen) / (maxY - minY)
    const dx = insoleCx - ((minX + maxX) / 2) * k
    const dy = insoleMinY + HEEL_INSET - minY * k
    // Leg stub: pinch xy toward the stub's center and compress z, so the open cut at the top closes into a dome.
    let top = 0, cx = 0, cy = 0, maxZ = 0
    for (let i = 0; i < r.length; i += 3) {
      maxZ = Math.max(maxZ, r[i + 2])
      if (r[i + 2] > ANKLE_Z) { cx += r[i]; cy += r[i + 1]; top++ }
    }
    cx /= top; cy /= top
    for (let i = 0; i < r.length; i += 3) {
      let x = r[i], y = r[i + 1], z = r[i + 2]
      if (z > ANKLE_Z) {
        const t = (z - ANKLE_Z) / (maxZ - ANKLE_Z)
        const pinch = Math.cos((t * Math.PI) / 2) ** 0.6
        x = cx + (x - cx) * pinch
        y = cy + (y - cy) * pinch
        z = ANKLE_Z + ANKLE_CAP * Math.sin((t * Math.PI) / 2)
      }
      r[i] = x * k + dx
      r[i + 1] = y * k + dy
      r[i + 2] = z * k
    }
  }

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

  pose({ pitch, pivotY, lift }: FootPose): void {
    const pos = this.geo.getAttribute("position") as BufferAttribute
    const a = pos.array as Float32Array
    for (let i = 0; i < a.length; i += 3) {
      const x = this.rest[i], y = this.rest[i + 1], z = this.rest[i + 2]
      const th = pitch < 0 ? pitch * (1 - smooth(pivotY + TOE_HINGE[0], pivotY + TOE_HINGE[1], y)) : pitch
      const c = Math.cos(th), s = Math.sin(th)
      const dy = y - pivotY
      a[i] = x
      a[i + 1] = pivotY + dy * c - z * s
      a[i + 2] = REST_Z + lift + dy * s + z * c
    }
    pos.needsUpdate = true
    this.geo.computeVertexNormals()
  }
}
