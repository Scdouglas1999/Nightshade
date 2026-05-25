layout(location = 0) out vec4 delta_rayleigh;
layout(location = 1) out vec4 delta_mie;
layout(location = 2) out vec4 scattering;
#ifndef COMBINED_SCATTERING_TEXTURES
layout(location = 3) out vec4 single_mie_scattering;
#endif
layout(binding = 1) uniform sampler2D transmittance_texture;
void main() {
  vec3 delta_r;
  vec3 delta_m;
  ComputeSingleScatteringTexture(
      ATMOSPHERE, transmittance_texture,
      vec3(gl_FragCoord.xy, float(layer) + 0.5),
      delta_r, delta_m);
  delta_rayleigh = vec4(delta_r, 1.0);
  delta_mie = vec4(delta_m, 1.0);
  scattering = vec4(
      luminance_from_radiance * delta_r,
      (luminance_from_radiance * delta_m).r);
#ifndef COMBINED_SCATTERING_TEXTURES
  single_mie_scattering = vec4(luminance_from_radiance * delta_m, 1.0);
#endif
}
