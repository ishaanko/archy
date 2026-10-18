import { connectDemoDevice, SENSOR_NAMES } from "../../sim/src/hardware/index"
for (const type of ["flat", "normal", "high arch"] as const) {
  const d = connectDemoDevice("left", type)
  let n = 0
  const max = new Float32Array(6)
  d.onFrame((k) => { n++; k.forEach((v, i) => { if (v > max[i]) max[i] = v }) })
  await new Promise((r) => setTimeout(r, 2000))
  await d.disconnect()
  console.log(type, "frames", n, SENSOR_NAMES.map((s, i) => `${s}=${max[i].toFixed(0)}`).join(" "))
}
