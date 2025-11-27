package game

import "base:runtime"
import "core:image"
import _ "core:image/png"
import "core:log"
import "core:mem"
import sdl "vendor:sdl3"

App :: struct {
	ctx:             runtime.Context,
	window:          ^sdl.Window,
	device:          ^sdl.GPUDevice,
	gfx_commands:    [dynamic]Gfx_Command,
	texture_manager: Texture_Manager,
	texture:         ^sdl.GPUTexture,
	shape_renderer:  Shape_Renderer,
	sprite_renderer: Sprite_Renderer,
}

app_init :: proc "c" (app_ptr: ^rawptr, argc: i32, argv: [^]cstring) -> sdl.AppResult {
	context = runtime.default_context()
	context.logger = log.create_console_logger()

	log.info("App started...")

	if !sdl.SetAppMetadata("SDL + Box2D", "25.10", "com.lechi.sdl+box2d") {
		log.errorf("Failed to set app metadata: %v", sdl.GetError())
		return sdl.AppResult.FAILURE
	}

	if !sdl.Init({.VIDEO}) {
		log.errorf("Failed to init SDL: %v", sdl.GetError())
		return sdl.AppResult.FAILURE
	}

	window := sdl.CreateWindow("SDL + Box2D", 640, 480, {.RESIZABLE})
	if window == nil {
		log.errorf("Failed to create window: %v", sdl.GetError())
		return sdl.AppResult.FAILURE
	}

	device := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if device == nil {
		log.errorf("Failed to create GPU device: %v", sdl.GetError())
		return sdl.AppResult.FAILURE
	}

	if !sdl.ClaimWindowForGPUDevice(device, window) {
		log.errorf("Failed to claim window for device: %v", sdl.GetError())
		return sdl.AppResult.FAILURE
	}

	texture_format := sdl.GetGPUSwapchainTextureFormat(device, window)

	app, _ := mem.new(App)

	app^ = {
		ctx             = context,
		window          = window,
		device          = device,
		gfx_commands    = make([dynamic]Gfx_Command),
		texture_manager = texture_manager_create(),
		shape_renderer  = shape_renderer_create(device, texture_format),
		sprite_renderer = sprite_renderer_create(device, texture_format),
	}

	image, err := image.load_from_file("images/lenna.png", {.alpha_add_if_missing})
	app.texture = gfx_texture_create(app, image)

	(^^App)(app_ptr)^ = app

	return sdl.AppResult.CONTINUE
}

app_iterate :: proc "c" (app: rawptr) -> sdl.AppResult {
	app := (^App)(app)
	context = app.ctx

	command_buffer := sdl.AcquireGPUCommandBuffer(app.device)

	texture: ^sdl.GPUTexture
	texture_w: u32
	texture_h: u32

	if !sdl.WaitAndAcquireGPUSwapchainTexture(
		command_buffer,
		app.window,
		&texture,
		&texture_w,
		&texture_h,
	) {
		log.errorf("Failed to acquire swapchain texture: %v", sdl.GetError())
	}

	if texture == nil {
		if !sdl.SubmitGPUCommandBuffer(command_buffer) {
			log.errorf("Failed to submit command buffer: %v", sdl.GetError())
		}

		return sdl.AppResult.CONTINUE
	}

	gfx_start(app)
	gfx_draw_aabb(app, 100, 100, 100, 100, {1, 0, 0, 0.2})
	gfx_draw_aabb_border(app, 100, 100, 100, 100, 1, .Outer, {1, 0, 0, 1})
	gfx_draw_texture(app, 0, 0, 100, 100, app.texture)
	gfx_end(app, command_buffer, texture, texture_w, texture_h)

	if !sdl.SubmitGPUCommandBuffer(command_buffer) {
		log.errorf("Failed to submit command buffer: %v", sdl.GetError())
	}

	return sdl.AppResult.CONTINUE
}

app_event :: proc "c" (app: rawptr, event: ^sdl.Event) -> sdl.AppResult {
	app := (^App)(app)
	context = app.ctx

	if event.type == .QUIT {
		return sdl.AppResult.SUCCESS
	}

	return sdl.AppResult.CONTINUE
}

app_quit :: proc "c" (app: rawptr, result: sdl.AppResult) {
	app := (^App)(app)
	context = app.ctx

	log.info("App shutting down...")

	if app == nil {
		return
	}

	texture_manager_destroy(app.texture_manager, app.device)
	sdl.ReleaseGPUTexture(app.device, app.texture)

	shape_renderer_destroy(app.shape_renderer, app.device)
	sprite_renderer_destroy(app.sprite_renderer, app.device)

	sdl.DestroyGPUDevice(app.device)
	sdl.DestroyWindow(app.window)
	mem.free(app)
}

main :: proc() {
	argc := i32(len(runtime.args__))
	argv := raw_data(runtime.args__)
	sdl.EnterAppMainCallbacks(argc, argv, app_init, app_iterate, app_event, app_quit)
}

