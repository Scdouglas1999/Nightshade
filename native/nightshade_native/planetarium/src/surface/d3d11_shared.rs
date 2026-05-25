//! D3D11/D3D12 shared-handle helper.
//!
//! Creates a D3D12 texture on a shared heap, exports an NT handle for Flutter
//! (`DxgiSharedHandle`), and imports the resource into wgpu via `create_texture_from_hal`.

use crate::PlanetariumError;
use d3d12::{Device as D3d12Device, Resource as D3d12Resource};
use std::sync::Arc;
use winapi::{
    shared::{dxgiformat, dxgitype, winerror::SUCCEEDED},
    um::{
        d3d12::{
            D3D12_HEAP_FLAG_SHARED, D3D12_HEAP_PROPERTIES, D3D12_HEAP_TYPE_CUSTOM, D3D12_MEMORY_POOL_L0,
            D3D12_RESOURCE_DIMENSION_TEXTURE2D, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
            D3D12_RESOURCE_STATE_COMMON, D3D12_TEXTURE_LAYOUT_UNKNOWN,
        },
        handleapi::CloseHandle,
        winnt::GENERIC_ALL,
    },
    Interface,
};
use wgpu::hal::dx12::Device as HalDx12Device;

/// Shareable wgpu render target plus the NT handle Flutter imports.
pub struct SharedTexture {
    /// wgpu texture wrapping the shared D3D12 resource.
    pub wgpu: Arc<wgpu::Texture>,
    /// NT handle for `irondash_texture::DxgiSharedHandle` registration.
    ///
    /// Closed by [`Drop`] — Flutter holds its own duplicated handle via
    /// `DxgiSharedHandle` so closing the source handle here does not break
    /// the registered texture; it just releases this process's reference.
    pub shared_handle: isize,
    /// Texture width in pixels.
    pub width: u32,
    /// Texture height in pixels.
    pub height: u32,
}

impl Drop for SharedTexture {
    fn drop(&mut self) {
        if self.shared_handle != 0 {
            // SAFETY: handle was produced by `ID3D12Device::CreateSharedHandle` in
            // `create_shared_d3d12_texture` and is owned by this `SharedTexture`.
            unsafe {
                CloseHandle(self.shared_handle as *mut _);
            }
            self.shared_handle = 0;
        }
    }
}

/// Allocate a BGRA8 render target with a DXGI-exportable shared handle.
pub fn allocate_shared(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> Result<SharedTexture, PlanetariumError> {
    let desc = wgpu::TextureDescriptor {
        label: Some("nightshade.shared_target"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Bgra8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    };

    let hal_result = unsafe {
        device.as_hal::<wgpu::hal::api::Dx12, _, Result<_, _>>(|hal_device| match hal_device {
            Some(hal_device) => create_shared_d3d12_texture(hal_device, width, height),
            None => Err(PlanetariumError::UnsupportedPlatform(
                "wgpu device has no DX12 backing — wrong backend selected",
            )),
        })
    };
    let (hal_texture, shared_handle) = hal_result
        .ok_or(PlanetariumError::UnsupportedPlatform(
            "wgpu device has no DX12 backing — wrong backend selected",
        ))??;

    let wgpu_texture = unsafe {
        device.create_texture_from_hal::<wgpu::hal::api::Dx12>(hal_texture, &desc)
    };

    Ok(SharedTexture {
        wgpu: Arc::new(wgpu_texture),
        shared_handle,
        width,
        height,
    })
}

/// Create a shared D3D12 texture and export an NT handle for DXGI import.
///
/// # Safety
/// Caller must ensure `hal_device` is the active wgpu DX12 device.
unsafe fn create_shared_d3d12_texture(
    hal_device: &HalDx12Device,
    width: u32,
    height: u32,
) -> Result<(wgpu::hal::dx12::Texture, isize), PlanetariumError> {
    let d3d_device: &D3d12Device = hal_device.raw_device();
    let mut resource = D3d12Resource::null();

    let heap_properties = D3D12_HEAP_PROPERTIES {
        Type: D3D12_HEAP_TYPE_CUSTOM,
        CPUPageProperty: winapi::um::d3d12::D3D12_CPU_PAGE_PROPERTY_NOT_AVAILABLE,
        MemoryPoolPreference: D3D12_MEMORY_POOL_L0,
        CreationNodeMask: 0,
        VisibleNodeMask: 0,
    };

    let raw_desc = winapi::um::d3d12::D3D12_RESOURCE_DESC {
        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        Alignment: 0,
        Width: width as u64,
        Height: height,
        DepthOrArraySize: 1,
        MipLevels: 1,
        Format: dxgiformat::DXGI_FORMAT_B8G8R8A8_UNORM,
        SampleDesc: dxgitype::DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
        Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
    };

    let hr = unsafe {
        d3d_device.CreateCommittedResource(
            &heap_properties,
            D3D12_HEAP_FLAG_SHARED,
            &raw_desc,
            D3D12_RESOURCE_STATE_COMMON,
            std::ptr::null(),
            &winapi::um::d3d12::ID3D12Resource::uuidof(),
            resource.mut_void(),
        )
    };
    if !SUCCEEDED(hr) {
        tracing::error!("CreateCommittedResource(SHARED) failed: {hr}");
        return Err(PlanetariumError::UnsupportedPlatform(
            "D3D12 CreateCommittedResource with D3D12_HEAP_FLAG_SHARED failed",
        ));
    }

    let mut nt_handle = std::ptr::null_mut();
    let hr = unsafe {
        d3d_device.CreateSharedHandle(
            resource.as_ptr() as *mut _,
            std::ptr::null(),
            GENERIC_ALL,
            std::ptr::null(),
            &mut nt_handle,
        )
    };
    if !SUCCEEDED(hr) {
        tracing::error!("ID3D12Device::CreateSharedHandle failed: {hr}");
        return Err(PlanetariumError::UnsupportedPlatform(
            "ID3D12Device::CreateSharedHandle failed",
        ));
    }

    let hal_texture = unsafe {
        HalDx12Device::texture_from_raw(
            resource,
            wgpu::TextureFormat::Bgra8Unorm,
            wgpu::TextureDimension::D2,
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            1,
            1,
        )
    };

    Ok((hal_texture, nt_handle as isize))
}
