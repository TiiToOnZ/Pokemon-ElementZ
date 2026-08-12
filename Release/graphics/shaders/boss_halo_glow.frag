uniform sampler2D texture;
uniform vec2 resolution;
uniform vec2 cellSize;
uniform float glowIntensity;

void main() {
  vec2 uv = gl_TexCoord[0].xy;
  vec2 px = vec2(1.0 / resolution.x, 1.0 / resolution.y);

  // Compute current cell bounds to avoid sampling into adjacent frames
  vec2 cellMin = floor(uv / cellSize) * cellSize;
  vec2 cellMax = cellMin + cellSize;

  vec4 original = texture2D(texture, uv);

  // Multi-sample blur for glow: 3 rings x 8 directions = 24 samples
  vec4 glow = vec4(0.0);
  float totalWeight = 0.0;

  for (int i = 0; i < 8; i++) {
    float angle = float(i) * 0.785398163; // 2*PI/8
    vec2 dir = vec2(cos(angle), sin(angle));

    // Ring 1: close, high weight
    vec2 uv1 = clamp(uv + dir * px * 2.0, cellMin, cellMax);
    glow += texture2D(texture, uv1) * 0.5;
    totalWeight += 0.5;

    // Ring 2: medium distance, medium weight
    vec2 uv2 = clamp(uv + dir * px * 4.0, cellMin, cellMax);
    glow += texture2D(texture, uv2) * 0.3;
    totalWeight += 0.3;

    // Ring 3: far, low weight
    vec2 uv3 = clamp(uv + dir * px * 7.0, cellMin, cellMax);
    glow += texture2D(texture, uv3) * 0.2;
    totalWeight += 0.2;
  }

  glow /= totalWeight;

  // Additive bloom: original + blurred glow
  vec4 result = original + glow * glowIntensity;
  result = clamp(result, 0.0, 1.0);

  gl_FragColor = result * gl_Color;
}
