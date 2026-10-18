import { BufferAttribute, Mesh, MeshStandardMaterial, type BufferGeometry } from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import type { FootPose } from "../core/gait"

/** Height of the foot sole above z = 0 (top of the insole base), mm. */
const REST_Z = 3
const TOE_HINGE = [-10, 25] as const // mm around the pivot over which the toes bend back flat during push-off

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
    this.mesh = new Mesh(geo, new MeshStandardMaterial({
      color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.3, roughness: 0.6, metalness: 0, transparent: true, opacity: 0.34, depthWrite: false,
    }))
    this.mesh.renderOrder = 2
    this.mesh.frustumCulled = false
    this.pose({ pitch: 0, pivotY: 0, lift: 0 })
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
