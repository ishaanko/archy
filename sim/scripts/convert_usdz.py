# Textured foot for the "Realistic" toggle: iPhone Object Capture USDZ -> GLB in the STL's coordinates.
#   uv run --with usd-core --with trimesh --with pillow --with numpy python -I scripts/convert_usdz.py <scan.usdz> <out.glb>
# The scanning app's STL export is the same mesh as the USDZ, scaled to mm and turned Z-up: stl = 1000 * (x, -z, y).
# Writing the GLB in those coordinates lets the app place it with the transform it already computed for the STL
# (ScanResult.toCanonical). Only the color texture is kept, re-encoded as a 2048 px JPEG.
import io
import sys
import zipfile

import numpy as np
import trimesh
from PIL import Image
from pxr import Usd, UsdGeom

src, out = sys.argv[1], sys.argv[2]
stage = Usd.Stage.Open(src)
prim = next(p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
mesh = UsdGeom.Mesh(prim)
scale = UsdGeom.GetStageMetersPerUnit(stage) * 1000
pts = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64) * scale
xf = np.array(UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default()))
assert np.allclose(xf, np.eye(4)), "mesh has a transform; apply it first"
counts = np.array(mesh.GetFaceVertexCountsAttr().Get())
assert (counts == 3).all(), "expected triangles only"
corners = np.array(mesh.GetFaceVertexIndicesAttr().Get())
st = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
assert st.GetInterpolation() == "faceVarying"
uv_corner = np.array(st.ComputeFlattened(), dtype=np.float64)

# One vertex per (point, uv) pair, so seams split but smooth shading survives elsewhere.
keys = np.c_[corners, np.round(uv_corner * 1e6)]
uniq, faces = np.unique(keys, axis=0, return_inverse=True)
p = pts[uniq[:, 0].astype(int)]
uv = uniq[:, 1:] / 1e6
verts = np.c_[p[:, 0], -p[:, 2], p[:, 1]]

with zipfile.ZipFile(src) as z:
    tex_name = next(n for n in z.namelist() if n.endswith("_tex0.png"))
    img = Image.open(io.BytesIO(z.read(tex_name))).convert("RGB")
img.thumbnail((2048, 2048))
buf = io.BytesIO()
img.save(buf, "JPEG", quality=85)
img = Image.open(buf)

tm = trimesh.Trimesh(verts, faces.reshape(-1, 3), process=False,
                     visual=trimesh.visual.TextureVisuals(uv=uv, image=img))
tm.export(out)
print(out, len(verts), "vertices", len(tm.faces), "faces", "bbox", verts.min(0).round(1), verts.max(0).round(1))
