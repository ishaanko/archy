import {
  AmbientLight, BufferAttribute, BufferGeometry, DataTexture, DirectionalLight, InstancedMesh, Line, LineBasicMaterial,
  LinearFilter, Matrix4, Mesh, MeshBasicMaterial, MeshStandardMaterial, PerspectiveCamera, RGBAFormat, Scene,
  SphereGeometry, SRGBColorSpace, UnsignedByteType, WebGLRenderer,
} from "three"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { createHeatmapImage, paintHeatmap, type ColormapName, type HeatmapImage } from "../core/colormap"
import type { InsoleMesh } from "../core/insole"
import { sampleGrid, type Grid } from "../core/pressure"
import type { Point } from "../core/types"

const TERRAIN_MM = 18 // displacement at full-scale pressure

export interface FieldStyle {
  map: Float32Array
  vmax: number
  colormap: ColormapName
  patterns: boolean
  diverging: boolean
  terrain: boolean
}

/** three.js scene for the insole: heatmap texture, optional pressure terrain, sensor points and CoP trail.
 *  Renders only when `render()` is called; `onChange` fires when the camera moves so the host can schedule a frame. */
export class InsoleScene {
  private renderer: WebGLRenderer
  private camera = new PerspectiveCamera(35, 1, 10, 3000)
  private scene = new Scene()
  readonly controls: OrbitControls
  private mesh: Mesh | null = null
  private mesh0: InsoleMesh | null = null
  private baseZ = new Float32Array(0)
  private grid: Grid | null = null
  private img: HeatmapImage | null = null
  private texture: DataTexture | null = null
  private material = new MeshStandardMaterial({ roughness: 0.8, metalness: 0 })
  private sensorMesh = new InstancedMesh(new SphereGeometry(1.2, 10, 8), new MeshBasicMaterial({ color: 0xffffff }), 48)
  private sensors: readonly Point[] = []
  private trail = new Line(new BufferGeometry(), new LineBasicMaterial({ color: 0xffffff }))
  private marker = new Mesh(new SphereGeometry(3, 12, 8), new MeshBasicMaterial({ color: 0xffffff }))
  private tmp = new Matrix4()

  constructor(canvas: HTMLCanvasElement, onChange: () => void) {
    this.renderer = new WebGLRenderer({ canvas, antialias: true })
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
    this.renderer.setClearColor(0x000000, 1)
    this.camera.up.set(0, 0, 1)
    this.camera.position.set(3, -210, 270)
    this.controls = new OrbitControls(this.camera, canvas)
    this.controls.target.set(3, 110, 4)
    this.controls.enableDamping = true
    this.controls.addEventListener("change", onChange)
    this.controls.update()
    this.scene.add(new AmbientLight(0xffffff, 1.1))
    const sun = new DirectionalLight(0xffffff, 1.6)
    sun.position.set(-150, -100, 300)
    this.scene.add(sun, this.sensorMesh, this.trail, this.marker)
    this.trail.frustumCulled = false
    this.sensorMesh.frustumCulled = false
    this.material.emissive.set(0xffffff)
    this.material.emissiveIntensity = 0.4
  }

  /** Resizes the drawing buffer to the canvas' CSS size. */
  resize(): void {
    const c = this.renderer.domElement
    this.renderer.setSize(c.clientWidth, c.clientHeight, false)
    this.camera.aspect = c.clientWidth / Math.max(1, c.clientHeight)
    this.camera.updateProjectionMatrix()
  }

  /** Replaces the insole geometry. */
  setInsole(insole: InsoleMesh, grid: Grid, sensors: readonly Point[]): void {
    if (this.mesh) {
      this.scene.remove(this.mesh)
      this.mesh.geometry.dispose()
    }
    this.mesh0 = insole
    this.grid = grid
    this.sensors = sensors
    this.img = createHeatmapImage(grid)
    this.texture?.dispose()
    this.texture = new DataTexture(new Uint8Array(this.img.data.buffer), this.img.width, this.img.height, RGBAFormat, UnsignedByteType)
    this.texture.colorSpace = SRGBColorSpace
    this.texture.magFilter = this.texture.minFilter = LinearFilter
    this.texture.generateMipmaps = false
    this.material.map = this.material.emissiveMap = this.texture
    this.material.needsUpdate = true

    const geo = new BufferGeometry()
    geo.setAttribute("position", new BufferAttribute(insole.positions.slice(), 3))
    const uv = new Float32Array(insole.topCount * 2 * 2)
    const w = grid.nx * grid.cell, h = grid.ny * grid.cell
    for (let i = 0; i < insole.topCount; i++) {
      const x = insole.topXY[i * 2], y = insole.topXY[i * 2 + 1]
      uv.set([(x - grid.x0) / w, (y - grid.y0) / h], i * 2)
      uv.set([(x - grid.x0) / w, (y - grid.y0) / h], (insole.topCount + i) * 2)
    }
    geo.setAttribute("uv", new BufferAttribute(uv, 2))
    geo.setIndex(new BufferAttribute(insole.indices, 1))
    geo.addGroup(0, insole.topTriangles * 3, 0)
    geo.addGroup(insole.topTriangles * 3, insole.indices.length - insole.topTriangles * 3, 1)
    geo.computeVertexNormals()
    this.baseZ = new Float32Array(insole.topCount)
    for (let i = 0; i < insole.topCount; i++) this.baseZ[i] = insole.positions[i * 3 + 2]
    this.mesh = new Mesh(geo, [this.material, new MeshStandardMaterial({ color: 0x3a3a3a, roughness: 0.9 })])
    this.scene.add(this.mesh)
  }

  /** Repaints the heatmap texture and (in terrain mode) displaces the surface. */
  setField(f: FieldStyle): void {
    if (!this.mesh || !this.mesh0 || !this.grid || !this.img || !this.texture) return
    paintHeatmap(this.img, this.grid, f.map, f.vmax, f.colormap, f.patterns, f.diverging)
    this.texture.needsUpdate = true
    const pos = this.mesh.geometry.getAttribute("position") as BufferAttribute
    const amp = f.diverging ? TERRAIN_MM / 2 : TERRAIN_MM
    for (let i = 0; i < this.mesh0.topCount; i++) {
      const d = f.terrain ? (sampleGrid(this.grid, f.map, this.mesh0.topXY[i * 2], this.mesh0.topXY[i * 2 + 1]) / f.vmax) * amp * this.mesh0.rimFade[i] : 0
      pos.setZ(i, Math.max(0.5, this.baseZ[i] + d))
    }
    pos.needsUpdate = true
    if (f.terrain || this.terrainWas) this.mesh.geometry.computeVertexNormals()
    this.terrainWas = f.terrain
    this.lift = (x, y) => (f.terrain ? (sampleGrid(this.grid!, f.map, x, y) / f.vmax) * amp : 0)
  }
  private terrainWas = false
  private lift: (x: number, y: number) => number = () => 0

  /** Sensor spheres on/off; positions follow the surface. */
  setSensorsVisible(on: boolean): void {
    this.sensorMesh.visible = on
    if (!on || !this.mesh0) return
    this.sensors.forEach((s, i) => {
      this.tmp.makeTranslation(s.x, s.y, this.mesh0!.heightAt(s.x, s.y) + this.lift(s.x, s.y) + 1.5)
      this.sensorMesh.setMatrixAt(i, this.tmp)
    })
    this.sensorMesh.count = this.sensors.length
    this.sensorMesh.instanceMatrix.needsUpdate = true
  }

  /** CoP trail up to `upTo` frames (cop = [x, y, ...], NaN = no load) and a marker at the latest point. */
  setCop(cop: Float32Array, upTo: number, visible: boolean): void {
    this.trail.visible = this.marker.visible = visible
    if (!visible || !this.mesh0) return
    const pts: number[] = []
    let last: [number, number] | null = null
    for (let f = 0; f < upTo; f++) {
      const x = cop[f * 2], y = cop[f * 2 + 1]
      if (Number.isNaN(x)) continue
      pts.push(x, y, this.mesh0.heightAt(x, y) + this.lift(x, y) + 2)
      last = [x, y]
    }
    this.trail.geometry.setAttribute("position", new BufferAttribute(new Float32Array(pts), 3))
    this.marker.visible = last !== null
    if (last) this.marker.position.set(last[0], last[1], this.mesh0.heightAt(...last) + this.lift(...last) + 2)
  }

  /** Orbits the camera around the target by (dAzimuth, dPolar) radians, or zooms by `zoom` (>1 = farther). */
  nudge(dAzimuth: number, dPolar: number, zoom = 1): void {
    const off = this.camera.position.clone().sub(this.controls.target)
    const r = off.length() * zoom
    let polar = Math.acos(off.z / off.length()) + dPolar
    polar = Math.min(Math.PI - 0.05, Math.max(0.05, polar))
    const az = Math.atan2(off.y, off.x) + dAzimuth
    this.camera.position.set(
      this.controls.target.x + r * Math.sin(polar) * Math.cos(az),
      this.controls.target.y + r * Math.sin(polar) * Math.sin(az),
      this.controls.target.z + r * Math.cos(polar),
    )
    this.controls.update()
  }

  /** Draws one frame. Returns true while camera damping still needs more frames. */
  render(): boolean {
    const moving = this.controls.update()
    this.renderer.render(this.scene, this.camera)
    return moving
  }
}
