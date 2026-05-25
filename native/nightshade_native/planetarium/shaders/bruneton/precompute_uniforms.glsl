layout(std140, binding = 0) uniform PrecomputeUniforms {
  mat3 luminance_from_radiance;
  int layer;
  int scattering_order;
  int _pad0;
  int _pad1;
};
