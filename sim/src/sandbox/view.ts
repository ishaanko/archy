import {
  AmbientLight, BoxGeometry, BufferAttribute, BufferGeometry, CatmullRomCurve3, CylinderGeometry, DataTexture, DirectionalLight,
  InstancedMesh, LinearFilter, Matrix4, Mesh, MeshBasicMaterial, MeshStandardMaterial, PerspectiveCamera, Raycaster,
  RGBAFormat, RingGeometry, Scene, Group, SRGBColorSpace, TubeGeometry, UnsignedByteType, Vector2, Vector3, WebGLRenderer,
  type Material,
} from "three"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { createHeatmapImage, paintHeatmap, type ColormapName, type HeatmapImage } from "../core/colormap"
import type { FootPose } from "../core/gait"
import { buildInsole, type InsoleMesh } from "../core/insole"
import { inside } from "../core/outline"
import type { Grid } from "../core/pressure"
import type { Point } from "../core/types"
import { FootModel } from "../view/foot"

/** Okabe-Ito colors (colorblind-safe), used to tell sensors and their wires apart. */
export const SENSOR_COLORS = ["#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7", "#FFFFFF"] as const

const BOARD_CENTER = new Vector3(3, -52, 0)
const BOARD_LENGTH = 45, BOARD_WIDTH = 18, PCB = 1.6, HEADER = 2.5, PIN_TIP = 5.5
const PIN_PITCH = 2.54
const FOOT_ROLL_RAD = 0.14 // foot tilt at full roll
const Z = new Vector3(0, 0, 1)

export interface SensorVis extends Point {
  color: string
}

/** Where wire `index` meets the board header (the row facing the insole). */
function pinPosition(index: number): Vector3 {
  const k = index % 15
  return new Vector3(BOARD_CENTER.x - 7 * PIN_PITCH + k * PIN_PITCH, BOARD_CENTER.y + BOARD_WIDTH / 2 - PIN_PITCH / 2, PIN_TIP)
}

/** three.js scene of the sandbox: insole with heatmap, FSR discs, wires, Arduino Nano model, optional scanned foot, press marker.
 *  Renders on demand: call `render()`; it returns true while camera damping needs more frames. */
export class SandboxScene {
  readonly controls: OrbitControls
  private renderer: WebGLRenderer
  private camera = new PerspectiveCamera(35, 1, 10, 3000)
  private scene = new Scene()
  private insole: InsoleMesh
  private insoleMesh: Mesh
  private img: HeatmapImage
  private tex: DataTexture
  private discs = new Group()
  private wires = new Group()
  private pcb = new MeshStandardMaterial({ color: 0x124a63, roughness: 0.6 })
  private marker = new Group()
  private foot: FootModel | null = null
  private footCache = new Map<string, Promise<FootModel>>()
  private footVisible = true
  private footRoll = 0
  private raycaster = new Raycaster()
  private shared = {
    base: new CylinderGeometry(9.15, 9.15, 0.5, 32).rotateX(Math.PI / 2),
    pad: new CylinderGeometry(6.35, 6.35, 0.2, 32).rotateX(Math.PI / 2),
    rim: new RingGeometry(5.3, 6.35, 40),
    halo: new RingGeometry(10.5, 11.8, 40),
  }
  private baseMat = new MeshStandardMaterial({ color: 0x1c1c1c, roughness: 0.7 })
  private padMat = new MeshStandardMaterial({ color: 0x3b3b3b, roughness: 0.5 })
  private haloMat = new MeshBasicMaterial({ color: 0xffffff })
  private rimMats = new Map<string, MeshBasicMaterial>()

  constructor(private canvas: HTMLCanvasElement, grid: Grid, private outline: readonly Point[], onChange: () => void) {
    this.renderer = new WebGLRenderer({ canvas, antialias: true })
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
    this.renderer.setClearColor(0x000000, 1)
    this.camera.up.set(0, 0, 1)
    this.controls = new OrbitControls(this.camera, canvas)
    this.controls.enableDamping = true
    this.controls.addEventListener("change", onChange)
    this.setCamera("3d")

    this.scene.add(new AmbientLight(0xffffff, 1.1))
    const sun = new DirectionalLight(0xffffff, 1.6)
    sun.position.set(-150, -100, 300)
    this.scene.add(sun, this.discs, this.wires, this.buildBoard(), this.marker)

    // Insole shell with the heatmap texture on its top face.
    this.insole = buildInsole(outline, grid, new Float32Array(grid.nx * grid.ny), null)
    this.img = createHeatmapImage(grid)
    this.tex = new DataTexture(new Uint8Array(this.img.data.buffer), this.img.width, this.img.height, RGBAFormat, UnsignedByteType)
    this.tex.colorSpace = SRGBColorSpace
    this.tex.magFilter = this.tex.minFilter = LinearFilter
    this.tex.generateMipmaps = false
    const top = new MeshStandardMaterial({ roughness: 0.8, metalness: 0, map: this.tex, emissiveMap: this.tex, emissive: 0xffffff, emissiveIntensity: 0.4 })
    const geo = new BufferGeometry()
    const ins = this.insole
    geo.setAttribute("position", new BufferAttribute(ins.positions.slice(), 3))
    const uv = new Float32Array(ins.topCount * 4)
    const w = grid.nx * grid.cell, h = grid.ny * grid.cell
    for (let i = 0; i < ins.topCount; i++) {
      const u = (ins.topXY[i * 2] - grid.x0) / w, v = (ins.topXY[i * 2 + 1] - grid.y0) / h
      uv.set([u, v], i * 2)
      uv.set([u, v], (ins.topCount + i) * 2)
    }
    geo.setAttribute("uv", new BufferAttribute(uv, 2))
    geo.setIndex(new BufferAttribute(ins.indices, 1))
    geo.addGroup(0, ins.topTriangles * 3, 0)
    geo.addGroup(ins.topTriangles * 3, ins.indices.length - ins.topTriangles * 3, 1)
    geo.computeVertexNormals()
    this.insoleMesh = new Mesh(geo, [top, new MeshStandardMaterial({ color: 0x3a3a3a, roughness: 0.9 })])
    this.scene.add(this.insoleMesh)

    // Press marker: ring on the surface plus a thin stem.
    const ringMat = new MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.9 })
    this.marker.add(new Mesh(new RingGeometry(0.88, 1, 48), ringMat), new Mesh(new CylinderGeometry(0.6, 0.6, 24, 8).rotateX(Math.PI / 2).translate(0, 0, 12), ringMat))
    this.marker.visible = false
    this.marker.renderOrder = 5
  }

  /** Arduino Nano-like board (PCB, USB port, chip, two header rows) at the heel end of the insole. */
  private buildBoard(): Group {
    const g = new Group()
    g.position.copy(BOARD_CENTER)
    const box = (w: number, d: number, h: number, mat: Material, x: number, y: number, z: number) => {
      const m = new Mesh(new BoxGeometry(w, d, h), mat)
      m.position.set(x, y, z)
      g.add(m)
    }
    box(BOARD_LENGTH, BOARD_WIDTH, PCB, this.pcb, 0, 0, PCB / 2)
    box(9, 7.6, 3, new MeshStandardMaterial({ color: 0xb8b8b8, metalness: 0.6, roughness: 0.4 }), -BOARD_LENGTH / 2 + 2, 0, PCB + 1.5)
    box(8, 8, 1.2, new MeshStandardMaterial({ color: 0x111111, roughness: 0.5 }), 5, 0, PCB + 0.6)
    const plastic = new MeshStandardMaterial({ color: 0x151515, roughness: 0.6 })
    const gold = new MeshStandardMaterial({ color: 0xd4af37, metalness: 0.8, roughness: 0.35 })
    const pins = new InstancedMesh(new BoxGeometry(0.64, 0.64, PIN_TIP - PCB), gold, 30)
    const m = new Matrix4()
    let n = 0
    for (const side of [-1, 1]) {
      const y = side * (BOARD_WIDTH / 2 - PIN_PITCH / 2)
      box(15 * PIN_PITCH, PIN_PITCH, HEADER, plastic, 0, y, PCB + HEADER / 2)
      for (let k = 0; k < 15; k++) {
        m.makeTranslation(-7 * PIN_PITCH + k * PIN_PITCH, y, PCB + (PIN_TIP - PCB) / 2)
        pins.setMatrixAt(n++, m)
      }
    }
    g.add(pins)
    return g
  }

  setBoard(isEsp: boolean): void {
    this.pcb.color.set(isEsp ? 0x1d1d1d : 0x124a63)
  }

  /** Board center on screen for its label. */
  boardAnchor(): Vector3 {
    return new Vector3(BOARD_CENTER.x, BOARD_CENTER.y, 12)
  }

  resize(): void {
    const c = this.canvas
    this.renderer.setSize(c.clientWidth, c.clientHeight, false)
    this.camera.aspect = c.clientWidth / Math.max(1, c.clientHeight)
    this.camera.updateProjectionMatrix()
  }

  setCamera(view: "3d" | "top"): void {
    if (view === "top") {
      this.camera.position.set(3, 90, 460)
      this.controls.target.set(3, 92, 0)
    } else {
      this.camera.position.set(240, -200, 230)
      this.controls.target.set(0, 85, 25)
    }
    this.controls.update()
  }

  /** Surface height of the insole at (x, y), mm. */
  heightAt(x: number, y: number): number {
    return this.insole.heightAt(x, y)
  }

  /** Repaints the insole heatmap texture. */
  paint(grid: Grid, map: Float32Array, vmax: number, cmap: ColormapName): void {
    paintHeatmap(this.img, grid, map, vmax, cmap, false)
    this.tex.needsUpdate = true
  }

  /** Screen position (CSS px within the canvas) of a world point, or null when behind the camera. */
  screenOf(p: Vector3): { x: number; y: number } | null {
    const v = p.clone().project(this.camera)
    if (v.z > 1) return null
    return { x: ((v.x + 1) / 2) * this.canvas.clientWidth, y: ((1 - v.y) / 2) * this.canvas.clientHeight }
  }

  /** World position on top of the insole for an (x, y) in the foot frame. */
  surfacePoint(x: number, y: number, lift = 0): Vector3 {
    return new Vector3(x, y, this.insole.heightAt(x, y) + lift)
  }

  /** Foot-frame point under a pointer, or null when the pointer is not over the insole. */
  pickInsole(clientX: number, clientY: number): Point | null {
    const r = this.canvas.getBoundingClientRect()
    this.raycaster.setFromCamera(new Vector2(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1), this.camera)
    const hit = this.raycaster.intersectObject(this.insoleMesh)[0]
    return hit && hit.point.z > 0.4 ? { x: hit.point.x, y: hit.point.y } : null
  }

  /** Discs lying on the insole (tilted to the surface) with a colored active-area ring; the selected one gets a halo. */
  setSensors(list: readonly SensorVis[], selected: number | null): void {
    this.discs.clear()
    list.forEach((s, i) => {
      const g = new Group()
      const hx = this.insole.heightAt(s.x + 2, s.y) - this.insole.heightAt(s.x - 2, s.y)
      const hy = this.insole.heightAt(s.x, s.y + 2) - this.insole.heightAt(s.x, s.y - 2)
      g.quaternion.setFromUnitVectors(Z, new Vector3(-hx / 4, -hy / 4, 1).normalize())
      g.position.copy(this.surfacePoint(s.x, s.y, 0.2))
      let rim = this.rimMats.get(s.color)
      if (!rim) this.rimMats.set(s.color, (rim = new MeshBasicMaterial({ color: s.color })))
      const base = new Mesh(this.shared.base, this.baseMat)
      base.position.z = 0.25
      const pad = new Mesh(this.shared.pad, this.padMat)
      pad.position.z = 0.6
      const ring = new Mesh(this.shared.rim, rim)
      ring.position.z = 0.75
      g.add(base, pad, ring)
      if (i === selected) {
        const halo = new Mesh(this.shared.halo, this.haloMat)
        halo.position.z = 0.4
        g.add(halo)
      }
      this.discs.add(g)
    })
    this.rebuildWires(list)
  }

  /** Thin tubes from each sensor over the insole surface to its header pin on the board. */
  private rebuildWires(list: readonly SensorVis[]): void {
    for (const c of this.wires.children) (c as Mesh).geometry.dispose()
    this.wires.clear()
    const outline = this.outline
    list.forEach((s, i) => {
      const pin = pinPosition(i)
      const N = 28
      const pts: Vector3[] = []
      let lastIn = 0
      for (let k = 0; k <= N; k++) {
        const u = k / N
        const x = s.x + (pin.x - s.x) * u, y = s.y + (pin.y - s.y) * u
        if (inside(outline, x, y)) {
          lastIn = k
          pts.push(new Vector3(x, y, this.insole.heightAt(x, y) + 0.5))
        } else pts.push(new Vector3(x, y, 0))
      }
      // Off the insole the wire descends from the edge to the header pin.
      const z0 = pts[lastIn].z
      for (let k = lastIn + 1; k <= N; k++) pts[k].z = z0 + (pin.z - z0) * ((k - lastIn) / (N - lastIn))
      const tube = new Mesh(new TubeGeometry(new CatmullRomCurve3(pts), 40, 0.55, 5), new MeshBasicMaterial({ color: s.color }))
      this.wires.add(tube)
    })
  }

  /** Fingertip marker on the surface (null hides it). */
  setPress(p: (Point & { radius: number }) | null): void {
    this.marker.visible = p !== null
    if (!p) return
    this.marker.position.copy(this.surfacePoint(p.x, p.y, 0.8))
    this.marker.scale.set(p.radius, p.radius, 1)
    this.marker.children[1].scale.set(1 / p.radius, 1 / p.radius, 1)
  }

  /** Shows the scanned foot at `url` (loaded once per url). */
  async setFoot(url: string): Promise<void> {
    let p = this.footCache.get(url)
    if (!p) this.footCache.set(url, (p = FootModel.load(url)))
    const next = await p
    if (this.foot === next) return
    if (this.foot) this.scene.remove(this.foot.mesh)
    this.foot = next
    next.opacity = 0.2
    next.mesh.visible = this.footVisible
    this.scene.add(next.mesh)
    this.poseFoot(this.lastPose, this.footRoll)
  }
  private lastPose: FootPose = { pitch: 0, pivotY: 0, lift: 0 }

  setFootVisible(on: boolean): void {
    this.footVisible = on
    if (this.foot) this.foot.mesh.visible = on
  }

  /** Pitch/lift from the gait pose, plus roll (-1 pronation .. 1 supination) about the foot's long axis. */
  poseFoot(pose: FootPose, roll: number): void {
    this.lastPose = pose
    this.footRoll = roll
    if (!this.foot) return
    this.foot.pose(pose)
    // Pronation lowers the medial (+x) side.
    const m = this.foot.mesh
    const pivot = new Vector3(5, 0, 3)
    m.quaternion.setFromAxisAngle(new Vector3(0, 1, 0), -roll * FOOT_ROLL_RAD)
    m.position.copy(pivot).sub(pivot.clone().applyQuaternion(m.quaternion))
  }

  render(): boolean {
    const moving = this.controls.update()
    this.renderer.render(this.scene, this.camera)
    return moving
  }
}
