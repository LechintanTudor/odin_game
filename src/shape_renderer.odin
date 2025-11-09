package game

import "core:log"
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"

VERT_SPV :: #load("../build/geometry.vert.spv")
FRAG_SPV :: #load("../build/geometry.frag.spv")

Border_Type :: enum {
	Outer,
	Centered,
	Inner,
}

Shape_Renderer :: struct {
	pipeline:        ^sdl.GPUGraphicsPipeline,
	vert_shader:     ^sdl.GPUShader,
	frag_shader:     ^sdl.GPUShader,
	transfer_buffer: ^sdl.GPUTransferBuffer,
	geometry_buffer: ^sdl.GPUBuffer,
	buffer_size:     u32,
	indexes_offset:  u32,
	vertexes:        [dynamic]Shape_Vertex,
	indexes:         [dynamic]u32,
}

Shape_Vertex :: struct #min_field_align(16) {
	position: Vec2,
	color:    Color,
}

shape_renderer_create :: proc(
	device: ^sdl.GPUDevice,
	texture_format: sdl.GPUTextureFormat,
) -> Shape_Renderer {
	vert_shader := sdl.CreateGPUShader(
		device,
		{
			code = raw_data(VERT_SPV),
			code_size = len(VERT_SPV),
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
			code = raw_data(FRAG_SPV),
			code_size = len(FRAG_SPV),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .FRAGMENT,
		},
	)

	assert(frag_shader != nil)

	vertex_buffer_descriptions := [?]sdl.GPUVertexBufferDescription {
		{slot = 0, input_rate = .VERTEX, instance_step_rate = 0, pitch = size_of(Shape_Vertex)},
	}

	vertex_attributes := [?]sdl.GPUVertexAttribute {
		{
			buffer_slot = 0,
			location = 0,
			format = .FLOAT2,
			offset = u32(offset_of(Shape_Vertex, position)),
		},
		{
			buffer_slot = 0,
			location = 1,
			format = .FLOAT4,
			offset = u32(offset_of(Shape_Vertex, color)),
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

	if pipeline == nil {
		log.errorf("Failed to build pipeline: %v", sdl.GetError())
	}

	assert(pipeline != nil)

	return {
		pipeline = pipeline,
		vert_shader = vert_shader,
		frag_shader = frag_shader,
		vertexes = make([dynamic]Shape_Vertex),
		indexes = make([dynamic]u32),
	}
}

shape_renderer_destroy :: proc(renderer: Shape_Renderer, device: ^sdl.GPUDevice) {
	sdl.ReleaseGPUGraphicsPipeline(device, renderer.pipeline)
	sdl.ReleaseGPUShader(device, renderer.vert_shader)
	sdl.ReleaseGPUShader(device, renderer.frag_shader)

	if renderer.buffer_size != 0 {
		sdl.ReleaseGPUTransferBuffer(device, renderer.transfer_buffer)
		sdl.ReleaseGPUBuffer(device, renderer.geometry_buffer)
	}

	delete(renderer.vertexes)
	delete(renderer.indexes)
}

shape_renderer_clear :: proc(renderer: ^Shape_Renderer) {
	clear(&renderer.vertexes)
	clear(&renderer.indexes)
}

shape_renderer_upload :: proc(
	renderer: ^Shape_Renderer,
	device: ^sdl.GPUDevice,
	copy_pass: ^sdl.GPUCopyPass,
) {
	vertexes_size := len(renderer.vertexes) * size_of(Shape_Vertex)
	indexes_offset := mem.align_forward_int(vertexes_size, align_of(u32))
	indexes_size := len(renderer.indexes) * size_of(u32)
	buffer_size := u32(indexes_offset + indexes_size)

	if buffer_size > renderer.buffer_size {
		sdl.ReleaseGPUTransferBuffer(device, renderer.transfer_buffer)
		sdl.ReleaseGPUBuffer(device, renderer.geometry_buffer)

		buffers_created_successfully := true

		transfer_buffer := sdl.CreateGPUTransferBuffer(
			device,
			{usage = .UPLOAD, size = buffer_size},
		)

		if transfer_buffer == nil {
			log.errorf("Failed to create transfer buffer: %v", sdl.GetError())
			buffers_created_successfully = false
		}

		geometry_buffer := sdl.CreateGPUBuffer(
			device,
			{usage = {.INDEX, .VERTEX}, size = buffer_size},
		)

		if geometry_buffer == nil {
			log.errorf("Failed to create buffer: %v", sdl.GetError())
			buffers_created_successfully = false
		}

		if !buffers_created_successfully {
			if transfer_buffer != nil {
				sdl.ReleaseGPUTransferBuffer(device, transfer_buffer)
			}

			if geometry_buffer != nil {
				sdl.ReleaseGPUBuffer(device, geometry_buffer)
			}

			renderer.transfer_buffer = nil
			renderer.geometry_buffer = nil
			renderer.buffer_size = 0
			renderer.indexes_offset = 0
			return
		}

		renderer.transfer_buffer = transfer_buffer
		renderer.geometry_buffer = geometry_buffer
		renderer.buffer_size = buffer_size
		renderer.indexes_offset = u32(indexes_offset)
	}

	{
		buffer := ([^]u8)(sdl.MapGPUTransferBuffer(device, renderer.transfer_buffer, true))

		if buffer == nil {
			log.errorf("Failed to map transfer buffer: %v", sdl.GetError())
			return
		}

		dst_vertexes := slice.from_ptr(([^]Shape_Vertex)(buffer), len(renderer.vertexes))
		copy(dst_vertexes, renderer.vertexes[:])

		dst_indexes := slice.from_ptr(
			([^]u32)(mem.ptr_offset(buffer, renderer.indexes_offset)),
			len(renderer.indexes),
		)
		copy(dst_indexes, renderer.indexes[:])

		sdl.UnmapGPUTransferBuffer(device, renderer.transfer_buffer)
	}

	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = renderer.transfer_buffer, offset = 0},
		{buffer = renderer.geometry_buffer, size = buffer_size, offset = 0},
		true,
	)
}

shape_renderer_bind :: proc(renderer: Shape_Renderer, pass: ^sdl.GPURenderPass) {
	sdl.BindGPUGraphicsPipeline(pass, renderer.pipeline)

	{
		vert_binding := sdl.GPUBufferBinding {
			buffer = renderer.geometry_buffer,
			offset = 0,
		}

		sdl.BindGPUVertexBuffers(pass, 0, &vert_binding, 1)

	}

	{
		index_binding := sdl.GPUBufferBinding {
			buffer = renderer.geometry_buffer,
			offset = renderer.indexes_offset,
		}

		sdl.BindGPUIndexBuffer(pass, index_binding, ._32BIT)
	}
}

shape_renderer_draw :: proc(
	renderer: Shape_Renderer,
	pass: ^sdl.GPURenderPass,
	start: u32,
	count: u32,
) {
	sdl.DrawGPUIndexedPrimitives(pass, count, 1, start, 0, 0)
}

gfx_draw_aabb :: proc(app: ^App, x, y, w, h: f32, color := COLOR_WHITE) {
	renderer := &app.shape_renderer
	draw_shapes := gfx_command_get_draw_shapes(app)
	start_index := u32(len(renderer.vertexes))

	append(
		&renderer.vertexes,
		Shape_Vertex{{x, y}, color},
		Shape_Vertex{{x, y + h}, color},
		Shape_Vertex{{x + w, y + h}, color},
		Shape_Vertex{{x + w, y}, color},
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

	draw_shapes.count += u32(index_count)
}

gfx_draw_aabb_border :: proc(
	app: ^App,
	x, y, w, h: f32,
	thickness: f32,
	type := Border_Type.Inner,
	color := COLOR_WHITE,
) {
	renderer := &app.shape_renderer
	draw_shapes := gfx_command_get_draw_shapes(app)
	start_index := u32(len(renderer.vertexes))

	in_off, out_off: f32

	switch type {
	case Border_Type.Outer:
		in_off = thickness
		out_off = 0

	case Border_Type.Centered:
		in_off = thickness * 0.5
		out_off = thickness * -0.5

	case Border_Type.Inner:
		in_off = 0
		out_off = -thickness
	}

	append(
		&renderer.vertexes,

		// Inner
		Shape_Vertex{{x - in_off, y - in_off}, color},
		Shape_Vertex{{x - in_off, y + h + in_off}, color},
		Shape_Vertex{{x + w + in_off, y + h + in_off}, color},
		Shape_Vertex{{x + w + in_off, y - in_off}, color},

		// Outer
		Shape_Vertex{{x - out_off, y - out_off}, color},
		Shape_Vertex{{x - out_off, y + h + out_off}, color},
		Shape_Vertex{{x + w + out_off, y + h + out_off}, color},
		Shape_Vertex{{x + w + out_off, y - out_off}, color},
	)

	index_count := append(
		&renderer.indexes,
		start_index + 0,
		start_index + 4,
		start_index + 5,
		start_index + 0,
		start_index + 5,
		start_index + 1,
		start_index + 1,
		start_index + 5,
		start_index + 6,
		start_index + 1,
		start_index + 6,
		start_index + 2,
		start_index + 2,
		start_index + 6,
		start_index + 7,
		start_index + 3,
		start_index + 2,
		start_index + 7,
		start_index + 4,
		start_index + 3,
		start_index + 7,
		start_index + 4,
		start_index + 0,
		start_index + 3,
	)

	draw_shapes.count += u32(index_count)
}

@(private)
gfx_command_get_draw_shapes :: proc(app: ^App) -> ^Gfx_Draw_Shapes {
	command := slice.last_ptr(app.gfx_commands[:])

	if command != nil {
		draw_shapes, ok := &command.(Gfx_Draw_Shapes)

		if ok {
			return draw_shapes
		}
	}

	append(&app.gfx_commands, Gfx_Draw_Shapes{})
	return &slice.last_ptr(app.gfx_commands[:]).(Gfx_Draw_Shapes)
}

