layout(location = 0) out vec4 scattering_density;
layout(binding = 1) uniform sampler2D transmittance_texture;
layout(binding = 2) uniform sampler2DArray single_rayleigh_scattering_texture;
layout(binding = 3) uniform sampler2DArray single_mie_scattering_texture;
layout(binding = 4) uniform sampler2DArray multiple_scattering_texture;
layout(binding = 5) uniform sampler2D irradiance_texture;
void main() {
  scattering_density = vec4(
      ComputeScatteringDensityTexture(
          ATMOSPHERE, transmittance_texture,
          single_rayleigh_scattering_texture,
          single_mie_scattering_texture,
          multiple_scattering_texture,
          irradiance_texture,
          vec3(gl_FragCoord.xy, float(layer) + 0.5),
          scattering_order),
      1.0);
}
