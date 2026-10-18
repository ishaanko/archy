import type { InsoleMesh } from "./insole"

/** Binary STL (mm) for the mesh. */
export function toBinaryStl(mesh: Pick<InsoleMesh, "positions" | "indices">): ArrayBuffer {
  const n = mesh.indices.length / 3
  const buf = new ArrayBuffer(84 + n * 50)
  const view = new DataView(buf)
  new TextEncoder().encodeInto("insole-sim binary STL, mm", new Uint8Array(buf, 0, 80))
  view.setUint32(80, n, true)
  const p = mesh.positions
  for (let t = 0; t < n; t++) {
    const [a, b, c] = [mesh.indices[t * 3] * 3, mesh.indices[t * 3 + 1] * 3, mesh.indices[t * 3 + 2] * 3]
    const ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2]
    const vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2]
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
    const len = Math.hypot(nx, ny, nz) || 1
    nx /= len; ny /= len; nz /= len
    const o = 84 + t * 50
    ;[nx, ny, nz, p[a], p[a + 1], p[a + 2], p[b], p[b + 1], p[b + 2], p[c], p[c + 1], p[c + 2]].forEach((f, k) => view.setFloat32(o + k * 4, f, true))
  }
  return buf
}
