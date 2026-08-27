class_name ProtoMesh
extends RefCounted
## Flat-shaded, faceted mesh builders for the 2.5D visual prototype.
##
## Everything is built from unshared triangles with face normals and per-face
## vertex colours: a deliberate low-poly miniature look, so the dioramas read as
## hand-made physical worlds rather than textured boxes. Deterministic — the
## same seed always builds the same little world.

# --- deterministic noise ----------------------------------------------------

static func hashf(x: int, y: int, seed_v: int) -> float:
    var h := (x * 374761393 + y * 668265263 + seed_v * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)

static func vnoise(x: float, z: float, cell: float, seed_v: int) -> float:
    var fx := x / cell
    var fz := z / cell
    var x0 := int(floor(fx))
    var z0 := int(floor(fz))
    var tx := fx - float(x0)
    var tz := fz - float(z0)
    tx = tx * tx * (3.0 - 2.0 * tx)
    tz = tz * tz * (3.0 - 2.0 * tz)
    var a := hashf(x0, z0, seed_v)
    var b := hashf(x0 + 1, z0, seed_v)
    var c := hashf(x0, z0 + 1, seed_v)
    var d := hashf(x0 + 1, z0 + 1, seed_v)
    return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

# --- core builders ----------------------------------------------------------

## tris: Array of [Vector3, Vector3, Vector3, Color]
static func flat_mesh(tris: Array) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for t in tris:
        var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
        if n.length_squared() < 0.0000001: continue
        n = n.normalized()
        st.set_normal(n); st.set_color(t[3]); st.add_vertex(t[0])
        st.set_normal(n); st.set_color(t[3]); st.add_vertex(t[1])
        st.set_normal(n); st.set_color(t[3]); st.add_vertex(t[2])
    return st.commit()

static func vertex_mat(rough := 0.95) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    # Godot treats vertex colours as LINEAR unless told otherwise, so every
    # sRGB hex written in this file was being over-brightened on the way to the
    # screen — which is why saturated greens kept rendering as pale mint.
    m.vertex_color_is_srgb = true
    m.roughness = rough
    # No specular. A faceted miniature should read by its albedo and its facet
    # normals, not by a highlight that bleaches every saturated colour.
    m.metallic_specular = 0.0
    return m

static func glow_mat(colour: Color, energy := 2.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_is_srgb = true
    m.albedo_color = colour
    m.emission_enabled = true
    m.emission = colour
    m.emission_energy_multiplier = energy
    return m

static func put(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3,
        rot_y := 0.0, scale_v := Vector3.ONE) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    if material != null: mi.material_override = material
    mi.position = pos
    mi.rotation.y = rot_y
    mi.scale = scale_v
    parent.add_child(mi)
    return mi

# --- primitive shapes -------------------------------------------------------

const ICO_T := 1.618034

static func _ico_verts() -> Array:
    var t := ICO_T
    var raw := [
        Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
        Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
        Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
    var out: Array = []
    for v in raw: out.append((v as Vector3).normalized())
    return out

const ICO_FACES := [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]

## An organic faceted lump: foliage, stones, lava rocks, crystal hearts.
static func blob(radius: float, jitter: float, col_a: Color, col_b: Color,
        seed_v: int) -> ArrayMesh:
    var base := _ico_verts()
    var jittered: Dictionary = {}
    var vert := func(v: Vector3, idx: int) -> Vector3:
        if not jittered.has(idx):
            var k := 1.0 + (hashf(idx, seed_v, 7) - 0.5) * 2.0 * jitter
            jittered[idx] = (v as Vector3) * radius * k
        return jittered[idx]
    var mids: Dictionary = {}
    var mid := func(i: int, j: int) -> Array:
        var key := "%d_%d" % [mini(i, j), maxi(i, j)]
        if not mids.has(key):
            var v: Vector3 = ((base[i] as Vector3) + (base[j] as Vector3)).normalized()
            var idx := 100 + mids.size()
            mids[key] = [v, idx]
        return mids[key]
    var tris: Array = []
    var fi := 0
    for f in ICO_FACES:
        var a: Vector3 = base[f[0]]
        var b: Vector3 = base[f[1]]
        var c: Vector3 = base[f[2]]
        var ab: Array = mid.call(f[0], f[1])
        var bc: Array = mid.call(f[1], f[2])
        var ca: Array = mid.call(f[2], f[0])
        var pa: Vector3 = vert.call(a, f[0])
        var pb: Vector3 = vert.call(b, f[1])
        var pc: Vector3 = vert.call(c, f[2])
        var pab: Vector3 = vert.call(ab[0], ab[1])
        var pbc: Vector3 = vert.call(bc[0], bc[1])
        var pca: Vector3 = vert.call(ca[0], ca[1])
        for sub in [[pa, pab, pca], [pb, pbc, pab], [pc, pca, pbc], [pab, pbc, pca]]:
            var col := col_a.lerp(col_b, hashf(fi, seed_v, 13))
            tris.append([sub[0], sub[1], sub[2], col])
            fi += 1
    return flat_mesh(tris)

## A tapered faceted column: trunks, stems, posts, rock shards.
static func prism(sides: int, r_bottom: float, r_top: float, height: float,
        col_a: Color, col_b: Color, seed_v: int, jitter := 0.12) -> ArrayMesh:
    var tris: Array = []
    for i in range(sides):
        var a0 := TAU * float(i) / float(sides)
        var a1 := TAU * float(i + 1) / float(sides)
        var j0 := 1.0 + (hashf(i, seed_v, 3) - 0.5) * jitter
        var j1 := 1.0 + (hashf(i + 1, seed_v, 3) - 0.5) * jitter
        var b0 := Vector3(cos(a0) * r_bottom * j0, 0, sin(a0) * r_bottom * j0)
        var b1 := Vector3(cos(a1) * r_bottom * j1, 0, sin(a1) * r_bottom * j1)
        var t0 := Vector3(cos(a0) * r_top * j0, height, sin(a0) * r_top * j0)
        var t1 := Vector3(cos(a1) * r_top * j1, height, sin(a1) * r_top * j1)
        var col := col_a.lerp(col_b, hashf(i, seed_v, 5))
        tris.append([b0, t0, b1, col])
        tris.append([b1, t0, t1, col])
        if r_top > 0.001:
            tris.append([t0, Vector3(0, height, 0), t1, col_a.lerp(col_b, 0.7)])
    return flat_mesh(tris)

static func cone(sides: int, radius: float, height: float, col_a: Color,
        col_b: Color, seed_v: int) -> ArrayMesh:
    return prism(sides, radius, 0.0, height, col_a, col_b, seed_v, 0.18)

## A cut gemstone: two faceted cones point to point.
static func gem(radius: float, height: float, col_a: Color, col_b: Color,
        seed_v: int) -> ArrayMesh:
    var tris: Array = []
    var sides := 6
    var girdle := height * 0.38
    for i in range(sides):
        var a0 := TAU * float(i) / float(sides)
        var a1 := TAU * float(i + 1) / float(sides)
        var p0 := Vector3(cos(a0) * radius, girdle, sin(a0) * radius)
        var p1 := Vector3(cos(a1) * radius, girdle, sin(a1) * radius)
        var col := col_a.lerp(col_b, hashf(i, seed_v, 3))
        tris.append([p0, Vector3(0, height, 0), p1, col])
        tris.append([p1, Vector3(0, 0, 0), p0, col.lerp(col_b, 0.4)])
    return flat_mesh(tris)

## An irregular flat pool: lava, ponds. Fan of jittered sectors.
static func pool(radius: float, colour: Color, seed_v: int, sectors := 12) -> ArrayMesh:
    var tris: Array = []
    for i in range(sectors):
        var a0 := TAU * float(i) / float(sectors)
        var a1 := TAU * float(i + 1) / float(sectors)
        var r0 := radius * (0.7 + 0.4 * hashf(i, seed_v, 11))
        var r1 := radius * (0.7 + 0.4 * hashf(i + 1, seed_v, 11))
        tris.append([Vector3.ZERO,
            Vector3(cos(a1) * r1, 0, sin(a1) * r1),
            Vector3(cos(a0) * r0, 0, sin(a0) * r0), colour])
    return flat_mesh(tris)

# --- the diorama base -------------------------------------------------------

## An oval faceted island with mounded top and a rocky skirt. `palette` is an
## Array[Color] sampled dark→light by height; `skirt` colours the cut edge.
static func island(width: float, depth: float, height: float, palette: Array,
        skirt: Color, seed_v: int) -> ArrayMesh:
    var rings := 5
    var sectors := 18
    var sx := width * 0.5
    var sz := depth * 0.5
    var pts: Array = []                      # ring -> sector -> Vector3
    for ring in range(rings + 1):
        var frac := float(ring) / float(rings)
        var row: Array = []
        for s in range(sectors):
            var a := TAU * float(s) / float(sectors)
            var edge := 0.84 + 0.16 * hashf(s, seed_v, 17)
            var x := cos(a) * sx * edge * frac
            var z := sin(a) * sz * edge * frac
            var mound := vnoise(x * 2.0 + 9.0, z * 2.0, 0.9, seed_v) * 0.55 \
                + vnoise(x * 5.0, z * 5.0, 0.9, seed_v + 3) * 0.2
            var y := height * (0.80 + mound * 0.12) * (1.0 - frac * frac * 0.34) + height * 0.3
            row.append(Vector3(x, y, z))
        pts.append(row)
    var tris: Array = []
    for ring in range(rings):
        for s in range(sectors):
            var s2 := (s + 1) % sectors
            var a: Vector3 = pts[ring][s]
            var b: Vector3 = pts[ring + 1][s]
            var c: Vector3 = pts[ring + 1][s2]
            var d: Vector3 = pts[ring][s2]
            var t := clampf((b.y + c.y) * 0.5 / (height * 1.3), 0.0, 0.999)
            var idx := int(t * float(palette.size()))
            var col: Color = palette[clampi(idx, 0, palette.size() - 1)]
            col = col.lightened((hashf(ring * 31 + s, seed_v, 23) - 0.5) * 0.14)
            if ring == 0:
                tris.append([a, b, c, col])
            else:
                tris.append([a, b, c, col])
                tris.append([a, c, d, col])
    for s in range(sectors):                 # skirt down to the table
        var s2 := (s + 1) % sectors
        var top_a: Vector3 = pts[rings][s]
        var top_b: Vector3 = pts[rings][s2]
        var bot_a := Vector3(top_a.x * 1.03, -0.02, top_a.z * 1.03)
        var bot_b := Vector3(top_b.x * 1.03, -0.02, top_b.z * 1.03)
        var col := skirt.lightened((hashf(s, seed_v, 29) - 0.5) * 0.16)
        tris.append([top_a, bot_a, bot_b, col])
        tris.append([top_a, bot_b, top_b, col])
    return flat_mesh(tris)

## Approximate surface height of an island built with the same parameters.
static func island_height(x: float, z: float, width: float, depth: float,
        height: float, seed_v: int) -> float:
    var frac := sqrt(pow(x / (width * 0.5), 2.0) + pow(z / (depth * 0.5), 2.0))
    frac = clampf(frac / 0.9, 0.0, 1.0)
    var mound := vnoise(x * 2.0 + 9.0, z * 2.0, 0.9, seed_v) * 0.55 \
        + vnoise(x * 5.0, z * 5.0, 0.9, seed_v + 3) * 0.2
    return height * (0.80 + mound * 0.12) * (1.0 - frac * frac * 0.34) + height * 0.3

# --- glowing crack ribbons (cinder) -----------------------------------------

static func cracks(width: float, depth: float, height: float, seed_v: int,
        count := 4) -> ArrayMesh:
    var tris: Array = []
    var hot := Color(2.2, 0.9, 0.25)         # HDR so the glow blooms
    for k in range(count):
        var x := (hashf(k, seed_v, 31) - 0.5) * width * 0.42
        var z := (hashf(k, seed_v, 37) - 0.5) * depth * 0.42
        var a := hashf(k, seed_v, 41) * TAU
        var steps := 5 + int(hashf(k, seed_v, 43) * 4.0)
        for i in range(steps):
            a += (hashf(k * 9 + i, seed_v, 47) - 0.5) * 1.5
            var nx := x + cos(a) * 0.14
            var nz := z + sin(a) * 0.14
            var y0 := island_height(x, z, width, depth, height, seed_v) + 0.012
            var y1 := island_height(nx, nz, width, depth, height, seed_v) + 0.012
            var side := Vector3(-sin(a), 0, cos(a)) * (0.016 + hashf(i, k, 53) * 0.014)
            var p0 := Vector3(x, y0, z)
            var p1 := Vector3(nx, y1, nz)
            tris.append([p0 - side, p1 - side, p1 + side, hot])
            tris.append([p0 - side, p1 + side, p0 + side, hot])
            x = nx; z = nz
    return flat_mesh(tris)
