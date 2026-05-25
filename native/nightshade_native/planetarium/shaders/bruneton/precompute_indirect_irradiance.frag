layout(location = 0) out vec4 delta_irradiance;
layout(location = 1) out vec4 irradiance;
layout(binding = 1) uniform sampler2DArray single_rayleigh_scattering_texture;
layout(binding = 2) uniform sampler2DArray single_mie_scattering_texture;
layout(binding = 3) uniform sampler2DArray multiple_scattering_texture;
void main() {
  vec3 delta = ComputeIndirectIrradianceTexture(
      ATMOSPHERE, single_rayleigh_scattering_texture,
      single_mie_scattering_texture, multiple_scattering_texture,
      gl_FragCoord.xy, scattering_order);
  delta_irradiance = vec4(delta, 1.0);
  irradiance = vec4(luminance_from_radiance * delta, 1.0);
}
