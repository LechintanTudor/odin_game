package game

import "core:slice"
import sdl "vendor:sdl3"

@(private)
SPRITE_VERT_SPV :: #load("../build/sprite.vert.spv")

@(private)
SPRITE_FRAG_SPV :: #load("../build/sprite.frag.spv")

Sprite_Renderer :: struct {
	pipeline:       ^sdl.GPUGraphicsPipeline,
	vert_shader:    ^sdl.GPUShader,
	frag_shader:    ^sdl.GPUShader,
	sampler:        ^sdl.GPUSampler,
	buffer:         Gfx_Buffer,
	indexes_offset: u32,
	vertexes:       [dynamic]Sprite_Vertex,
	indexes:        [dynamic]u32,
}

Gfx_Draw_Sprites :: struct {
	texture: ^sdl.GPUTexture,
	start:   u32,
	count:   u32,
}

Sprite_Vertex :: struct #align (16) {
	position: Vec2,
	uv:       Vec2,
	color:    Color,
}

sprite_renderer_create :: proc(
	device: ^sdl.GPUDevice,
	texture_format: sdl.GPUTextureFormat,
) -> Sprite_Renderer {
	vert_shader := sdl.CreateGPUShader(
		device,
		{
			code = raw_data(SPRITE_VERT_SPV),
			code_size = len(SPRITE_VERT_SPV),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .VERTEX,
			num_uniform_buffers = 1,
		},
	)

	assert(vert_shader != nil)

	frag_shader := sdl.CreateGPUShader(
		device,
		{
			code = raw_data(SPRITE_FRAG_SPV),
			code_size = len(SPRITE_FRAG_SPV),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .FRAGMENT,
			num_samplers = 1,
		},
	)

	assert(frag_shader != nil)

	vertex_buffer_descriptions := [?]sdl.GPUVertexBufferDescription {
		{slot = 0, input_rate = .VERTEX, instance_step_rate = 0, pitch = size_of(Sprite_Vertex)},
	}

	vertex_attributes := [?]sdl.GPUVertexAttribute {
		{
			buffer_slot = 0,
			location = 0,
			format = .FLOAT2,
			offset = u32(offset_of(Sprite_Vertex, position)),
		},
		{
			buffer_slot = 0,
			location = 1,
			format = .FLOAT2,
			offset = u32(offset_of(Sprite_Vertex, uv)),
		},
		{
			buffer_slot = 0,
			location = 2,
			format = .FLOAT4,
			offset = u32(offset_of(Sprite_Vertex, color)),
		},
	}

	color_target_descriptions := [?]sdl.GPUColorTargetDescription {
		{
			blend_state = {
				enable_blend = true,
				color_blend_op = .ADD,
				alpha_blend_op = .ADD,
				src_color_blendfactor = .SRC_ALPHA,
				dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
				src_alpha_blendfactor = .SRC_ALPHA,
				dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			},
			format = texture_format,
		},
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		device,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			vertex_input_state = {
				vertex_buffer_descriptions = raw_data(vertex_buffer_descriptions[:]),
				num_vertex_buffers = len(vertex_buffer_descriptions),
				vertex_attributes = raw_data(vertex_attributes[:]),
				num_vertex_attributes = len(vertex_attributes),
			},
			target_info = {
				color_target_descriptions = raw_data(color_target_descriptions[:]),
				num_color_targets = len(color_target_descriptions),
			},
		},
	)

	assert(pipeline != nil)

	sampler := sdl.CreateGPUSampler(
		device,
		{
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)

	assert(sampler != nil)

	return {
		pipeline = pipeline,
		vert_shader = vert_shader,
		frag_shader = frag_shader,
		sampler = sampler,
		vertexes = make([dynamic]Sprite_Vertex),
		indexes = make([dynamic]u32),
	}
}

sprite_renderer_destroy :: proc(renderer: Sprite_Renderer, device: ^sdl.GPUDevice) {
	sdl.ReleaseGPUGraphicsPipeline(device, renderer.pipeline)
	sdl.ReleaseGPUShader(device, renderer.vert_shader)
	sdl.ReleaseGPUShader(device, renderer.frag_shader)

	gfx_buffer_destroy(renderer.buffer, device)

	delete(renderer.vertexes)
	delete(renderer.indexes)
}

sprite_renderer_clear :: proc(renderer: ^Sprite_Renderer) {
	clear(&renderer.vertexes)
	clear(&renderer.indexes)
}

sprite_renderer_upload :: proc(
	renderer: ^Sprite_Renderer,
	device: ^sdl.GPUDevice,
	copy_pass: ^sdl.GPUCopyPass,
) {
	indexes_offset, _ := gfx_buffer_upload(
		&renderer.buffer,
		device,
		copy_pass,
		renderer.vertexes[:],
		renderer.indexes[:],
	)

	renderer.indexes_offset = indexes_offset
}

sprite_renderer_bind :: proc(renderer: Sprite_Renderer, pass: ^sdl.GPURenderPass) {
	sdl.BindGPUGraphicsPipeline(pass, renderer.pipeline)

	{
		vert_binding := sdl.GPUBufferBinding {
			buffer = renderer.buffer.buffer,
			offset = 0,
		}

		sdl.BindGPUVertexBuffers(pass, 0, &vert_binding, 1)

	}

	{
		index_binding := sdl.GPUBufferBinding {
			buffer = renderer.buffer.buffer,
			offset = renderer.indexes_offset,
		}

		sdl.BindGPUIndexBuffer(pass, index_binding, ._32BIT)
	}
}

sprite_renderer_draw :: proc(
	renderer: Sprite_Renderer,
	pass: ^sdl.GPURenderPass,
	command: Gfx_Draw_Sprites,
) {
	sampler_binding := [?]sdl.GPUTextureSamplerBinding {
		{texture = command.texture, sampler = renderer.sampler},
	}

	sdl.BindGPUFragmentSamplers(pass, 0, raw_data(sampler_binding[:]), u32(len(sampler_binding)))
	sdl.DrawGPUIndexedPrimitives(pass, command.count, 1, command.start, 0, 0)
}

gfx_draw_texture :: proc(
	app: ^App,
	x, y, w, h: f32,
	texture: ^sdl.GPUTexture,
	color := COLOR_WHITE,
) {
	renderer := &app.sprite_renderer
	draw_sprites := gfx_command_get_draw_sprites(app, texture)
	start_index := u32(len(renderer.vertexes))

	append(
		&renderer.vertexes,
		Sprite_Vertex{{x, y}, {0, 0}, color},
		Sprite_Vertex{{x, y + h}, {0, 1}, color},
		Sprite_Vertex{{x + w, y + h}, {1, 1}, color},
		Sprite_Vertex{{x + w, y}, {1, 0}, color},
	)

	index_count := append(
		&renderer.indexes,
		start_index + 0,
		start_index + 1,
		start_index + 3,
		start_index + 3,
		start_index + 1,
		start_index + 2,
	)

	draw_sprites.count += u32(index_count)
}

@(private)
gfx_command_get_draw_sprites :: proc(app: ^App, texture: ^sdl.GPUTexture) -> ^Gfx_Draw_Sprites {
	command := slice.last_ptr(app.gfx_commands[:])

	if command != nil {
		draw_shapes, ok := &command.(Gfx_Draw_Sprites)

		if ok && draw_shapes.texture == texture {
			return draw_shapes
		}
	}

	append(&app.gfx_commands, Gfx_Draw_Sprites{texture = texture})
	return &slice.last_ptr(app.gfx_commands[:]).(Gfx_Draw_Sprites)
}

