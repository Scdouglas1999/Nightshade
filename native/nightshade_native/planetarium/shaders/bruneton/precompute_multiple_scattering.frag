layout(location = 0) out vec4 delta_multiple_scattering;
layout(location = 1) out vec4 scattering;
layout(binding = 1) uniform sampler2D transmittance_texture;
layout(binding = 2) uniform sampler2DArray scattering_density_texture;
void main() {
  float nu;
  vec3 delta = ComputeMultipleScatteringTexture(
      ATMOSPHERE, transmittance_texture, scattering_density_texture,
      vec3(gl_FragCoord.xy, float(layer) + 0.5), nu);
  delta_multiple_scattering = vec4(delta, 1.0);
  scattering = vec4(
      luminance_from_radiance * delta / RayleighPhaseFunction(nu),
      0.0);
}
