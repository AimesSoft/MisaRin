use std::collections::BTreeMap;
use std::sync::Arc;

use bevy::asset::{AssetPlugin, Assets};
use bevy::core_pipeline::CorePipelinePlugin;
use bevy::pbr::{PbrBundle, PbrPlugin, StandardMaterial};
use bevy::prelude::*;
use bevy::render::camera::{
    ManualTextureView, ManualTextureViewHandle, ManualTextureViews, RenderTarget,
};
use bevy::render::mesh::{Indices, Mesh};
use bevy::render::render_asset::RenderAssetUsages;
use bevy::render::render_resource::{
    Extent3d, Face, PrimitiveTopology, TextureDimension, TextureFormat,
};
use bevy::render::renderer::{RenderAdapter, RenderAdapterInfo, RenderInstance, RenderQueue};
use bevy::render::settings::RenderCreation;
use bevy::render::texture::{
    Image, ImageAddressMode, ImageFilterMode, ImageSampler, ImageSamplerDescriptor,
};
use bevy::render::RenderPlugin;
use bevy::window::{WindowClosed, WindowCreated, WindowResized, WindowScaleFactorChanged};
use serde::Deserialize;

use crate::gpu::shared_device::SharedRenderDevice;

const MANUAL_VIEW_HANDLE: ManualTextureViewHandle = ManualTextureViewHandle(0xC0BE_0001);
const GRADIENT_TEXTURE_HEIGHT: u32 = 256;
const GRADIENT_TEXTURE_WIDTH: u32 = 4;

#[derive(Clone)]
pub(crate) struct CubeTextPreviewScene {
    pub(crate) positions: Vec<f32>,
    pub(crate) normals: Vec<f32>,
    pub(crate) uvs: Vec<f32>,
    pub(crate) indices: Vec<u32>,
    pub(crate) material_indices: Vec<i32>,
    pub(crate) materials: Vec<CubeTextPreviewMaterial>,
    pub(crate) images: Vec<CubeTextPreviewImage>,
}

#[derive(Clone)]
pub(crate) struct CubeTextPreviewMaterial {
    pub(crate) mode: CubeTextPreviewMaterialMode,
    pub(crate) color: u32,
    pub(crate) gradient_start: u32,
    pub(crate) gradient_end: u32,
    pub(crate) repeat: f32,
    pub(crate) offset: f32,
    pub(crate) image_index: i32,
    pub(crate) repeat_x: f32,
    pub(crate) repeat_y: f32,
    pub(crate) offset_x: f32,
    pub(crate) offset_y: f32,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum CubeTextPreviewMaterialMode {
    Color,
    Gradient,
    Image,
}

#[derive(Clone)]
pub(crate) struct CubeTextPreviewImage {
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) rgba: Vec<u8>,
}

#[derive(Clone, Copy)]
pub(crate) struct CubeTextPreviewCamera {
    pub(crate) yaw: f32,
    pub(crate) pitch: f32,
    pub(crate) zoom: f32,
    pub(crate) fov: f32,
    pub(crate) transparent_background: bool,
}

impl Default for CubeTextPreviewCamera {
    fn default() -> Self {
        Self {
            yaw: -28.0,
            pitch: -28.0,
            zoom: 1.0,
            fov: 35.0,
            transparent_background: false,
        }
    }
}

pub(crate) struct CubeTextPreviewRenderer {
    format: wgpu::TextureFormat,
    app: App,
    camera: Entity,
    mesh_entities: Vec<Entity>,
    scene_key: Option<SceneKey>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct SceneKey {
    positions_len: usize,
    normals_len: usize,
    uvs_len: usize,
    indices_len: usize,
    material_indices_len: usize,
    materials_hash: u64,
    images_hash: u64,
}

#[derive(Clone, Copy)]
struct Bounds3 {
    center: Vec3,
    diagonal: f32,
}

impl CubeTextPreviewRenderer {
    pub(crate) fn new(
        instance: &Arc<wgpu::Instance>,
        adapter: &Arc<wgpu::Adapter>,
        device: &SharedRenderDevice,
        queue: &Arc<wgpu::Queue>,
        format: wgpu::TextureFormat,
    ) -> Self {
        let render_creation = RenderCreation::manual(
            device.bevy_render_device(),
            RenderQueue(Arc::clone(queue)),
            RenderAdapterInfo(adapter.get_info()),
            RenderAdapter(Arc::clone(adapter)),
            RenderInstance(Arc::clone(instance)),
        );

        let mut app = App::new();
        app.add_plugins(MinimalPlugins)
            .add_plugins(bevy::hierarchy::HierarchyPlugin)
            .add_plugins(bevy::transform::TransformPlugin)
            .add_event::<WindowResized>()
            .add_event::<WindowCreated>()
            .add_event::<WindowScaleFactorChanged>()
            .add_event::<WindowClosed>()
            .add_plugins(AssetPlugin::default())
            .add_plugins(RenderPlugin {
                render_creation,
                synchronous_pipeline_compilation: true,
            })
            .add_plugins(bevy::render::texture::ImagePlugin::default())
            .add_plugins(CorePipelinePlugin)
            .add_plugins(PbrPlugin::default())
            .init_resource::<ManualTextureViews>();

        app.world.insert_resource(AmbientLight {
            color: Color::WHITE,
            brightness: 280.0,
        });
        app.world.insert_resource(Msaa::Sample4);

        let camera = app
            .world
            .spawn(Camera3dBundle {
                camera: Camera {
                    target: RenderTarget::TextureView(MANUAL_VIEW_HANDLE),
                    clear_color: ClearColorConfig::Custom(Color::rgb(0.97, 0.97, 0.97)),
                    ..default()
                },
                ..default()
            })
            .id();

        app.world.spawn(DirectionalLightBundle {
            directional_light: DirectionalLight {
                illuminance: 16_000.0,
                shadows_enabled: true,
                ..default()
            },
            transform: Transform::from_xyz(-2.0, 4.0, 6.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        });
        app.world.spawn(PointLightBundle {
            point_light: PointLight {
                intensity: 260_000.0,
                radius: 8.0,
                shadows_enabled: false,
                ..default()
            },
            transform: Transform::from_xyz(4.0, -3.0, 5.0),
            ..default()
        });

        app.finish();
        app.cleanup();

        Self {
            format,
            app,
            camera,
            mesh_entities: Vec::new(),
            scene_key: None,
        }
    }

    pub(crate) fn format(&self) -> wgpu::TextureFormat {
        self.format
    }

    pub(crate) fn render(
        &mut self,
        target_texture: &wgpu::Texture,
        width: u32,
        height: u32,
        scene: &CubeTextPreviewScene,
        camera: CubeTextPreviewCamera,
    ) {
        if width == 0 || height == 0 || scene.positions.len() < 3 || scene.indices.len() < 3 {
            return;
        }
        self.update_target(target_texture, width, height);
        self.ensure_scene(scene);
        self.update_camera(scene, width, height, camera);
        self.app.update();
    }

    fn update_target(&mut self, target_texture: &wgpu::Texture, width: u32, height: u32) {
        let view_format = self.format.add_srgb_suffix();
        let target_view = target_texture.create_view(&wgpu::TextureViewDescriptor {
            format: Some(view_format),
            ..Default::default()
        });
        let manual_view = ManualTextureView {
            texture_view: target_view.into(),
            size: UVec2::new(width, height),
            format: view_format,
        };
        self.app
            .world
            .resource_mut::<ManualTextureViews>()
            .insert(MANUAL_VIEW_HANDLE, manual_view);
    }

    fn ensure_scene(&mut self, scene: &CubeTextPreviewScene) {
        let key = SceneKey::from_scene(scene);
        if self.scene_key == Some(key) {
            return;
        }
        for entity in self.mesh_entities.drain(..) {
            if let Some(entity_commands) = self.app.world.get_entity_mut(entity) {
                entity_commands.despawn_recursive();
            }
        }

        let chunks = split_scene_by_material(scene);

        for (material_index, chunk) in chunks {
            if chunk.positions.is_empty() {
                continue;
            }
            let mut mesh = Mesh::new(
                PrimitiveTopology::TriangleList,
                RenderAssetUsages::default(),
            );
            mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, chunk.positions);
            mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, chunk.normals);
            mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, chunk.uvs);
            mesh.insert_indices(Indices::U32(
                (0..chunk.vertex_count as u32).collect::<Vec<u32>>(),
            ));

            let spec = material_spec(scene, material_index);
            let texture = self.material_texture(spec, scene);
            let color = material_color(spec);
            let slot = material_index % 7;
            let mut meshes = self.app.world.resource_mut::<Assets<Mesh>>();
            let mesh_handle = meshes.add(mesh);
            drop(meshes);
            let mut materials = self.app.world.resource_mut::<Assets<StandardMaterial>>();
            let material_handle = materials.add(StandardMaterial {
                base_color: if texture.is_some() {
                    Color::WHITE
                } else {
                    color
                },
                base_color_texture: texture,
                perceptual_roughness: if slot == 6 { 0.92 } else { 0.68 },
                metallic: 0.0,
                reflectance: if slot == 6 { 0.04 } else { 0.18 },
                unlit: slot == 6,
                double_sided: true,
                cull_mode: None::<Face>,
                alpha_mode: AlphaMode::Opaque,
                ..default()
            });
            drop(materials);

            let entity = self
                .app
                .world
                .spawn(PbrBundle {
                    mesh: mesh_handle,
                    material: material_handle,
                    transform: Transform::IDENTITY,
                    ..default()
                })
                .id();
            self.mesh_entities.push(entity);
        }

        self.scene_key = Some(key);
    }

    fn update_camera(
        &mut self,
        scene: &CubeTextPreviewScene,
        width: u32,
        height: u32,
        camera: CubeTextPreviewCamera,
    ) {
        let Some(mut entity) = self.app.world.get_entity_mut(self.camera) else {
            return;
        };
        let bounds = Bounds3::from_positions(&scene.positions);
        let fov = camera.fov.clamp(10.0, 80.0).to_radians();
        let zoom = camera.zoom.clamp(0.1, 12.0);
        let aspect = (width as f32 / height.max(1) as f32).max(0.01);
        let radius = (bounds.diagonal * 0.5).max(1.0);
        let distance = (radius / (fov * 0.5).tan()) * 1.24 / zoom;
        let yaw = camera.yaw.to_radians();
        let pitch = camera.pitch.clamp(-88.0, 88.0).to_radians();
        let dir = Vec3::new(
            yaw.sin() * pitch.cos(),
            pitch.sin(),
            yaw.cos() * pitch.cos(),
        )
        .normalize_or_zero();
        let eye = bounds.center + dir * distance.max(0.1);
        let transform = Transform::from_translation(eye).looking_at(bounds.center, Vec3::Y);

        if let Some(mut transform_component) = entity.get_mut::<Transform>() {
            *transform_component = transform;
        }
        if let Some(mut projection) = entity.get_mut::<Projection>() {
            *projection = Projection::Perspective(PerspectiveProjection {
                fov,
                aspect_ratio: aspect,
                near: (bounds.diagonal * 0.0005).max(0.01),
                far: (distance + bounds.diagonal * 4.0).max(100.0),
            });
        }
        if let Some(mut camera_component) = entity.get_mut::<Camera>() {
            camera_component.clear_color =
                ClearColorConfig::Custom(if camera.transparent_background {
                    Color::rgba(0.0, 0.0, 0.0, 0.0)
                } else {
                    Color::rgb(0.97, 0.97, 0.97)
                });
        }
    }
}

impl SceneKey {
    fn from_scene(scene: &CubeTextPreviewScene) -> Self {
        Self {
            positions_len: scene.positions.len(),
            normals_len: scene.normals.len(),
            uvs_len: scene.uvs.len(),
            indices_len: scene.indices.len(),
            material_indices_len: scene.material_indices.len(),
            materials_hash: hash_materials(&scene.materials),
            images_hash: hash_images(&scene.images),
        }
    }
}

struct MeshChunk {
    positions: Vec<[f32; 3]>,
    normals: Vec<[f32; 3]>,
    uvs: Vec<[f32; 2]>,
    vertex_count: usize,
}

fn split_scene_by_material(scene: &CubeTextPreviewScene) -> BTreeMap<u32, MeshChunk> {
    let mut chunks: BTreeMap<u32, MeshChunk> = BTreeMap::new();
    for (triangle_index, tri) in scene.indices.chunks_exact(3).enumerate() {
        let material_index = scene
            .material_indices
            .get(triangle_index)
            .copied()
            .unwrap_or(0)
            .max(0) as u32;
        let chunk = chunks.entry(material_index).or_insert_with(|| MeshChunk {
            positions: Vec::new(),
            normals: Vec::new(),
            uvs: Vec::new(),
            vertex_count: 0,
        });
        let material = material_spec(scene, material_index);
        for &index in tri {
            let vertex_index = index as usize;
            if let Some(position) = read_vec3(&scene.positions, vertex_index) {
                chunk.positions.push(position);
                chunk
                    .normals
                    .push(read_vec3(&scene.normals, vertex_index).unwrap_or([0.0, 0.0, 1.0]));
                let uv = read_vec2(&scene.uvs, vertex_index).unwrap_or([0.0, 0.0]);
                chunk.uvs.push(transform_uv(material, uv));
                chunk.vertex_count += 1;
            }
        }
    }
    chunks
}

fn read_vec3(values: &[f32], vertex_index: usize) -> Option<[f32; 3]> {
    let offset = vertex_index.checked_mul(3)?;
    Some([
        *values.get(offset)?,
        *values.get(offset + 1)?,
        *values.get(offset + 2)?,
    ])
}

fn read_vec2(values: &[f32], vertex_index: usize) -> Option<[f32; 2]> {
    let offset = vertex_index.checked_mul(2)?;
    Some([*values.get(offset)?, *values.get(offset + 1)?])
}

fn material_spec(scene: &CubeTextPreviewScene, material_index: u32) -> &CubeTextPreviewMaterial {
    static FALLBACK: CubeTextPreviewMaterial = CubeTextPreviewMaterial {
        mode: CubeTextPreviewMaterialMode::Color,
        color: 0xFFFF_FFFF,
        gradient_start: 0xFFFF_FFFF,
        gradient_end: 0xFFFF_FFFF,
        repeat: 1.0,
        offset: 0.0,
        image_index: -1,
        repeat_x: 1.0,
        repeat_y: 1.0,
        offset_x: 0.0,
        offset_y: 0.0,
    };
    scene
        .materials
        .get(material_index as usize)
        .unwrap_or(&FALLBACK)
}

fn transform_uv(material: &CubeTextPreviewMaterial, uv: [f32; 2]) -> [f32; 2] {
    match material.mode {
        CubeTextPreviewMaterialMode::Gradient => {
            let repeat = material.repeat.max(0.001);
            [uv[0], (uv[1] + material.offset).mul_add(repeat, 0.0)]
        }
        CubeTextPreviewMaterialMode::Image => {
            let repeat_x = material.repeat_x.max(0.001) * 24.0;
            let repeat_y = material.repeat_y.max(0.001) * 24.0;
            [
                uv[0].mul_add(repeat_x, material.offset_x),
                uv[1].mul_add(repeat_y, material.offset_y),
            ]
        }
        CubeTextPreviewMaterialMode::Color => uv,
    }
}

fn material_color(material: &CubeTextPreviewMaterial) -> Color {
    let rgba = match material.mode {
        CubeTextPreviewMaterialMode::Gradient => material.gradient_start,
        _ => material.color,
    };
    let r = ((rgba >> 24) & 0xFF) as f32 / 255.0;
    let g = ((rgba >> 16) & 0xFF) as f32 / 255.0;
    let b = ((rgba >> 8) & 0xFF) as f32 / 255.0;
    let a = (rgba & 0xFF) as f32 / 255.0;
    Color::rgba(r, g, b, a)
}

impl CubeTextPreviewRenderer {
    fn material_texture(
        &mut self,
        material: &CubeTextPreviewMaterial,
        scene: &CubeTextPreviewScene,
    ) -> Option<Handle<Image>> {
        let image = match material.mode {
            CubeTextPreviewMaterialMode::Gradient => Some(gradient_image(
                material.gradient_start,
                material.gradient_end,
            )),
            CubeTextPreviewMaterialMode::Image => {
                if material.image_index < 0 {
                    None
                } else {
                    scene
                        .images
                        .get(material.image_index as usize)
                        .and_then(image_from_preview_image)
                }
            }
            CubeTextPreviewMaterialMode::Color => None,
        }?;
        let mut images = self.app.world.resource_mut::<Assets<Image>>();
        Some(images.add(image))
    }
}

fn gradient_image(start: u32, end: u32) -> Image {
    let mut image = Image::new_fill(
        Extent3d {
            width: GRADIENT_TEXTURE_WIDTH,
            height: GRADIENT_TEXTURE_HEIGHT,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[255, 255, 255, 255],
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    );
    for y in 0..GRADIENT_TEXTURE_HEIGHT {
        let t = if GRADIENT_TEXTURE_HEIGHT <= 1 {
            0.0
        } else {
            y as f32 / (GRADIENT_TEXTURE_HEIGHT - 1) as f32
        };
        let color = lerp_rgba(start, end, t);
        for x in 0..GRADIENT_TEXTURE_WIDTH {
            let offset = ((y * GRADIENT_TEXTURE_WIDTH + x) * 4) as usize;
            image.data[offset] = ((color >> 24) & 0xFF) as u8;
            image.data[offset + 1] = ((color >> 16) & 0xFF) as u8;
            image.data[offset + 2] = ((color >> 8) & 0xFF) as u8;
            image.data[offset + 3] = (color & 0xFF) as u8;
        }
    }
    image.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
        address_mode_u: ImageAddressMode::ClampToEdge,
        address_mode_v: ImageAddressMode::ClampToEdge,
        address_mode_w: ImageAddressMode::ClampToEdge,
        mag_filter: ImageFilterMode::Linear,
        min_filter: ImageFilterMode::Linear,
        ..Default::default()
    });
    image
}

fn image_from_preview_image(source: &CubeTextPreviewImage) -> Option<Image> {
    let expected_len = source.width.checked_mul(source.height)?.checked_mul(4)? as usize;
    if source.width == 0 || source.height == 0 || source.rgba.len() != expected_len {
        return None;
    }
    Some(Image {
        data: source.rgba.clone(),
        texture_descriptor: wgpu::TextureDescriptor {
            label: None,
            size: Extent3d {
                width: source.width,
                height: source.height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format: TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        },
        sampler: ImageSampler::Descriptor(ImageSamplerDescriptor {
            address_mode_u: ImageAddressMode::Repeat,
            address_mode_v: ImageAddressMode::Repeat,
            address_mode_w: ImageAddressMode::ClampToEdge,
            mag_filter: ImageFilterMode::Linear,
            min_filter: ImageFilterMode::Linear,
            ..Default::default()
        }),
        texture_view_descriptor: None,
        asset_usage: RenderAssetUsages::default(),
    })
}

fn lerp_rgba(start: u32, end: u32, t: f32) -> u32 {
    let t = t.clamp(0.0, 1.0);
    let sr = ((start >> 24) & 0xFF) as f32;
    let sg = ((start >> 16) & 0xFF) as f32;
    let sb = ((start >> 8) & 0xFF) as f32;
    let sa = (start & 0xFF) as f32;
    let er = ((end >> 24) & 0xFF) as f32;
    let eg = ((end >> 16) & 0xFF) as f32;
    let eb = ((end >> 8) & 0xFF) as f32;
    let ea = (end & 0xFF) as f32;
    let r = (sr + (er - sr) * t).round().clamp(0.0, 255.0) as u32;
    let g = (sg + (eg - sg) * t).round().clamp(0.0, 255.0) as u32;
    let b = (sb + (eb - sb) * t).round().clamp(0.0, 255.0) as u32;
    let a = (sa + (ea - sa) * t).round().clamp(0.0, 255.0) as u32;
    (r << 24) | (g << 16) | (b << 8) | a
}

impl Bounds3 {
    fn from_positions(positions: &[f32]) -> Self {
        if positions.len() < 3 {
            return Self {
                center: Vec3::ZERO,
                diagonal: 1.0,
            };
        }
        let mut min = Vec3::splat(f32::INFINITY);
        let mut max = Vec3::splat(f32::NEG_INFINITY);
        for point in positions.chunks_exact(3) {
            let p = Vec3::new(point[0], point[1], point[2]);
            min = min.min(p);
            max = max.max(p);
        }
        if !min.is_finite() || !max.is_finite() {
            return Self {
                center: Vec3::ZERO,
                diagonal: 1.0,
            };
        }
        let size = max - min;
        Self {
            center: (min + max) * 0.5,
            diagonal: size.length().max(1.0),
        }
    }
}

fn hash_materials(values: &[CubeTextPreviewMaterial]) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    for value in values {
        hash = hash_mix(hash, value.mode as u64);
        hash = hash_mix(hash, value.color as u64);
        hash = hash_mix(hash, value.gradient_start as u64);
        hash = hash_mix(hash, value.gradient_end as u64);
        hash = hash_mix(hash, value.repeat.to_bits() as u64);
        hash = hash_mix(hash, value.offset.to_bits() as u64);
        hash = hash_mix(hash, value.image_index as u64);
        hash = hash_mix(hash, value.repeat_x.to_bits() as u64);
        hash = hash_mix(hash, value.repeat_y.to_bits() as u64);
        hash = hash_mix(hash, value.offset_x.to_bits() as u64);
        hash = hash_mix(hash, value.offset_y.to_bits() as u64);
    }
    hash
}

fn hash_images(values: &[CubeTextPreviewImage]) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    for value in values {
        hash = hash_mix(hash, value.width as u64);
        hash = hash_mix(hash, value.height as u64);
        for byte in &value.rgba {
            hash ^= *byte as u64;
            hash = hash.wrapping_mul(0x1000_0000_01b3);
        }
    }
    hash
}

fn hash_mix(mut hash: u64, value: u64) -> u64 {
    hash ^= value;
    hash.wrapping_mul(0x1000_0000_01b3)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MaterialJson {
    #[serde(default)]
    mode: String,
    #[serde(default = "default_white")]
    color: u32,
    #[serde(default = "default_white")]
    gradient_start: u32,
    #[serde(default = "default_white")]
    gradient_end: u32,
    #[serde(default = "default_one")]
    repeat: f32,
    #[serde(default)]
    offset: f32,
    #[serde(default = "default_image_index")]
    image_index: i32,
    #[serde(default = "default_one")]
    repeat_x: f32,
    #[serde(default = "default_one")]
    repeat_y: f32,
    #[serde(default)]
    offset_x: f32,
    #[serde(default)]
    offset_y: f32,
}

pub(crate) fn parse_materials_json(bytes: &[u8]) -> Vec<CubeTextPreviewMaterial> {
    let Ok(values) = serde_json::from_slice::<Vec<MaterialJson>>(bytes) else {
        return vec![CubeTextPreviewMaterial::default()];
    };
    let mut materials = Vec::with_capacity(values.len().max(1));
    for value in values {
        let mode = match value.mode.as_str() {
            "gradient" => CubeTextPreviewMaterialMode::Gradient,
            "image" => CubeTextPreviewMaterialMode::Image,
            _ => CubeTextPreviewMaterialMode::Color,
        };
        materials.push(CubeTextPreviewMaterial {
            mode,
            color: value.color,
            gradient_start: value.gradient_start,
            gradient_end: value.gradient_end,
            repeat: finite_or(value.repeat, 1.0),
            offset: finite_or(value.offset, 0.0),
            image_index: value.image_index,
            repeat_x: finite_or(value.repeat_x, 1.0),
            repeat_y: finite_or(value.repeat_y, 1.0),
            offset_x: finite_or(value.offset_x, 0.0),
            offset_y: finite_or(value.offset_y, 0.0),
        });
    }
    if materials.is_empty() {
        materials.push(CubeTextPreviewMaterial::default());
    }
    materials
}

impl Default for CubeTextPreviewMaterial {
    fn default() -> Self {
        Self {
            mode: CubeTextPreviewMaterialMode::Color,
            color: 0xFFFF_FFFF,
            gradient_start: 0xFFFF_FFFF,
            gradient_end: 0xFFFF_FFFF,
            repeat: 1.0,
            offset: 0.0,
            image_index: -1,
            repeat_x: 1.0,
            repeat_y: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
        }
    }
}

fn default_white() -> u32 {
    0xFFFF_FFFF
}

fn default_one() -> f32 {
    1.0
}

fn default_image_index() -> i32 {
    -1
}

fn finite_or(value: f32, fallback: f32) -> f32 {
    if value.is_finite() {
        value
    } else {
        fallback
    }
}
