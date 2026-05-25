layout(location = 0) out vec4 out_color;
void main() {
  out_color = vec4(
      ComputeTransmittanceToTopAtmosphereBoundaryTexture(
          ATMOSPHERE, gl_FragCoord.xy),
      1.0);
}
