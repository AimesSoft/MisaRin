use std::borrow::Cow;
use std::collections::BTreeMap;
use std::sync::{mpsc, Arc, Mutex};

use bevy::asset::{AssetPlugin, Assets};
use bevy::core_pipeline::core_3d::{
    graph::{Core3d, Node3d},
    AlphaMask3d, Opaque3d, Transmissive3d, Transparent3d,
};
use bevy::core_pipeline::CorePipelinePlugin;
use bevy::pbr::{
    queue_material_meshes, DefaultOpaqueRendererMethod, MaterialPipeline, OpaqueRendererMethod,
    PbrBundle, PbrPlugin, RenderMaterialInstances, RenderMaterials, RenderMeshInstances,
    StandardMaterial, MESH_SHADER_HANDLE, PBR_SHADER_HANDLE,
};
use bevy::prelude::*;
use bevy::render::camera::{
    ManualTextureView, ManualTextureViewHandle, ManualTextureViews, RenderTarget,
};
use bevy::render::mesh::{Indices, Mesh};
use bevy::render::render_asset::RenderAssetUsages;
use bevy::render::render_asset::RenderAssets;
use bevy::render::render_graph::{
    Node, NodeRunError, RenderGraphApp, RenderGraphContext, RenderLabel,
};
use bevy::render::render_phase::{PhaseItem, RenderPhase};
use bevy::render::render_resource::PipelineCache;
use bevy::render::render_resource::{
    Buffer, CachedPipelineState, Extent3d, Face, OwnedBindingResource, Pipeline, PrimitiveTopology,
    TextureDimension, TextureFormat,
};
use bevy::render::renderer::{
    RenderAdapter, RenderAdapterInfo, RenderContext, RenderDevice, RenderInstance, RenderQueue,
};
use bevy::render::settings::RenderCreation;
use bevy::render::texture::{
    FallbackImage, Image, ImageAddressMode, ImageFilterMode, ImageSampler, ImageSamplerDescriptor,
};
use bevy::render::view::{NoFrustumCulling, ViewTarget, VisibleEntities};
use bevy::render::{Render, RenderApp, RenderPlugin, RenderSet};
use bevy::window::{WindowClosed, WindowCreated, WindowResized, WindowScaleFactorChanged};
use serde::Deserialize;
use wgpu::TextureViewDimension;

use crate::gpu::debug::{self, LogLevel};
use crate::gpu::shared_device::SharedRenderDevice;

const MANUAL_VIEW_HANDLE: ManualTextureViewHandle = ManualTextureViewHandle(0xC0BE_0001);
const GRADIENT_TEXTURE_HEIGHT: u32 = 256;
const GRADIENT_TEXTURE_WIDTH: u32 = 4;
const TARGET_GRID_SAMPLE_COLUMNS: u32 = 9;
const TARGET_GRID_SAMPLE_ROWS: u32 = 9;
const READBACK_BYTES_PER_PIXEL: u32 = 4;
const READBACK_BYTES_PER_ROW_ALIGNMENT: u32 = 256;
const TARGET_NON_TRANSPARENT_DETAIL_LIMIT: usize = 24;

#[derive(Debug, Hash, PartialEq, Eq, Clone, RenderLabel)]
enum CubeTextPreviewGraphNode {
    BeforeOpaqueProbe,
    AfterMainPassProbe,
    AfterUpscalingProbe,
}

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
    target_sample_log_remaining: u8,
    view_target_sample_log_remaining: u8,
}

#[derive(Resource, Default)]
struct CubeTextPreviewQueueDiagnostics {
    remaining_frames: u8,
}

#[derive(Resource, Default)]
struct CubeTextPreviewGraphReadbacks {
    inner: Mutex<CubeTextPreviewGraphReadbackState>,
}

#[derive(Default)]
struct CubeTextPreviewGraphReadbackState {
    remaining_captures: u8,
    pending: Vec<CubeTextPreviewGraphReadbackRequest>,
}

struct CubeTextPreviewGraphReadbackRequest {
    stage: String,
    texture_label: String,
    view_entity: Entity,
    width: u32,
    height: u32,
    format: TextureFormat,
    points: Vec<TargetSamplePoint>,
    buffer: Buffer,
    buffer_size: u64,
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
        let checkerboard_pipeline =
            create_checkerboard_pipeline(device.as_ref(), format.add_srgb_suffix());

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

        app.world
            .insert_resource(DefaultOpaqueRendererMethod::forward());
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

        if let Ok(render_app) = app.get_sub_app_mut(RenderApp) {
            render_app
                .init_resource::<CubeTextPreviewQueueDiagnostics>()
                .init_resource::<CubeTextPreviewGraphReadbacks>()
                .add_systems(
                    Render,
                    log_cube_text_preview_queue_state
                        .in_set(RenderSet::QueueMeshes)
                        .after(queue_material_meshes::<StandardMaterial>),
                )
                .add_systems(
                    Render,
                    drain_cube_text_preview_graph_readbacks
                        .in_set(RenderSet::Cleanup)
                        .before(World::clear_entities),
                )
                .add_render_graph_node::<CubeTextPreviewBeforeOpaqueProbeNode>(
                    Core3d,
                    CubeTextPreviewGraphNode::BeforeOpaqueProbe,
                )
                .add_render_graph_node::<CubeTextPreviewAfterMainPassProbeNode>(
                    Core3d,
                    CubeTextPreviewGraphNode::AfterMainPassProbe,
                )
                .add_render_graph_node::<CubeTextPreviewAfterUpscalingProbeNode>(
                    Core3d,
                    CubeTextPreviewGraphNode::AfterUpscalingProbe,
                )
                .add_render_graph_edge(
                    Core3d,
                    Node3d::StartMainPass,
                    CubeTextPreviewGraphNode::BeforeOpaqueProbe,
                )
                .add_render_graph_edge(
                    Core3d,
                    CubeTextPreviewGraphNode::BeforeOpaqueProbe,
                    Node3d::MainOpaquePass,
                )
                .add_render_graph_edge(
                    Core3d,
                    Node3d::EndMainPass,
                    CubeTextPreviewGraphNode::AfterMainPassProbe,
                )
                .add_render_graph_edge(
                    Core3d,
                    CubeTextPreviewGraphNode::AfterMainPassProbe,
                    Node3d::Tonemapping,
                )
                .add_render_graph_edge(
                    Core3d,
                    Node3d::Upscaling,
                    CubeTextPreviewGraphNode::AfterUpscalingProbe,
                );
        }

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
            target_sample_log_remaining: 0,
            view_target_sample_log_remaining: 0,
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
        self.log_bevy_view_target_samples();
        self.log_target_texture_samples(target_texture, width, height);
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
            format: view_format,
        };
        self.app
            .world
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
            let uv_stats = UvStats::from_uvs(&chunk.uvs);
            mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, chunk.uvs);
            mesh.insert_indices(Indices::U32(
                (0..chunk.vertex_count as u32).collect::<Vec<u32>>(),
            ));

            let spec = material_spec(scene, material_index);
            let texture = self.material_texture(spec, scene);
            let texture_id = texture.as_ref().map(|handle| format!("{:?}", handle.id()));
            let color = material_color(spec);
            let slot = material_index % 7;
            let texture_samples = material_texture_samples(spec, scene);
            debug::log(
                LogLevel::Info,
                format_args!(
                    "cube_text_preview material[{material_index}] mode={} image_index={} color=0x{:08X} gradient_start=0x{:08X} gradient_end=0x{:08X} texture={} texture_id={} vertices={} texture_samples=[{}]",
                    spec.mode_name(),
                    spec.image_index,
                    spec.color,
                    spec.gradient_start,
                    spec.gradient_end,
                    texture.is_some(),
                    texture_id.as_deref().unwrap_or("none"),
                    chunk.vertex_count,
                    texture_samples,
                ),
            );
            debug::log(
                LogLevel::Info,
                format_args!(
                    "cube_text_preview material[{material_index}] uv_stats min=({:.3},{:.3}) max=({:.3},{:.3}) first=({:.3},{:.3}) mid=({:.3},{:.3}) last=({:.3},{:.3})",
                    uv_stats.min[0],
                    uv_stats.min[1],
                    uv_stats.max[0],
                    uv_stats.max[1],
                    uv_stats.first[0],
                    uv_stats.first[1],
                    uv_stats.mid[0],
                    uv_stats.mid[1],
                    uv_stats.last[0],
                    uv_stats.last[1],
                ),
            );
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
                .world
                .spawn(PbrBundle {
                    mesh: mesh_handle,
                    material: material_handle,
                    transform: Transform::IDENTITY,
                    ..default()
                })
                .insert(NoFrustumCulling)
                .id();
            self.mesh_entities.push(entity);
        }

        self.scene_key = Some(key);
        self.scene_just_rebuilt = true;
        self.render_debug_logged = false;
        self.target_sample_log_remaining = 3;
        self.view_target_sample_log_remaining = 3;
        if let Ok(render_app) = self.app.get_sub_app_mut(RenderApp) {
            render_app
                .world
                .resource_mut::<CubeTextPreviewQueueDiagnostics>()
                .remaining_frames = 2;
            let readbacks = render_app.world.resource::<CubeTextPreviewGraphReadbacks>();
            if let Ok(mut state) = readbacks.inner.lock() {
                state.remaining_captures = 2;
                state.pending.clear();
            };
        }
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
                    Color::NONE
                } else {
                    Color::rgb(0.97, 0.97, 0.97)
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
            let materials = self.app.world.resource::<Assets<StandardMaterial>>();
            main_material_asset_count = materials.iter().count();
            let images = self.app.world.resource::<Assets<Image>>();
            main_image_asset_count = images.iter().count();
            for &entity in &self.mesh_entities {
                let Some(entity_ref) = self.app.world.get_entity(entity) else {
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
                let Some(handle) = entity_ref.get::<Handle<StandardMaterial>>() else {
                    continue;
                };
                material_entity_count += 1;
                if material_samples.len() < 4 {
                    if let Some(material) = materials.get(handle) {
                        material_samples.push(format!(
                            "{entity:?}:id={:?}:color={:?}:texture={}:unlit={}:fog={}:opaque={:?}",
                            handle.id(),
                            material.base_color,
                            material.base_color_texture.is_some(),
                            material.unlit,
                            material.fog_enabled,
                            material.opaque_render_method,
                        ));
                    } else {
                        material_samples.push(format!("{entity:?}:id={:?}:missing", handle.id()));
                    }
                }
                if handle.id() == Handle::<StandardMaterial>::default().id() {
                    default_material_count += 1;
                }
                if materials
                    .get(handle)
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
        let mut opaque_phase_items = 0usize;
        let mut alpha_mask_phase_items = 0usize;
        let mut transmissive_phase_items = 0usize;
        let mut transparent_phase_items = 0usize;
        let mut pipeline_ok = 0usize;
        let mut pipeline_queued = 0usize;
        let mut pipeline_creating = 0usize;
        let mut pipeline_err = 0usize;
        let mut prepared_material_samples = Vec::new();
        if let Ok(render_app) = self.app.get_sub_app_mut(RenderApp) {
            if let Some(instances) = render_app
                .world
                .get_resource::<RenderMaterialInstances<StandardMaterial>>()
            {
                render_material_instances = instances.len();
            }
            if let Some(materials) = render_app
                .world
                .get_resource::<RenderMaterials<StandardMaterial>>()
            {
                render_materials = materials.iter().count();
                for (asset_id, material) in materials.iter().take(4) {
                    prepared_material_samples.push(format!(
                        "{asset_id:?}:render={:?}:alpha={:?}:bindings={}",
                        material.properties.render_method,
                        material.properties.alpha_mode,
                        material.bindings.len(),
                    ));
                }
            }
            if let Some(meshes) = render_app.world.get_resource::<RenderAssets<Mesh>>() {
                render_meshes = meshes.iter().count();
            }
            if let Some(images) = render_app.world.get_resource::<RenderAssets<Image>>() {
                render_images = images.iter().count();
            }
            let mut query = render_app.world.query::<&VisibleEntities>();
            for visible_entities in query.iter(&render_app.world) {
                render_visible_entities += visible_entities.entities.len();
            }
            let mut view_query = render_app.world.query::<(
                Option<&RenderPhase<Opaque3d>>,
                Option<&RenderPhase<AlphaMask3d>>,
                Option<&RenderPhase<Transmissive3d>>,
                Option<&RenderPhase<Transparent3d>>,
                Option<&ViewTarget>,
            )>();
            let mut pipeline_ids = Vec::new();
            for (opaque, alpha_mask, transmissive, transparent, view_target) in
                view_query.iter(&render_app.world)
            {
                if view_target.is_some() {
                    view_targets += 1;
                }
                if let Some(phase) = opaque {
                    opaque_phase_items += phase.items.len();
                    for item in phase.items.iter().take(8) {
                        pipeline_ids.push(item.pipeline);
                    }
                }
                if let Some(phase) = alpha_mask {
                    alpha_mask_phase_items += phase.items.len();
                    for item in phase.items.iter().take(8) {
                        pipeline_ids.push(item.pipeline);
                    }
                }
                if let Some(phase) = transmissive {
                    transmissive_phase_items += phase.items.len();
                    for item in phase.items.iter().take(8) {
                        pipeline_ids.push(item.pipeline);
                    }
                }
                if let Some(phase) = transparent {
                    transparent_phase_items += phase.items.len();
                    for item in phase.items.iter().take(8) {
                        pipeline_ids.push(item.pipeline);
                    }
                }
            }
            if let Some(pipeline_cache) = render_app.world.get_resource::<PipelineCache>() {
                for pipeline_id in pipeline_ids {
                    match pipeline_cache.get_render_pipeline_state(pipeline_id) {
                        CachedPipelineState::Ok(Pipeline::RenderPipeline(_)) => pipeline_ok += 1,
                        CachedPipelineState::Queued => pipeline_queued += 1,
                        CachedPipelineState::Creating(_) => pipeline_creating += 1,
                        CachedPipelineState::Err(_) => pipeline_err += 1,
                        CachedPipelineState::Ok(_) => pipeline_err += 1,
                    }
                }
            }
        }

        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview render state entities={} main_material_assets={} main_image_assets={} material_entities={} visible={} hidden={} default_material_handles={} textured_main_materials={} render_instances={} render_materials={} render_meshes={} render_images={} render_visible_entities={} view_targets={} phase_opaque={} phase_alpha={} phase_transmissive={} phase_transparent={} pipeline_ok={} pipeline_queued={} pipeline_creating={} pipeline_err={} material_samples=[{}] prepared_material_samples=[{}]",
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
                opaque_phase_items,
                alpha_mask_phase_items,
                transmissive_phase_items,
                transparent_phase_items,
                pipeline_ok,
                pipeline_queued,
                pipeline_creating,
                pipeline_err,
                material_samples.join("; "),
                prepared_material_samples.join("; "),
            ),
        );
    }

    fn log_target_texture_samples(
        &mut self,
        target_texture: &wgpu::Texture,
        width: u32,
        height: u32,
    ) {
        if self.target_sample_log_remaining == 0 || debug::level() < LogLevel::Info {
            return;
        }
        self.target_sample_log_remaining -= 1;
        if width == 0 || height == 0 {
            return;
        }
        let points = target_sample_points(width, height);
        let mut samples = Vec::new();
        let mut stats = TargetSampleStats::default();
        for point in points {
            match read_bgra_texture_pixel(
                self.device.as_ref(),
                self.queue.as_ref(),
                target_texture,
                width,
                height,
                self.format,
                point.x,
                point.y,
            ) {
                Ok(pixel) => {
                    stats.push(pixel, &point.label, point.x, point.y, self.format);
                    if point.log_label {
                        samples.push(format!(
                            "{}@{},{}=ARGB#{pixel:08X}/{}({},{},{},{})",
                            point.label,
                            point.x,
                            point.y,
                            format_pixel_channels(self.format),
                            (pixel >> 16) & 0xFF,
                            (pixel >> 8) & 0xFF,
                            pixel & 0xFF,
                            (pixel >> 24) & 0xFF,
                        ));
                    }
                }
                Err(err) => samples.push(format!(
                    "{}@{},{}=ERR({err})",
                    point.label, point.x, point.y
                )),
            }
        }
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview target samples frame_remaining={} size={}x{} format={:?} stats={} samples=[{}]",
                self.target_sample_log_remaining,
                width,
                height,
                self.format,
                stats.summary(),
                samples.join("; "),
            ),
        );
    }

    fn log_bevy_view_target_samples(&mut self) {
        if self.view_target_sample_log_remaining == 0 || debug::level() < LogLevel::Info {
            return;
        }
        self.view_target_sample_log_remaining -= 1;
        let Ok(render_app) = self.app.get_sub_app_mut(RenderApp) else {
            return;
        };
        let mut query = render_app.world.query::<(Entity, &ViewTarget)>();
        let Some((view_entity, view_target)) = query.iter(&render_app.world).next() else {
            debug::log(
                LogLevel::Warn,
                format_args!("cube_text_preview bevy view target samples missing view_target"),
            );
            return;
        };
        let Some(texture) = view_target.sampled_main_texture() else {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "cube_text_preview bevy view target samples view={view_entity:?} missing sampled_main_texture main_format={:?} out_format={:?}",
                    view_target.main_texture_format(),
                    view_target.out_texture_format(),
                ),
            );
            return;
        };
        let width = texture.width();
        let height = texture.height();
        if width == 0 || height == 0 {
            return;
        }
        let points = target_sample_points(width, height);
        let mut samples = Vec::new();
        let mut stats = TargetSampleStats::default();
        for point in points {
            match read_bgra_texture_pixel(
                self.device.as_ref(),
                self.queue.as_ref(),
                texture,
                width,
                height,
                view_target.main_texture_format(),
                point.x,
                point.y,
            ) {
                Ok(pixel) => {
                    stats.push(
                        pixel,
                        &point.label,
                        point.x,
                        point.y,
                        view_target.main_texture_format(),
                    );
                    if point.log_label {
                        samples.push(format!(
                            "{}@{},{}=ARGB#{pixel:08X}/{}({},{},{},{})",
                            point.label,
                            point.x,
                            point.y,
                            format_pixel_channels(view_target.main_texture_format()),
                            (pixel >> 16) & 0xFF,
                            (pixel >> 8) & 0xFF,
                            pixel & 0xFF,
                            (pixel >> 24) & 0xFF,
                        ));
                    }
                }
                Err(err) => samples.push(format!(
                    "{}@{},{}=ERR({err})",
                    point.label, point.x, point.y
                )),
            }
        }
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview bevy view target samples frame_remaining={} view={view_entity:?} size={}x{} main_format={:?} out_format={:?} sampled_tex={:?} sampled_view={:?} stats={} samples=[{}]",
                self.view_target_sample_log_remaining,
                width,
                height,
                view_target.main_texture_format(),
                view_target.out_texture_format(),
                texture.id(),
                view_target
                    .sampled_main_texture_view()
                    .map(|texture_view| texture_view.id()),
                stats.summary(),
                samples.join("; "),
            ),
        );
    }
}

fn log_cube_text_preview_queue_state(
    mut diagnostics: ResMut<CubeTextPreviewQueueDiagnostics>,
    material_pipeline: Res<MaterialPipeline<StandardMaterial>>,
    render_material_instances: Res<RenderMaterialInstances<StandardMaterial>>,
    render_materials: Res<RenderMaterials<StandardMaterial>>,
    render_mesh_instances: Res<RenderMeshInstances>,
    render_images: Res<RenderAssets<Image>>,
    fallback_image: Res<FallbackImage>,
    views: Query<(
        Entity,
        &VisibleEntities,
        Option<&RenderPhase<Opaque3d>>,
        Option<&RenderPhase<AlphaMask3d>>,
        Option<&RenderPhase<Transmissive3d>>,
        Option<&RenderPhase<Transparent3d>>,
        Option<&ViewTarget>,
    )>,
) {
    if diagnostics.remaining_frames == 0 || debug::level() < LogLevel::Info {
        return;
    }
    diagnostics.remaining_frames -= 1;

    let pbr_shader_id = PBR_SHADER_HANDLE.id();
    let mesh_shader_id = MESH_SHADER_HANDLE.id();
    let material_fragment_shader = material_pipeline
        .fragment_shader
        .as_ref()
        .map(|handle| format!("{:?}", handle.id()))
        .unwrap_or_else(|| "none".to_string());

    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview queue pipeline material_fragment_shader={} expected_pbr={:?} mesh_shader={:?} render_material_instances={} render_materials={} render_mesh_instances={}",
            material_fragment_shader,
            pbr_shader_id,
            mesh_shader_id,
            render_material_instances.len(),
            render_materials.iter().count(),
            render_mesh_instances.len(),
        ),
    );
    log_cube_text_preview_fallback_image(&fallback_image);

    let default_material_id = Handle::<StandardMaterial>::default().id();
    let mut view_count = 0usize;
    for (
        view_entity,
        visible_entities,
        opaque,
        alpha_mask,
        transmissive,
        transparent,
        view_target,
    ) in &views
    {
        view_count += 1;
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview queue view={view_entity:?} visible={} view_target={} phase_opaque={} phase_alpha={} phase_transmissive={} phase_transparent={}",
                visible_entities.len(),
                view_target.is_some(),
                opaque.map(|phase| phase.items.len()).unwrap_or(0),
                alpha_mask.map(|phase| phase.items.len()).unwrap_or(0),
                transmissive.map(|phase| phase.items.len()).unwrap_or(0),
                transparent.map(|phase| phase.items.len()).unwrap_or(0),
            ),
        );

        log_cube_text_preview_phase_items(
            "opaque",
            opaque.map(|phase| phase.items.as_slice()).unwrap_or(&[]),
            &render_material_instances,
            &render_materials,
            &render_mesh_instances,
            &render_images,
            &fallback_image,
            default_material_id,
        );
        log_cube_text_preview_phase_items(
            "alpha",
            alpha_mask
                .map(|phase| phase.items.as_slice())
                .unwrap_or(&[]),
            &render_material_instances,
            &render_materials,
            &render_mesh_instances,
            &render_images,
            &fallback_image,
            default_material_id,
        );
        log_cube_text_preview_phase_items(
            "transmissive",
            transmissive
                .map(|phase| phase.items.as_slice())
                .unwrap_or(&[]),
            &render_material_instances,
            &render_materials,
            &render_mesh_instances,
            &render_images,
            &fallback_image,
            default_material_id,
        );
        log_cube_text_preview_phase_items(
            "transparent",
            transparent
                .map(|phase| phase.items.as_slice())
                .unwrap_or(&[]),
            &render_material_instances,
            &render_materials,
            &render_mesh_instances,
            &render_images,
            &fallback_image,
            default_material_id,
        );
    }

    if view_count == 0 {
        debug::log(
            LogLevel::Warn,
            format_args!("cube_text_preview queue view_count=0"),
        );
    }
}

fn log_cube_text_preview_phase_items<I: PhaseItem + CubeTextPreviewPhaseItemDebug>(
    phase_name: &str,
    items: &[I],
    render_material_instances: &RenderMaterialInstances<StandardMaterial>,
    render_materials: &RenderMaterials<StandardMaterial>,
    render_mesh_instances: &RenderMeshInstances,
    render_images: &RenderAssets<Image>,
    fallback_image: &FallbackImage,
    default_material_id: bevy::asset::AssetId<StandardMaterial>,
) {
    for item in items.iter().take(16) {
        let entity = item.entity();
        let material_asset_id = render_material_instances.get(&entity).copied();
        let prepared_material =
            material_asset_id.and_then(|asset_id| render_materials.get(&asset_id));
        let mesh_instance = render_mesh_instances.get(&entity);
        let material_status = match material_asset_id {
            Some(asset_id) => {
                let prepared = prepared_material.is_some();
                let is_default = asset_id == default_material_id;
                let bindings = prepared_material
                    .map(|material| material.bindings.len())
                    .unwrap_or(0);
                let alpha = prepared_material
                    .map(|material| format!("{:?}", material.properties.alpha_mode))
                    .unwrap_or_else(|| "missing".to_string());
                let render_method = prepared_material
                    .map(|material| format!("{:?}", material.properties.render_method))
                    .unwrap_or_else(|| "missing".to_string());
                let bind_group_id = prepared_material
                    .map(|material| format!("{:?}", material.bind_group.id()))
                    .unwrap_or_else(|| "none".to_string());
                let material_flags = prepared_material
                    .map(|material| material_debug_flags(material, render_images, fallback_image))
                    .unwrap_or_else(|| "missing".to_string());
                let binding_summary = prepared_material
                    .map(|material| {
                        prepared_material_binding_summary(material, render_images, fallback_image)
                    })
                    .unwrap_or_else(|| "none".to_string());
                format!(
                    "material_id={asset_id:?}:prepared={prepared}:default={is_default}:bindings={bindings}:alpha={alpha}:render={render_method}:bind_group={bind_group_id}:flags=[{material_flags}]:binding_summary=[{binding_summary}]"
                )
            }
            None => "material_id=missing".to_string(),
        };
        let mesh_bind_group_id = mesh_instance
            .map(|mesh| {
                if mesh.material_bind_group_id.is_some() {
                    "present".to_string()
                } else {
                    "none".to_string()
                }
            })
            .unwrap_or_else(|| "missing".to_string());

        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview queue item phase={} entity={entity:?} pipeline_id={} draw_function={:?} mesh_material_bind_group={} {}",
                phase_name,
                item.pipeline_id().id(),
                item.draw_function(),
                mesh_bind_group_id,
                material_status,
            ),
        );
    }
}

fn prepared_material_binding_summary(
    material: &bevy::pbr::PreparedMaterial<StandardMaterial>,
    render_images: &RenderAssets<Image>,
    fallback_image: &FallbackImage,
) -> String {
    let mut parts = Vec::new();
    let fallback_d2_view = fallback_image.d2.texture_view.id();
    let fallback_d2_sampler = fallback_image.d2.sampler.id();
    for (binding, resource) in &material.bindings {
        let detail = match resource {
            OwnedBindingResource::Buffer(buffer) => format!("buffer:{:?}", buffer.id()),
            OwnedBindingResource::TextureView(view) => {
                let view_id = view.id();
                let source = render_images
                    .iter()
                    .find(|(_, image)| image.texture_view.id() == view_id)
                    .map(|(asset_id, image)| {
                        format!(
                            "image:{asset_id:?}:tex={:?}:fmt={:?}:size={:.0}x{:.0}:mips={}:sampler={:?}",
                            image.texture.id(),
                            image.texture_format,
                            image.size.x,
                            image.size.y,
                            image.mip_level_count,
                            image.sampler.id(),
                        )
                    })
                    .unwrap_or_else(|| {
                        if view_id == fallback_d2_view {
                            "fallback_d2".to_string()
                        } else {
                            "unknown".to_string()
                        }
                    });
                format!("texture_view:{view_id:?}:{source}")
            }
            OwnedBindingResource::Sampler(sampler) => {
                let sampler_id = sampler.id();
                let source = render_images
                    .iter()
                    .find(|(_, image)| image.sampler.id() == sampler_id)
                    .map(|(asset_id, _)| format!("image:{asset_id:?}"))
                    .unwrap_or_else(|| {
                        if sampler_id == fallback_d2_sampler {
                            "fallback_d2".to_string()
                        } else {
                            "unknown".to_string()
                        }
                    });
                format!("sampler:{sampler_id:?}:{source}")
            }
        };
        parts.push(format!("{binding}={detail}"));
    }
    parts.join(",")
}

fn material_debug_flags(
    material: &bevy::pbr::PreparedMaterial<StandardMaterial>,
    render_images: &RenderAssets<Image>,
    fallback_image: &FallbackImage,
) -> String {
    let fallback_d2_view = fallback_image.d2.texture_view.id();
    let has_texture_binding = material.bindings.iter().any(|(binding, resource)| {
        *binding == 1
            && matches!(
                resource,
                OwnedBindingResource::TextureView(view)
                    if view.id() != fallback_d2_view
                        && render_images
                            .iter()
                            .any(|(_, image)| image.texture_view.id() == view.id())
            )
    });
    let bits = ((has_texture_binding as u32) << 0) | (1 << 4) | (1 << 5);
    format!(
        "expected_bits=0x{bits:08X}:base_color_texture={has_texture_binding}:double_sided=true:unlit=true:alpha=opaque"
    )
}

fn log_cube_text_preview_fallback_image(fallback_image: &FallbackImage) {
    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview fallback_image d2 tex={:?} view={:?} sampler={:?} format={:?} size={:.0}x{:.0} mips={}",
            fallback_image.d2.texture.id(),
            fallback_image.d2.texture_view.id(),
            fallback_image.d2.sampler.id(),
            fallback_image.d2.texture_format,
            fallback_image.d2.size.x,
            fallback_image.d2.size.y,
            fallback_image.d2.mip_level_count,
        ),
    );
}

trait CubeTextPreviewPhaseItemDebug {
    fn pipeline_id(&self) -> bevy::render::render_resource::CachedRenderPipelineId;
}

impl CubeTextPreviewPhaseItemDebug for Opaque3d {
    fn pipeline_id(&self) -> bevy::render::render_resource::CachedRenderPipelineId {
        self.pipeline
    }
}

impl CubeTextPreviewPhaseItemDebug for AlphaMask3d {
    fn pipeline_id(&self) -> bevy::render::render_resource::CachedRenderPipelineId {
        self.pipeline
    }
}

impl CubeTextPreviewPhaseItemDebug for Transmissive3d {
    fn pipeline_id(&self) -> bevy::render::render_resource::CachedRenderPipelineId {
        self.pipeline
    }
}

impl CubeTextPreviewPhaseItemDebug for Transparent3d {
    fn pipeline_id(&self) -> bevy::render::render_resource::CachedRenderPipelineId {
        self.pipeline
    }
}

struct CubeTextPreviewBeforeOpaqueProbeNode;

impl FromWorld for CubeTextPreviewBeforeOpaqueProbeNode {
    fn from_world(_world: &mut World) -> Self {
        Self
    }
}

impl Node for CubeTextPreviewBeforeOpaqueProbeNode {
    fn run<'w>(
        &self,
        graph: &mut RenderGraphContext,
        _render_context: &mut RenderContext<'w>,
        world: &'w World,
    ) -> Result<(), NodeRunError> {
        if debug::level() < LogLevel::Info {
            return Ok(());
        }
        let Some(view_entity) = graph.get_view_entity() else {
            debug::log(
                LogLevel::Warn,
                format_args!("cube_text_preview graph before_opaque missing view_entity"),
            );
            return Ok(());
        };
        log_cube_text_preview_graph_probe("before_opaque", view_entity, world);
        Ok(())
    }
}

struct CubeTextPreviewAfterMainPassProbeNode;

impl FromWorld for CubeTextPreviewAfterMainPassProbeNode {
    fn from_world(_world: &mut World) -> Self {
        Self
    }
}

impl Node for CubeTextPreviewAfterMainPassProbeNode {
    fn run<'w>(
        &self,
        graph: &mut RenderGraphContext,
        render_context: &mut RenderContext<'w>,
        world: &'w World,
    ) -> Result<(), NodeRunError> {
        if debug::level() < LogLevel::Info {
            return Ok(());
        }
        let Some(view_entity) = graph.get_view_entity() else {
            debug::log(
                LogLevel::Warn,
                format_args!("cube_text_preview graph after_main_pass missing view_entity"),
            );
            return Ok(());
        };
        log_cube_text_preview_graph_probe("after_main_pass", view_entity, world);
        capture_cube_text_preview_graph_targets(
            "after_main_pass",
            view_entity,
            render_context,
            world,
        );
        Ok(())
    }
}

struct CubeTextPreviewAfterUpscalingProbeNode;

impl FromWorld for CubeTextPreviewAfterUpscalingProbeNode {
    fn from_world(_world: &mut World) -> Self {
        Self
    }
}

impl Node for CubeTextPreviewAfterUpscalingProbeNode {
    fn run<'w>(
        &self,
        graph: &mut RenderGraphContext,
        render_context: &mut RenderContext<'w>,
        world: &'w World,
    ) -> Result<(), NodeRunError> {
        if debug::level() < LogLevel::Info {
            return Ok(());
        }
        let Some(view_entity) = graph.get_view_entity() else {
            debug::log(
                LogLevel::Warn,
                format_args!("cube_text_preview graph after_upscaling missing view_entity"),
            );
            return Ok(());
        };
        log_cube_text_preview_graph_probe("after_upscaling", view_entity, world);
        capture_cube_text_preview_graph_targets(
            "after_upscaling",
            view_entity,
            render_context,
            world,
        );
        Ok(())
    }
}

fn log_cube_text_preview_graph_probe(stage: &str, view_entity: Entity, world: &World) {
    let Some(entity_ref) = world.get_entity(view_entity) else {
        debug::log(
            LogLevel::Warn,
            format_args!("cube_text_preview graph {stage} view={view_entity:?} missing entity"),
        );
        return;
    };
    let view_target = entity_ref.get::<ViewTarget>();
    let opaque = entity_ref.get::<RenderPhase<Opaque3d>>();
    let alpha_mask = entity_ref.get::<RenderPhase<AlphaMask3d>>();
    let transmissive = entity_ref.get::<RenderPhase<Transmissive3d>>();
    let transparent = entity_ref.get::<RenderPhase<Transparent3d>>();
    let visible = entity_ref.get::<VisibleEntities>().map(|items| items.len());

    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview graph {stage} view={view_entity:?} view_target={} visible={:?} main_format={:?} out_format={:?} sampled_main={} phase_opaque={} phase_alpha={} phase_transmissive={} phase_transparent={}",
            view_target.is_some(),
            visible,
            view_target.map(|target| target.main_texture_format()),
            view_target.map(|target| target.out_texture_format()),
            view_target.and_then(|target| target.sampled_main_texture()).is_some(),
            opaque.map(|phase| phase.items.len()).unwrap_or(0),
            alpha_mask.map(|phase| phase.items.len()).unwrap_or(0),
            transmissive.map(|phase| phase.items.len()).unwrap_or(0),
            transparent.map(|phase| phase.items.len()).unwrap_or(0),
        ),
    );
    if let Some(target) = view_target {
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview graph {stage} target_ids main_tex={:?} main_view={:?} sampled_tex={:?} sampled_view={:?} out_view={:?}",
                target.main_texture().id(),
                target.main_texture_view().id(),
                target.sampled_main_texture().map(|texture| texture.id()),
                target
                    .sampled_main_texture_view()
                    .map(|texture_view| texture_view.id()),
                target.out_texture().id(),
            ),
        );
    }

    if let Some(phase) = opaque {
        for item in phase.items.iter().take(8) {
            log_cube_text_preview_graph_pipeline(stage, item.entity(), item.pipeline_id(), world);
        }
    }
}

fn capture_cube_text_preview_graph_targets(
    stage: &str,
    view_entity: Entity,
    render_context: &mut RenderContext<'_>,
    world: &World,
) {
    let Some(readbacks) = world.get_resource::<CubeTextPreviewGraphReadbacks>() else {
        return;
    };
    let mut state = match readbacks.inner.lock() {
        Ok(state) => state,
        Err(_) => {
            debug::log(
                LogLevel::Warn,
                format_args!("cube_text_preview graph {stage} readback lock poisoned"),
            );
            return;
        }
    };
    if state.remaining_captures == 0 {
        return;
    }
    let Some(entity_ref) = world.get_entity(view_entity) else {
        return;
    };
    let Some(view_target) = entity_ref.get::<ViewTarget>() else {
        return;
    };

    let main_format = view_target.main_texture_format();
    enqueue_cube_text_preview_graph_readback(
        &mut state,
        stage,
        "main",
        view_entity,
        view_target.main_texture(),
        main_format,
        render_context,
    );
    if let Some(sampled_main) = view_target.sampled_main_texture() {
        debug::log(
            LogLevel::Info,
            format_args!(
                "cube_text_preview graph {stage} readback skip sampled_main view={view_entity:?} tex={:?} reason=msaa_texture_not_copyable",
                sampled_main.id(),
            ),
        );
    }
    if stage == "after_upscaling" {
        state.remaining_captures = state.remaining_captures.saturating_sub(1);
    }
}

fn enqueue_cube_text_preview_graph_readback(
    state: &mut CubeTextPreviewGraphReadbackState,
    stage: &str,
    texture_label: &str,
    view_entity: Entity,
    texture: &bevy::render::render_resource::Texture,
    format: TextureFormat,
    render_context: &mut RenderContext<'_>,
) {
    let width = texture.width();
    let height = texture.height();
    if width == 0 || height == 0 {
        return;
    }
    if unsupported_readback_format(format) {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "cube_text_preview graph {stage} readback {texture_label} unsupported format={format:?}"
            ),
        );
        return;
    }

    let bytes_per_row = graph_readback_bytes_per_row(width);
    let buffer_size = bytes_per_row as u64 * height as u64;
    let buffer = render_context
        .render_device()
        .create_buffer(&wgpu::BufferDescriptor {
            label: Some("misa-rin cube text graph readback"),
            size: buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
    render_context.command_encoder().copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &buffer,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    state.pending.push(CubeTextPreviewGraphReadbackRequest {
        stage: stage.to_string(),
        texture_label: texture_label.to_string(),
        view_entity,
        width,
        height,
        format,
        points: target_sample_points(width, height),
        buffer,
        buffer_size,
    });
    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview graph {stage} readback queued texture={texture_label} view={view_entity:?} tex={:?} size={}x{} format={format:?} bytes_per_row={bytes_per_row}",
            texture.id(),
            width,
            height,
        ),
    );
}

fn drain_cube_text_preview_graph_readbacks(
    readbacks: Res<CubeTextPreviewGraphReadbacks>,
    render_device: Res<RenderDevice>,
) {
    if debug::level() < LogLevel::Info {
        return;
    }
    let pending = {
        let mut state = match readbacks.inner.lock() {
            Ok(state) => state,
            Err(_) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("cube_text_preview graph readback drain lock poisoned"),
                );
                return;
            }
        };
        if state.pending.is_empty() {
            return;
        }
        state.pending.drain(..).collect::<Vec<_>>()
    };

    render_device.poll(wgpu::Maintain::Wait);
    for request in pending {
        log_cube_text_preview_graph_readback(request, &render_device);
    }
}

fn log_cube_text_preview_graph_readback(
    request: CubeTextPreviewGraphReadbackRequest,
    render_device: &RenderDevice,
) {
    let slice = request.buffer.slice(0..request.buffer_size);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |res| {
        let _ = tx.send(res);
    });
    render_device.poll(wgpu::Maintain::Wait);

    match rx.recv() {
        Ok(Ok(())) => {}
        Ok(Err(err)) => {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "cube_text_preview graph {} readback texture={} view={:?} map_async failed: {err:?}",
                    request.stage, request.texture_label, request.view_entity,
                ),
            );
            return;
        }
        Err(err) => {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "cube_text_preview graph {} readback texture={} view={:?} map channel failed: {err}",
                    request.stage, request.texture_label, request.view_entity,
                ),
            );
            return;
        }
    }

    let bytes_per_row = graph_readback_bytes_per_row(request.width);
    let mapped = slice.get_mapped_range();
    let mut samples = Vec::new();
    let mut stats = TargetSampleStats::default();
    for point in &request.points {
        let offset = point.y as usize * bytes_per_row as usize
            + point.x as usize * READBACK_BYTES_PER_PIXEL as usize;
        match decode_texture_pixel(&mapped, offset, request.format) {
            Some(pixel) => {
                stats.push(pixel, &point.label, point.x, point.y, request.format);
                if point.log_label {
                    samples.push(format!(
                        "{}@{},{}=ARGB#{pixel:08X}/{}({},{},{},{})",
                        point.label,
                        point.x,
                        point.y,
                        format_pixel_channels(request.format),
                        (pixel >> 16) & 0xFF,
                        (pixel >> 8) & 0xFF,
                        pixel & 0xFF,
                        (pixel >> 24) & 0xFF,
                    ));
                }
            }
            None => samples.push(format!("{}@{},{}=ERR", point.label, point.x, point.y)),
        }
    }
    drop(mapped);
    request.buffer.unmap();

    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview graph {} readback texture={} view={:?} size={}x{} format={:?} stats={} samples=[{}]",
            request.stage,
            request.texture_label,
            request.view_entity,
            request.width,
            request.height,
            request.format,
            stats.summary(),
            samples.join("; "),
        ),
    );
}

fn log_cube_text_preview_graph_pipeline(
    stage: &str,
    entity: Entity,
    pipeline_id: bevy::render::render_resource::CachedRenderPipelineId,
    world: &World,
) {
    let Some(pipeline_cache) = world.get_resource::<PipelineCache>() else {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "cube_text_preview graph {stage} entity={entity:?} pipeline_id={} missing PipelineCache",
                pipeline_id.id(),
            ),
        );
        return;
    };
    let Some(material_instances) =
        world.get_resource::<RenderMaterialInstances<StandardMaterial>>()
    else {
        debug::log(
            LogLevel::Warn,
            format_args!(
                "cube_text_preview graph {stage} entity={entity:?} pipeline_id={} missing RenderMaterialInstances",
                pipeline_id.id(),
            ),
        );
        return;
    };
    let material_asset_id = material_instances.get(&entity).copied();
    let pipeline_state = pipeline_cache.get_render_pipeline_state(pipeline_id);
    let pipeline_ready = pipeline_cache.get_render_pipeline(pipeline_id).is_some();
    let descriptor = pipeline_cache.get_render_pipeline_descriptor(pipeline_id);
    let fragment_shader_id = descriptor
        .fragment
        .as_ref()
        .map(|fragment| fragment.shader.id());
    let target_formats = descriptor
        .fragment
        .as_ref()
        .map(|fragment| {
            fragment
                .targets
                .iter()
                .map(|target| {
                    target
                        .as_ref()
                        .map(|state| format!("{:?}", state.format))
                        .unwrap_or_else(|| "none".to_string())
                })
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_else(|| "none".to_string());
    let vertex_defs = descriptor
        .vertex
        .shader_defs
        .iter()
        .map(|def| format!("{def:?}"))
        .collect::<Vec<_>>()
        .join("|");
    let fragment_defs = descriptor
        .fragment
        .as_ref()
        .map(|fragment| {
            fragment
                .shader_defs
                .iter()
                .map(|def| format!("{def:?}"))
                .collect::<Vec<_>>()
                .join("|")
        })
        .unwrap_or_default();
    let vertex_layouts = descriptor
        .vertex
        .buffers
        .iter()
        .map(|layout| {
            let attributes = layout
                .attributes
                .iter()
                .map(|attribute| {
                    format!(
                        "loc{}:{:?}@{}",
                        attribute.shader_location, attribute.format, attribute.offset
                    )
                })
                .collect::<Vec<_>>()
                .join("+");
            format!(
                "stride{}:{:?}:{}",
                layout.array_stride, layout.step_mode, attributes
            )
        })
        .collect::<Vec<_>>()
        .join("|");
    let layout_ids = descriptor
        .layout
        .iter()
        .enumerate()
        .map(|(index, layout)| format!("{index}:{:?}", layout.id()))
        .collect::<Vec<_>>()
        .join(",");
    let depth = descriptor
        .depth_stencil
        .as_ref()
        .map(|depth| {
            format!(
                "{:?}:write={}:cmp={:?}",
                depth.format, depth.depth_write_enabled, depth.depth_compare
            )
        })
        .unwrap_or_else(|| "none".to_string());
    let shader_kind = match fragment_shader_id {
        Some(shader_id) if shader_id == PBR_SHADER_HANDLE.id() => "pbr",
        Some(shader_id) if shader_id == MESH_SHADER_HANDLE.id() => "mesh",
        Some(_) => "other",
        None => "none",
    };

    debug::log(
        LogLevel::Info,
        format_args!(
            "cube_text_preview graph {stage} pipeline entity={entity:?} pipeline_id={} ready={} state={} shader_kind={} fragment_shader={:?} targets=[{}] material_id={:?} layout_ids=[{}] vertex_entry={} fragment_entry={} depth={} msaa={} vertex_defs=[{}] fragment_defs=[{}] vertex_layouts=[{}]",
            pipeline_id.id(),
            pipeline_ready,
            pipeline_state_summary(pipeline_state),
            shader_kind,
            fragment_shader_id,
            target_formats,
            material_asset_id,
            layout_ids,
            descriptor.vertex.entry_point,
            descriptor
                .fragment
                .as_ref()
                .map(|fragment| fragment.entry_point.as_ref())
                .unwrap_or("none"),
            depth,
            descriptor.multisample.count,
            vertex_defs,
            fragment_defs,
            vertex_layouts,
        ),
    );
}

fn pipeline_state_summary(state: &CachedPipelineState) -> String {
    match state {
        CachedPipelineState::Queued => "Queued".to_string(),
        CachedPipelineState::Creating(_) => "Creating".to_string(),
        CachedPipelineState::Ok(Pipeline::RenderPipeline(_)) => "Ok(RenderPipeline)".to_string(),
        CachedPipelineState::Ok(Pipeline::ComputePipeline(_)) => "Ok(ComputePipeline)".to_string(),
        CachedPipelineState::Err(err) => format!("Err({err})"),
    }
}

struct TargetSamplePoint {
    label: String,
    x: u32,
    y: u32,
    log_label: bool,
}

#[derive(Default)]
struct TargetSampleStats {
    total: u32,
    non_transparent: u32,
    purple_like: u32,
    magenta_like: u32,
    transparent: u32,
    buckets: BTreeMap<u32, u32>,
    non_transparent_samples: Vec<String>,
}

impl TargetSampleStats {
    fn push(&mut self, argb: u32, label: &str, x: u32, y: u32, format: TextureFormat) {
        self.total += 1;
        let a = (argb >> 24) & 0xFF;
        let r = (argb >> 16) & 0xFF;
        let g = (argb >> 8) & 0xFF;
        let b = argb & 0xFF;
        if a <= 8 {
            self.transparent += 1;
        } else {
            self.non_transparent += 1;
            if self.non_transparent_samples.len() < TARGET_NON_TRANSPARENT_DETAIL_LIMIT {
                self.non_transparent_samples.push(format!(
                    "{label}@{x},{y}=ARGB#{argb:08X}/{}({r},{g},{b},{a})",
                    format_pixel_channels(format),
                ));
            }
        }
        if a > 8 && r > 160 && b > 160 && g < 96 {
            self.purple_like += 1;
        }
        if a > 8 && r > 220 && b > 180 && g < 64 {
            self.magenta_like += 1;
        }
        let bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        *self.buckets.entry(bucket).or_insert(0) += 1;
    }

    fn summary(&self) -> String {
        let dominant = self
            .buckets
            .iter()
            .max_by_key(|(_, count)| *count)
            .map(|(bucket, count)| {
                let r = (bucket >> 8) & 0xF;
                let g = (bucket >> 4) & 0xF;
                let b = bucket & 0xF;
                format!("#{r:X}{g:X}{b:X}x count={count}")
            })
            .unwrap_or_else(|| "none".to_string());
        let purple_ratio = percent(self.purple_like, self.total);
        let magenta_ratio = percent(self.magenta_like, self.total);
        let transparent_ratio = percent(self.transparent, self.total);
        let non_transparent_detail = if self.non_transparent_samples.is_empty() {
            "none".to_string()
        } else {
            self.non_transparent_samples.join("; ")
        };
        format!(
            "total={} non_transparent={} transparent={}({transparent_ratio:.1}%) purple_like={}({purple_ratio:.1}%) magenta_like={}({magenta_ratio:.1}%) dominant_bucket={dominant} non_transparent_samples=[{}]",
            self.total,
            self.non_transparent,
            self.transparent,
            self.purple_like,
            self.magenta_like,
            non_transparent_detail,
        )
    }
}

fn target_sample_points(width: u32, height: u32) -> Vec<TargetSamplePoint> {
    let mut points = Vec::new();
    for row in 0..TARGET_GRID_SAMPLE_ROWS {
        for col in 0..TARGET_GRID_SAMPLE_COLUMNS {
            let x = grid_coord(width, col, TARGET_GRID_SAMPLE_COLUMNS);
            let y = grid_coord(height, row, TARGET_GRID_SAMPLE_ROWS);
            let log_label = (row == TARGET_GRID_SAMPLE_ROWS / 2
                && col == TARGET_GRID_SAMPLE_COLUMNS / 2)
                || (row == 1 && col == 1)
                || (row == 1 && col + 2 == TARGET_GRID_SAMPLE_COLUMNS)
                || (row + 2 == TARGET_GRID_SAMPLE_ROWS && col == 1)
                || (row + 2 == TARGET_GRID_SAMPLE_ROWS && col + 2 == TARGET_GRID_SAMPLE_COLUMNS);
            points.push(TargetSamplePoint {
                label: format!("g{col}x{row}"),
                x,
                y,
                log_label,
            });
        }
    }
    points
}

fn grid_coord(size: u32, index: u32, count: u32) -> u32 {
    if size <= 1 || count <= 1 {
        return 0;
    }
    let max = size - 1;
    ((index as u64 * max as u64) / (count - 1) as u64) as u32
}

fn percent(count: u32, total: u32) -> f32 {
    if total == 0 {
        0.0
    } else {
        (count as f32 / total as f32) * 100.0
    }
}

fn graph_readback_bytes_per_row(width: u32) -> u32 {
    align_up_u32(
        width.saturating_mul(READBACK_BYTES_PER_PIXEL),
        READBACK_BYTES_PER_ROW_ALIGNMENT,
    )
}

fn unsupported_readback_format(format: TextureFormat) -> bool {
    !matches!(
        format.remove_srgb_suffix(),
        TextureFormat::Bgra8Unorm | TextureFormat::Rgba8Unorm
    )
}

fn decode_texture_pixel(mapped: &[u8], offset: usize, format: TextureFormat) -> Option<u32> {
    if mapped.len() < offset + READBACK_BYTES_PER_PIXEL as usize {
        return None;
    }
    let (r, g, b, a) = match format.remove_srgb_suffix() {
        TextureFormat::Bgra8Unorm => (
            mapped[offset + 2] as u32,
            mapped[offset + 1] as u32,
            mapped[offset] as u32,
            mapped[offset + 3] as u32,
        ),
        TextureFormat::Rgba8Unorm => (
            mapped[offset] as u32,
            mapped[offset + 1] as u32,
            mapped[offset + 2] as u32,
            mapped[offset + 3] as u32,
        ),
        _ => return None,
    };
    Some((a << 24) | (r << 16) | (g << 8) | b)
}

fn read_bgra_texture_pixel(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    x: u32,
    y: u32,
) -> Result<u32, String> {
    if width == 0 || height == 0 {
        return Err("empty texture".to_string());
    }
    if x >= width || y >= height {
        return Err(format!(
            "out of bounds x={x} y={y} width={width} height={height}"
        ));
    }

    let bytes_per_row_padded =
        align_up_u32(READBACK_BYTES_PER_PIXEL, READBACK_BYTES_PER_ROW_ALIGNMENT);
    if bytes_per_row_padded == 0 {
        return Err("bytes_per_row_padded == 0".to_string());
    }
    let readback_size = bytes_per_row_padded as u64;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("misa-rin cube text target pixel readback"),
        size: readback_size,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("misa-rin cube text target pixel readback encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d { x, y, z: 0 },
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &readback,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row_padded),
                rows_per_image: Some(1),
            },
        },
        wgpu::Extent3d {
            width: 1,
            height: 1,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(Some(encoder.finish()));

    let slice = readback.slice(0..readback_size);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |res| {
        let _ = tx.send(res);
    });
    device.poll(wgpu::Maintain::Wait);

    match rx.recv() {
        Ok(Ok(())) => {}
        Ok(Err(err)) => return Err(format!("map_async failed: {err:?}")),
        Err(err) => return Err(format!("map_async channel failed: {err}")),
    }

    let mapped = slice.get_mapped_range();
    let Some(pixel) = decode_texture_pixel(&mapped, 0, format) else {
        drop(mapped);
        readback.unmap();
        return if unsupported_readback_format(format) {
            Err(format!(
                "unsupported readback format {:?}",
                format.remove_srgb_suffix()
            ))
        } else {
            Err("mapped buffer too small".to_string())
        };
    };
    drop(mapped);
    readback.unmap();

    Ok(pixel)
}

fn format_pixel_channels(format: wgpu::TextureFormat) -> &'static str {
    match format.remove_srgb_suffix() {
        wgpu::TextureFormat::Bgra8Unorm => "BGRA",
        wgpu::TextureFormat::Rgba8Unorm => "RGBA",
        _ => "unknown",
    }
}

fn align_up_u32(value: u32, alignment: u32) -> u32 {
    if alignment == 0 {
        return value;
    }
    ((value + alignment - 1) / alignment) * alignment
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

struct UvStats {
    min: [f32; 2],
    max: [f32; 2],
    first: [f32; 2],
    mid: [f32; 2],
    last: [f32; 2],
}

impl UvStats {
    fn from_uvs(uvs: &[[f32; 2]]) -> Self {
        if uvs.is_empty() {
            return Self {
                min: [0.0, 0.0],
                max: [0.0, 0.0],
                first: [0.0, 0.0],
                mid: [0.0, 0.0],
                last: [0.0, 0.0],
            };
        }
        let mut min = [f32::INFINITY, f32::INFINITY];
        let mut max = [f32::NEG_INFINITY, f32::NEG_INFINITY];
        for uv in uvs {
            min[0] = min[0].min(uv[0]);
            min[1] = min[1].min(uv[1]);
            max[0] = max[0].max(uv[0]);
            max[1] = max[1].max(uv[1]);
        }
        Self {
            min,
            max,
            first: uvs[0],
            mid: uvs[uvs.len() / 2],
            last: uvs[uvs.len() - 1],
        }
    }
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

fn material_texture_samples(
    material: &CubeTextPreviewMaterial,
    scene: &CubeTextPreviewScene,
) -> String {
    match material.mode {
        CubeTextPreviewMaterialMode::Gradient => format!(
            "gradient top=0x{:08X} mid=0x{:08X} bottom=0x{:08X}",
            material.gradient_start,
            lerp_rgba(material.gradient_start, material.gradient_end, 0.5),
            material.gradient_end,
        ),
        CubeTextPreviewMaterialMode::Image => {
            if material.image_index < 0 {
                return format!("image missing index={}", material.image_index);
            }
            match scene.images.get(material.image_index as usize) {
                Some(image) => image_sample_summary(image),
                None => format!(
                    "image index={} out_of_range images={}",
                    material.image_index,
                    scene.images.len(),
                ),
            }
        }
        CubeTextPreviewMaterialMode::Color => format!("solid=0x{:08X}", material.color),
    }
}

fn image_sample_summary(image: &CubeTextPreviewImage) -> String {
    if image.width == 0 || image.height == 0 || image.rgba.len() < 4 {
        return format!(
            "image invalid size={}x{} len={}",
            image.width,
            image.height,
            image.rgba.len(),
        );
    }
    let points = [
        ("top_left", 0, 0),
        ("center", image.width / 2, image.height / 2),
        (
            "bottom_right",
            image.width.saturating_sub(1),
            image.height.saturating_sub(1),
        ),
    ];
    let mut samples = Vec::new();
    for (label, x, y) in points {
        samples.push(format!(
            "{label}@{x},{y}=0x{}",
            sample_rgba_bytes(image, x, y)
                .map(|pixel| format!("{pixel:08X}"))
                .unwrap_or_else(|| "ERR".to_string())
        ));
    }
    format!(
        "image size={}x{} len={} {}",
        image.width,
        image.height,
        image.rgba.len(),
        samples.join("; "),
    )
}

fn sample_rgba_bytes(image: &CubeTextPreviewImage, x: u32, y: u32) -> Option<u32> {
    if x >= image.width || y >= image.height {
        return None;
    }
    let offset = y.checked_mul(image.width)?.checked_add(x)?.checked_mul(4)? as usize;
    let r = *image.rgba.get(offset)? as u32;
    let g = *image.rgba.get(offset + 1)? as u32;
    let b = *image.rgba.get(offset + 2)? as u32;
    let a = *image.rgba.get(offset + 3)? as u32;
    Some((r << 24) | (g << 16) | (b << 8) | a)
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
        label: Some("misa-rin cube text checkerboard pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: "vs_main",
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: "fs_main",
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
