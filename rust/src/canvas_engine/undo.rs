use std::collections::HashMap;

use crate::gpu::layer_format::LAYER_TEXTURE_FORMAT;

const UNDO_TILE_SIZE: u32 = 256;
const UNDO_STACK_LIMIT: usize = 50;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct UndoTileKey {
    tx: u32,
    ty: u32,
    layer_index: u32,
}

#[derive(Clone, Copy, Debug)]
struct UndoTileRect {
    left: u32,
    top: u32,
    width: u32,
    height: u32,
}

struct UndoTileBefore {
    rect: UndoTileRect,
    before: wgpu::Texture,
}

struct UndoTilePatch {
    rect: UndoTileRect,
    before: wgpu::Texture,
    after: wgpu::Texture,
}

struct UndoRecord {
    layer_index: u32,
    tiles: Vec<UndoTilePatch>,
}

struct ActiveStrokeUndo {
    layer_index: u32,
    tiles: HashMap<UndoTileKey, UndoTileBefore>,
}

pub(crate) struct UndoManager {
    canvas_width: u32,
    canvas_height: u32,
    tile_size: u32,
    max_steps: usize,
    undo_stack: Vec<UndoRecord>,
    redo_stack: Vec<UndoRecord>,
    current: Option<ActiveStrokeUndo>,
}

impl UndoManager {
    pub(crate) fn new(canvas_width: u32, canvas_height: u32) -> Self {
        Self {
            canvas_width,
            canvas_height,
            tile_size: UNDO_TILE_SIZE,
            max_steps: UNDO_STACK_LIMIT,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            current: None,
        }
    }

    pub(crate) fn begin_stroke(&mut self, layer_index: u32) {
        self.current = Some(ActiveStrokeUndo {
            layer_index,
            tiles: HashMap::new(),
        });
    }

    pub(crate) fn begin_stroke_if_needed(&mut self, layer_index: u32) {
        if self.current.is_none() {
            self.begin_stroke(layer_index);
        }
    }

    pub(crate) fn cancel_stroke(&mut self) {
        self.current = None;
    }

    pub(crate) fn reset(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
        self.current = None;
    }

    pub(crate) fn reorder_layers(&mut self, from: u32, to: u32) {
        if from == to {
            return;
        }
        for record in self.undo_stack.iter_mut() {
            record.layer_index = remap_layer_index(record.layer_index, from, to);
        }
        for record in self.redo_stack.iter_mut() {
            record.layer_index = remap_layer_index(record.layer_index, from, to);
        }
        if let Some(active) = self.current.as_mut() {
            active.layer_index = remap_layer_index(active.layer_index, from, to);
            if !active.tiles.is_empty() {
                let mut next = HashMap::with_capacity(active.tiles.len());
                for (key, value) in active.tiles.drain() {
                    let remapped = remap_layer_index(key.layer_index, from, to);
                    next.insert(
                        UndoTileKey {
                            tx: key.tx,
                            ty: key.ty,
                            layer_index: remapped,
                        },
                        value,
                    );
                }
                active.tiles = next;
            }
        }
    }

    pub(crate) fn capture_before_for_dirty_rect(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        layer_texture: &wgpu::Texture,
        layer_index: u32,
        dirty: (i32, i32, i32, i32),
    ) {
        let canvas_width = self.canvas_width;
        let canvas_height = self.canvas_height;
        let tile_size = self.tile_size.max(1);

        let Some(active) = self.current.as_mut() else {
            return;
        };
        if active.layer_index != layer_index {
            return;
        }
        let (left_i, top_i, width_i, height_i) = dirty;
        if width_i <= 0 || height_i <= 0 {
            return;
        }

        let left = (left_i.max(0) as u32).min(canvas_width);
        let top = (top_i.max(0) as u32).min(canvas_height);
        let right = (left_i.saturating_add(width_i).max(0) as u32).min(canvas_width);
        let bottom = (top_i.saturating_add(height_i).max(0) as u32).min(canvas_height);
        if right <= left || bottom <= top {
            return;
        }

        let tx0 = left / tile_size;
        let ty0 = top / tile_size;
        let tx1 = right.saturating_sub(1) / tile_size;
        let ty1 = bottom.saturating_sub(1) / tile_size;

        let mut encoder: Option<wgpu::CommandEncoder> = None;

        for ty in ty0..=ty1 {
            for tx in tx0..=tx1 {
                let key = UndoTileKey {
                    tx,
                    ty,
                    layer_index,
                };
                if active.tiles.contains_key(&key) {
                    continue;
                }
                let tile_left = tx.saturating_mul(tile_size);
                let tile_top = ty.saturating_mul(tile_size);
                if tile_left >= canvas_width || tile_top >= canvas_height {
                    continue;
                }
                let tile_width = tile_size.min(canvas_width.saturating_sub(tile_left));
                let tile_height = tile_size.min(canvas_height.saturating_sub(tile_top));
                if tile_width == 0 || tile_height == 0 {
                    continue;
                }
                let rect = UndoTileRect {
                    left: tile_left,
                    top: tile_top,
                    width: tile_width,
                    height: tile_height,
                };

                let before_tex = device.create_texture(&wgpu::TextureDescriptor {
                    label: Some("misa-rin undo before (tile)"),
                    size: wgpu::Extent3d {
                        width: rect.width,
                        height: rect.height,
                        depth_or_array_layers: 1,
                    },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format: LAYER_TEXTURE_FORMAT,
                    usage: wgpu::TextureUsages::COPY_DST | wgpu::TextureUsages::COPY_SRC,
                    view_formats: &[],
                });

                let enc = encoder.get_or_insert_with(|| {
                    device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                        label: Some("misa-rin undo capture before encoder"),
                    })
                });
                enc.copy_texture_to_texture(
                    wgpu::TexelCopyTextureInfo {
                        texture: layer_texture,
                        mip_level: 0,
                        origin: wgpu::Origin3d {
                            x: rect.left,
                            y: rect.top,
                            z: layer_index,
                        },
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::TexelCopyTextureInfo {
                        texture: &before_tex,
                        mip_level: 0,
                        origin: wgpu::Origin3d::ZERO,
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::Extent3d {
                        width: rect.width,
                        height: rect.height,
                        depth_or_array_layers: 1,
                    },
                );

                active.tiles.insert(
                    key,
                    UndoTileBefore {
                        rect,
                        before: before_tex,
                    },
                );
            }
        }

        if let Some(enc) = encoder {
            queue.submit(Some(enc.finish()));
        }
    }

    pub(crate) fn end_stroke(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        layer_texture: &wgpu::Texture,
    ) {
        let Some(active) = self.current.take() else {
            return;
        };
        if active.tiles.is_empty() {
            return;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin undo capture after encoder"),
        });
        let mut patches: Vec<UndoTilePatch> = Vec::with_capacity(active.tiles.len());

        for (_, tile_before) in active.tiles {
            let rect = tile_before.rect;
            let after_tex = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("misa-rin undo after (tile)"),
                size: wgpu::Extent3d {
                    width: rect.width,
                    height: rect.height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: LAYER_TEXTURE_FORMAT,
                usage: wgpu::TextureUsages::COPY_DST | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });

            encoder.copy_texture_to_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: layer_texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d {
                        x: rect.left,
                        y: rect.top,
                        z: active.layer_index,
                    },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyTextureInfo {
                    texture: &after_tex,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::Extent3d {
                    width: rect.width,
                    height: rect.height,
                    depth_or_array_layers: 1,
                },
            );

            patches.push(UndoTilePatch {
                rect,
                before: tile_before.before,
                after: after_tex,
            });
        }

        queue.submit(Some(encoder.finish()));

        self.undo_stack.push(UndoRecord {
            layer_index: active.layer_index,
            tiles: patches,
        });
        if self.undo_stack.len() > self.max_steps {
            let overflow = self.undo_stack.len() - self.max_steps;
            self.undo_stack.drain(0..overflow);
        }
        self.redo_stack.clear();
    }

    pub(crate) fn restore_current_before(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        layer_texture: &wgpu::Texture,
    ) -> bool {
        let Some(active) = self.current.as_ref() else {
            return false;
        };
        if active.tiles.is_empty() {
            return false;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin undo restore current before encoder"),
        });
        for tile in active.tiles.values() {
            encoder.copy_texture_to_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &tile.before,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyTextureInfo {
                    texture: layer_texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d {
                        x: tile.rect.left,
                        y: tile.rect.top,
                        z: active.layer_index,
                    },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::Extent3d {
                    width: tile.rect.width,
                    height: tile.rect.height,
                    depth_or_array_layers: 1,
                },
            );
        }
        queue.submit(Some(encoder.finish()));
        true
    }

    pub(crate) fn undo(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        layer_texture: &wgpu::Texture,
        layer_count: usize,
    ) -> bool {
        self.cancel_stroke();
        let Some(record) = self.undo_stack.pop() else {
            return false;
        };
        if (record.layer_index as usize) >= layer_count {
            return false;
        };
        if record.tiles.is_empty() {
            return false;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin undo apply encoder"),
        });
        for tile in &record.tiles {
            encoder.copy_texture_to_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &tile.before,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyTextureInfo {
                    texture: layer_texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d {
                        x: tile.rect.left,
                        y: tile.rect.top,
                        z: record.layer_index,
                    },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::Extent3d {
                    width: tile.rect.width,
                    height: tile.rect.height,
                    depth_or_array_layers: 1,
                },
            );
        }
        queue.submit(Some(encoder.finish()));
        self.redo_stack.push(record);
        true
    }

    pub(crate) fn redo(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        layer_texture: &wgpu::Texture,
        layer_count: usize,
    ) -> bool {
        self.cancel_stroke();
        let Some(record) = self.redo_stack.pop() else {
            return false;
        };
        if (record.layer_index as usize) >= layer_count {
            return false;
        };
        if record.tiles.is_empty() {
            return false;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("misa-rin redo apply encoder"),
        });
        for tile in &record.tiles {
            encoder.copy_texture_to_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &tile.after,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyTextureInfo {
                    texture: layer_texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d {
                        x: tile.rect.left,
                        y: tile.rect.top,
                        z: record.layer_index,
                    },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::Extent3d {
                    width: tile.rect.width,
                    height: tile.rect.height,
                    depth_or_array_layers: 1,
                },
            );
        }
        queue.submit(Some(encoder.finish()));
        self.undo_stack.push(record);
        true
    }
}

fn remap_layer_index(index: u32, from: u32, to: u32) -> u32 {
    if from == to {
        return index;
    }
    if index == from {
        return to;
    }
    if from < to {
        if index > from && index <= to {
            return index.saturating_sub(1);
        }
    } else if from > to {
        if index >= to && index < from {
            return index.saturating_add(1);
        }
    }
    index
}
