// Draws a big rotating ring of small circles: each small circle is made of triangles, and each
// triangle spins on its own. The whole hierarchy is derived procedurally from instance_index + time,
// so the CPU only uploads a tiny uniform and the GPU does all the movement.
//
//   instance_index -> (outer_i in [0,outer_count), mid_i in [0,mid_count))
//   big ring:    outer_i placed around a large circle that rotates over time
//   small circle: mid_i placed around a small circle (centered on the outer node) that rotates
//   triangle:    each triangle also spins about its own center

const TAU = 6.28318530718;

struct Uniforms {
    time: f32,
    outer_count: f32,
    mid_count: f32,
    aspect: f32,
};
@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

fn rotate(p: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

@vertex fn vertex_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> VertexOut {
    var base = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.6),
        vec2<f32>(-0.5, -0.4),
        vec2<f32>( 0.5, -0.4),
    );

    let fi = f32(instance_index);
    let outer_i = floor(fi / u.mid_count);
    let mid_i = fi - outer_i * u.mid_count;

    // Big ring: which small circle, placed around a large circle that slowly rotates.
    let big_angle = u.time * 0.3 + (outer_i / u.outer_count) * TAU;
    let center_big = vec2<f32>(cos(big_angle), sin(big_angle)) * 0.66;

    // Small circle: triangle position around the small circle, which rotates (alternating
    // direction per node for visual interest).
    let even = outer_i - 2.0 * floor(outer_i * 0.5); // outer_i mod 2 -> 0 or 1
    let dir = 1.0 - 2.0 * even;                       // +1 for even nodes, -1 for odd
    let small_angle = u.time * 1.4 * dir + (mid_i / u.mid_count) * TAU;
    let center_small = center_big + vec2<f32>(cos(small_angle), sin(small_angle)) * 0.13;

    // Each triangle spins about its own center.
    let spin = u.time * 3.5 + fi * 0.6;
    let p = rotate(base[vertex_index] * 0.04, spin);

    var pos = p + center_small;
    pos.x = pos.x / u.aspect; // keep triangles from stretching on wide windows

    var out: VertexOut;
    out.position = vec4<f32>(pos, 0.0, 1.0);
    // Keep colors varied by instance but always somewhat dark (each channel in ~[0.08, 0.38]).
    out.color = vec4<f32>(
        0.08 + 0.30 * (0.5 + 0.5 * sin(fi * 0.13 + 0.0)),
        0.08 + 0.30 * (0.5 + 0.5 * sin(fi * 0.13 + 2.0)),
        0.08 + 0.30 * (0.5 + 0.5 * sin(fi * 0.13 + 4.0)),
        1.0,
    );
    return out;
}

@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    return in.color;
}
