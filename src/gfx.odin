package game

import "core:math/linalg"
import sdl "vendor:sdl3"

Vec2 :: distinct [2]f32
Color :: distinct [4]f32

COLOR_WHITE: Color = {1, 1, 1, 1}
COLOR_RED: Color = {1, 0, 0, 1}
COLOR_GREEN: Color = {0, 1, 0, 1}
COLOR_BLUE: Color = {0, 0, 1, 1}
COLOR_YELLOW: Color = {1, 1, 0, 1}

Gfx_Command :: union {
	Gfx_Draw_Shapes,
}

Gfx_Draw_Shapes :: struct {
	start: u32,
	count: u32,
}

gfx_start :: proc(app: ^App) {
	clear(&app.gfx_commands)
	shape_renderer_clear(&app.shape_renderer)
}

gfx_end :: proc(
	app: ^App,
	command_buffer: ^sdl.GPUCommandBuffer,
	texture: ^sdl.GPUTexture,
	texture_w, texture_h: u32,
) {
	copy_pass := sdl.BeginGPUCopyPass(command_buffer)
	shape_renderer_upload(&app.shape_renderer, app.device, copy_pass)
	sdl.EndGPUCopyPass(copy_pass)

	color_target_info := sdl.GPUColorTargetInfo {
		clear_color = auto_cast COLOR_WHITE,
		load_op     = .CLEAR,
		store_op    = .STORE,
		texture     = texture,
	}

	pass := sdl.BeginGPURenderPass(command_buffer, &color_target_info, 1, nil)

	ortho_matrix := linalg.matrix_ortho3d_f32(0, f32(texture_w), f32(texture_h), 0, 0, 1)
	sdl.PushGPUVertexUniformData(command_buffer, 1, &ortho_matrix, size_of(ortho_matrix))

	last_draw_command: typeid

	for &command in app.gfx_commands {
		switch &command in command {
		case Gfx_Draw_Shapes:
			if set_if_different(&last_draw_command, typeid_of(Gfx_Draw_Shapes)) {
				shape_renderer_bind(app.shape_renderer, pass)
			}

			shape_renderer_draw(app.shape_renderer, pass, command.start, command.count)
		}
	}

	sdl.EndGPURenderPass(pass)
}


@(private)
set_if_different :: proc(dest: ^$T, src: T) -> bool {
	if dest^ == src {
		return false
	}

	dest^ = src
	return true
}

