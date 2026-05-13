use std::any::TypeId;
use std::borrow::Cow;
use std::collections::BTreeMap;
use std::sync::Arc;

use bevy::asset::{AssetPlugin, Assets, RenderAssetUsages};
use bevy::camera::visibility::{NoFrustumCulling, ViewVisibility, VisibleEntities};
use bevy::camera::{ManualTextureViewHandle, RenderTarget};
use bevy::core_pipeline::CorePipelinePlugin;
use bevy::image::{
    Image, ImageAddressMode, ImageFilterMode, ImagePlugin, ImageSampler, ImageSamplerDescriptor,
};
use bevy::light::{DirectionalLight, GlobalAmbientLight, PointLight};
use bevy::mesh::{Indices, Mesh, Mesh3d};
use bevy::pbr::{
    DefaultOpaqueRendererMethod, MeshMaterial3d, OpaqueRendererMethod, PbrPlugin, PreparedMaterial,
    RenderMaterialInstances, StandardMaterial,
};
use bevy::prelude::*;
use bevy::render::erased_render_asset::ErasedRenderAssets;
use bevy::render::mesh::RenderMesh;
use bevy::render::render_asset::RenderAssets;
use bevy::render::render_resource::{
    Extent3d, Face, PrimitiveTopology, TextureDimension, TextureFormat,
};
use bevy::render::renderer::{
    RenderAdapter, RenderAdapterInfo, RenderInstance, RenderQueue, WgpuWrapper,
};
use bevy::render::settings::RenderCreation;
use bevy::render::texture::{GpuImage, ManualTextureView, ManualTextureViews};
use bevy::render::view::ViewTarget;
use bevy::render::{RenderApp, RenderPlugin};
use bevy::window::{WindowClosed, WindowCreated, WindowResized, WindowScaleFactorChanged};
use serde::Deserialize;
use wgpu::TextureViewDimension;

use crate::gpu::debug::{self, LogLevel};
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
    device: SharedRenderDevice,
    queue: Arc<wgpu::Queue>,
    checkerboard_pipeline: wgpu::RenderPipeline,
    camera: Entity,
    mesh_entities: Vec<Entity>,
    scene_key: Option<SceneKey>,
    scene_just_rebuilt: bool,
    render_debug_logged: bool,
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
            RenderQueue(Arc::new(WgpuWrapper::new(queue.as_ref().clone()))),
            RenderAdapterInfo(WgpuWrapper::new(adapter.get_info())),
            RenderAdapter(Arc::new(WgpuWrapper::new(adapter.as_ref().clone()))),
            RenderInstance(Arc::new(WgpuWrapper::new(instance.as_ref().clone()))),
        );
        let checkerboard_pipeline =
            create_checkerboard_pipeline(device.as_ref(), format.add_srgb_suffix());

        let mut app = App::new();
        app.add_plugins(MinimalPlugins)
            .add_plugins(bevy::transform::TransformPlugin)
            .add_message::<WindowResized>()
            .add_message::<WindowCreated>()
            .add_message::<WindowScaleFactorChanged>()
            .add_message::<WindowClosed>()
            .add_plugins(AssetPlugin::default())
            .add_plugins(RenderPlugin {
                render_creation,
                synchronous_pipeline_compilation: true,
                ..default()
            })
            .add_plugins(ImagePlugin::default())
            .add_plugins(CorePipelinePlugin)
            .add_plugins(PbrPlugin::default())
            .init_resource::<ManualTextureViews>();

        app.world_mut()
            .insert_resource(DefaultOpaqueRendererMethod::forward());
        app.world_mut().insert_resource(GlobalAmbientLight {
            color: Color::WHITE,
            brightness: 280.0,
            affects_lightmapped_meshes: true,
        });
        let camera = app
            .world_mut()
            .spawn((
                Camera3d::default(),
                Msaa::Sample4,
                Camera {
                    clear_color: ClearColorConfig::Custom(Color::srgb(0.97, 0.97, 0.97)),
                    ..default()
                },
                RenderTarget::TextureView(MANUAL_VIEW_HANDLE),
            ))
            .id();

        app.world_mut().spawn((
            DirectionalLight {
                illuminance: 16_000.0,
                shadows_enabled: true,
                ..default()
            },
            Transform::from_xyz(-2.0, 4.0, 6.0).looking_at(Vec3::ZERO, Vec3::Y),
        ));
        app.world_mut().spawn((
            PointLight {
                intensity: 260_000.0,
                radius: 8.0,
                shadows_enabled: false,
                ..default()
            },
            Transform::from_xyz(4.0, -3.0, 5.0),
        ));

        app.finish();
        app.cleanup();

        Self {
            format,
            app,
            device: device.clone(),
            queue: Arc::clone(queue),
            checkerboard_pipeline,
            camera,
            mesh_entities: Vec::new(),
            scene_key: None,
            scene_just_rebuilt: false,
            render_debug_logged: false,
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
        if camera.transparent_background {
            self.render_checkerboard_background(target_texture, width, height);
        }
        if self.scene_just_rebuilt {
            // Bevy render assets/material bind groups are extracted and prepared on update.
            // A warm-up update prevents the first visible frame from using incomplete render state.
            self.app.update();
            self.scene_just_rebuilt = false;
        }
        self.app.update();
        self.log_render_state_once();
    }

    fn render_checkerboard_background(
        &self,
        target_texture: &wgpu::Texture,
        width: u32,
        height: u32,
    ) {
        if width == 0 || height == 0 {
            return;
        }
        let view_format = self.format.add_srgb_suffix();
        let target_view = target_texture.create_view(&wgpu::TextureViewDescriptor {
            label: Some("misa-rin cube text checkerboard target view"),
            dimension: Some(TextureViewDimension::D2),
            format: Some(view_format),
            mip_level_count: Some(1),
            array_layer_count: Some(1),
            ..Default::default()
        });
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("misa-rin cube text checkerboard encoder"),
            });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("misa-rin cube text checkerboard pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    depth_slice: None,
                    view: &target_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.checkerboard_pipeline);
            pass.draw(0..3, 0..1);
        }
        self.queue.submit(Some(encoder.finish()));
        debug::log(
            LogLevel::Verbose,
            format_args!(
                "cube_text_preview checkerboard prefill size={}x{} format={:?}",
                width, height, view_format,
            ),
        );
    }

    fn update_target(&mut self, target_texture: &wgpu::Texture, width: u32, height: u32) {
        let view_format = self.format.add_srgb_suffix();
        let target_view = target_texture.create_view(&wgpu::TextureViewDescriptor {
            label: Some("misa-rin cube text bevy target view"),
            dimension: Some(TextureViewDimension::D2),
            format: Some(view_format),
            mip_level_count: Some(1),
            array_layer_count: Some(1),
            ..Default::default()
        });
        let manual_view = ManualTextureView {
            texture_view: target_view.into(),
            size: UVec2::new(width, height),
            view_format,
        };
        self.app
            .world_mut()
            .resource_mut::<ManualTextureViews>()
            .insert(MANUAL_VIEW_HANDLE, manual_view);
        debug::log(
            LogLevel::Verbose,
            format_args!(
                "cube_text_preview target size={}x{} base_format={:?} view_format={:?}",
                width, height, self.format, view_format,
            ),
        );
    }

    fn ensure_scene(&mut self, scene: &CubeTextPreviewScene) {
        let key = SceneKey::from_scene(scene);
        if self.scene_key == Some(key) {
            return;
        }
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview bevy rebuild vertices={} triangles={} chunks_pending materials={} images={}",
                scene.positions.len() / 3,
                scene.indices.len() / 3,
                scene.materials.len(),
                scene.images.len(),
            ),
        );
        for entity in self.mesh_entities.drain(..) {
            if let Ok(entity_commands) = self.app.world_mut().get_entity_mut(entity) {
                entity_commands.despawn();
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
            let texture_id = texture.as_ref().map(|handle| format!("{:?}", handle.id()));
            let color = material_color(spec);
            let slot = material_index % 7;
            debug::log(
                LogLevel::Info,
                format_args!(
                    "cube_text_preview material[{material_index}] mode={} image_index={} color=0x{:08X} gradient_start=0x{:08X} gradient_end=0x{:08X} texture={} texture_id={} vertices={}",
                    spec.mode_name(),
                    spec.image_index,
                    spec.color,
                    spec.gradient_start,
                    spec.gradient_end,
                    texture.is_some(),
                    texture_id.as_deref().unwrap_or("none"),
                    chunk.vertex_count,
                ),
            );
            let mut meshes = self.app.world_mut().resource_mut::<Assets<Mesh>>();
            let mesh_handle = meshes.add(mesh);
            drop(meshes);
            let mut materials = self
                .app
                .world_mut()
                .resource_mut::<Assets<StandardMaterial>>();
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
                unlit: true,
                fog_enabled: false,
                double_sided: true,
                cull_mode: None::<Face>,
                alpha_mode: AlphaMode::Opaque,
                opaque_render_method: OpaqueRendererMethod::Forward,
                ..default()
            });
            let material_id = material_handle.id();
            drop(materials);
            debug::log(
                LogLevel::Verbose,
                format_args!(
                    "cube_text_preview material[{material_index}] handle_id={material_id:?}"
                ),
            );

            let entity = self
                .app
                .world_mut()
                .spawn((
                    Mesh3d(mesh_handle),
                    MeshMaterial3d(material_handle),
                    Transform::IDENTITY,
                ))
                .insert(NoFrustumCulling)
                .id();
            self.mesh_entities.push(entity);
        }

        self.scene_key = Some(key);
        self.scene_just_rebuilt = true;
        self.render_debug_logged = false;
    }

    fn update_camera(
        &mut self,
        scene: &CubeTextPreviewScene,
        width: u32,
        height: u32,
        camera: CubeTextPreviewCamera,
    ) {
        let Ok(mut entity) = self.app.world_mut().get_entity_mut(self.camera) else {
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
            let near = (bounds.diagonal * 0.0005).max(0.01);
            *projection = Projection::Perspective(PerspectiveProjection {
                fov,
                aspect_ratio: aspect,
                near,
                far: (distance + bounds.diagonal * 4.0).max(100.0),
                near_clip_plane: Vec4::new(0.0, 0.0, -1.0, -near),
            });
        }
        if let Some(mut camera_component) = entity.get_mut::<Camera>() {
            camera_component.clear_color =
                ClearColorConfig::Custom(if camera.transparent_background {
                    Color::NONE
                } else {
                    Color::srgb(0.97, 0.97, 0.97)
                });
        }
        debug::log(
            LogLevel::Verbose,
            format_args!(
                "cube_text_preview camera yaw={:.2} pitch={:.2} zoom={:.3} fov={:.2} transparent={} eye=({:.2},{:.2},{:.2}) center=({:.2},{:.2},{:.2})",
                camera.yaw,
                camera.pitch,
                camera.zoom,
                camera.fov,
                camera.transparent_background,
                eye.x,
                eye.y,
                eye.z,
                bounds.center.x,
                bounds.center.y,
                bounds.center.z,
            ),
        );
    }

    fn log_render_state_once(&mut self) {
        if self.render_debug_logged || debug::level() < LogLevel::Info {
            return;
        }
        self.render_debug_logged = true;

        let mut visible_count = 0usize;
        let mut hidden_count = 0usize;
        let mut default_material_count = 0usize;
        let mut texture_material_count = 0usize;
        let mut material_entity_count = 0usize;
        let mut material_samples = Vec::new();
        let main_material_asset_count;
        let main_image_asset_count;
        {
            let materials = self.app.world().resource::<Assets<StandardMaterial>>();
            main_material_asset_count = materials.iter().count();
            let images = self.app.world().resource::<Assets<Image>>();
            main_image_asset_count = images.iter().count();
            for &entity in &self.mesh_entities {
                let Ok(entity_ref) = self.app.world().get_entity(entity) else {
                    continue;
                };
                let visible = entity_ref
                    .get::<ViewVisibility>()
                    .map(|visibility| visibility.get())
                    .unwrap_or(false);
                if visible {
                    visible_count += 1;
                } else {
                    hidden_count += 1;
                }
                let Some(material_component) = entity_ref.get::<MeshMaterial3d<StandardMaterial>>()
                else {
                    continue;
                };
                material_entity_count += 1;
                if material_samples.len() < 4 {
                    if let Some(material) = materials.get(&material_component.0) {
                        material_samples.push(format!(
                            "{entity:?}:id={:?}:color={:?}:texture={}:unlit={}:fog={}:opaque={:?}",
                            material_component.0.id(),
                            material.base_color,
                            material.base_color_texture.is_some(),
                            material.unlit,
                            material.fog_enabled,
                            material.opaque_render_method,
                        ));
                    } else {
                        material_samples.push(format!(
                            "{entity:?}:id={:?}:missing",
                            material_component.0.id()
                        ));
                    }
                }
                if material_component.0.id() == Handle::<StandardMaterial>::default().id() {
                    default_material_count += 1;
                }
                if materials
                    .get(&material_component.0)
                    .and_then(|material| material.base_color_texture.as_ref())
                    .is_some()
                {
                    texture_material_count += 1;
                }
            }
        }

        let mut render_material_instances = 0usize;
        let mut render_materials = 0usize;
        let mut render_meshes = 0usize;
        let mut render_images = 0usize;
        let mut render_visible_entities = 0usize;
        let mut view_targets = 0usize;
        let mut prepared_material_samples = Vec::new();
        if let Some(render_app) = self.app.get_sub_app_mut(RenderApp) {
            if let Some(instances) = render_app.world().get_resource::<RenderMaterialInstances>() {
                render_material_instances = instances.instances.len();
            }
            if let Some(materials) = render_app
                .world()
                .get_resource::<ErasedRenderAssets<PreparedMaterial>>()
            {
                render_materials = materials.iter().count();
                for (asset_id, material) in materials.iter().take(4) {
                    prepared_material_samples.push(format!(
                        "{asset_id:?}:render={:?}:alpha={:?}:binding={:?}",
                        material.properties.render_method,
                        material.properties.alpha_mode,
                        material.binding,
                    ));
                }
            }
            if let Some(meshes) = render_app
                .world()
                .get_resource::<RenderAssets<RenderMesh>>()
            {
                render_meshes = meshes.iter().count();
            }
            if let Some(images) = render_app.world().get_resource::<RenderAssets<GpuImage>>() {
                render_images = images.iter().count();
            }
            let mut query = render_app.world_mut().query::<&VisibleEntities>();
            for visible_entities in query.iter(render_app.world()) {
                render_visible_entities += visible_entities.len(TypeId::of::<Mesh3d>());
            }
            let mut view_query = render_app.world_mut().query::<Option<&ViewTarget>>();
            for view_target in view_query.iter(render_app.world()) {
                if view_target.is_some() {
                    view_targets += 1;
                }
            }
        }

        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview render state entities={} main_material_assets={} main_image_assets={} material_entities={} visible={} hidden={} default_material_handles={} textured_main_materials={} render_instances={} render_materials={} render_meshes={} render_images={} render_visible_entities={} view_targets={} material_samples=[{}] prepared_material_samples=[{}]",
                self.mesh_entities.len(),
                main_material_asset_count,
                main_image_asset_count,
                material_entity_count,
                visible_count,
                hidden_count,
                default_material_count,
                texture_material_count,
                render_material_instances,
                render_materials,
                render_meshes,
                render_images,
                render_visible_entities,
                view_targets,
                material_samples.join("; "),
                prepared_material_samples.join("; "),
            ),
        );
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
    Color::srgba(r, g, b, a)
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
                    debug::log(
                        LogLevel::Warn,
                        format_args!(
                            "cube_text_preview image material missing image_index={}",
                            material.image_index,
                        ),
                    );
                    None
                } else {
                    match scene.images.get(material.image_index as usize) {
                        Some(source) => image_from_preview_image(source),
                        None => {
                            debug::log(
                                LogLevel::Warn,
                                format_args!(
                                    "cube_text_preview image_index={} out of range images={}",
                                    material.image_index,
                                    scene.images.len(),
                                ),
                            );
                            None
                        }
                    }
                }
            }
            CubeTextPreviewMaterialMode::Color => None,
        }?;
        let mut images = self.app.world_mut().resource_mut::<Assets<Image>>();
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
            let Some(data) = image.data.as_mut() else {
                continue;
            };
            data[offset] = ((color >> 24) & 0xFF) as u8;
            data[offset + 1] = ((color >> 16) & 0xFF) as u8;
            data[offset + 2] = ((color >> 8) & 0xFF) as u8;
            data[offset + 3] = (color & 0xFF) as u8;
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
        debug::log(
            LogLevel::Warn,
            format_args!(
                "cube_text_preview image invalid width={} height={} len={} expected={expected_len}",
                source.width,
                source.height,
                source.rgba.len(),
            ),
        );
        return None;
    }
    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview create image texture width={} height={} len={}",
            source.width,
            source.height,
            source.rgba.len(),
        ),
    );
    let mut image = Image::new(
        Extent3d {
            width: source.width,
            height: source.height,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        source.rgba.clone(),
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    );
    image.texture_descriptor.usage =
        wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST;
    image.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
        address_mode_u: ImageAddressMode::Repeat,
        address_mode_v: ImageAddressMode::Repeat,
        address_mode_w: ImageAddressMode::ClampToEdge,
        mag_filter: ImageFilterMode::Linear,
        min_filter: ImageFilterMode::Linear,
        ..Default::default()
    });
    Some(image)
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

fn create_checkerboard_pipeline(
    device: &wgpu::Device,
    format: wgpu::TextureFormat,
) -> wgpu::RenderPipeline {
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("misa-rin cube text checkerboard shader"),
        source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(
            r#"
struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(-1.0, 1.0),
        vec2<f32>(3.0, 1.0)
    );
    var out: VertexOut;
    let position = positions[vertex_index];
    out.position = vec4<f32>(position, 0.0, 1.0);
    out.uv = position * 0.5 + vec2<f32>(0.5, 0.5);
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let cell = floor(in.position.xy / vec2<f32>(14.0, 14.0));
    let odd = (u32(cell.x) + u32(cell.y)) & 1u;
    let light = vec3<f32>(0.88, 0.91, 0.95);
    let dark = vec3<f32>(0.72, 0.77, 0.84);
    let color = select(light, dark, odd == 1u);
    return vec4<f32>(color, 1.0);
}
"#,
        )),
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("misa-rin cube text checkerboard pipeline layout"),
        bind_group_layouts: &[],
        push_constant_ranges: &[],
    });
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        cache: None,
        label: Some("misa-rin cube text checkerboard pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs_main"),
            compilation_options: wgpu::PipelineCompilationOptions::default(),
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs_main"),
            compilation_options: wgpu::PipelineCompilationOptions::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState {
            topology: wgpu::PrimitiveTopology::TriangleList,
            strip_index_format: None,
            front_face: wgpu::FrontFace::Ccw,
            cull_mode: None,
            unclipped_depth: false,
            polygon_mode: wgpu::PolygonMode::Fill,
            conservative: false,
        },
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
    })
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

impl CubeTextPreviewMaterial {
    pub(crate) fn is_image_mode(&self) -> bool {
        self.mode == CubeTextPreviewMaterialMode::Image
    }

    fn mode_name(&self) -> &'static str {
        match self.mode {
            CubeTextPreviewMaterialMode::Color => "color",
            CubeTextPreviewMaterialMode::Gradient => "gradient",
            CubeTextPreviewMaterialMode::Image => "image",
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
