layout(location = 0) out vec4 delta_irradiance;
layout(location = 1) out vec4 irradiance;
layout(binding = 1) uniform sampler2D transmittance_texture;
void main() {
  delta_irradiance = vec4(
      ComputeDirectIrradianceTexture(
          ATMOSPHERE, transmittance_texture, gl_FragCoord.xy),
      1.0);
  irradiance = vec4(0.0);
}
