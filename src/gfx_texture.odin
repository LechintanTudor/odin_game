package game

import "core:image"
import "core:slice"
import sdl "vendor:sdl3"

Texture_Handle :: distinct Handle

Texture_Manager :: struct {
	queued_uploads:         [dynamic]Texture_Upload,
	queued_upload_max_size: int,
	transfer_buffer:        ^sdl.GPUTransferBuffer,
	transfer_buffer_size:   int,
}

Texture_Upload :: struct {
	image:   ^image.Image,
	texture: ^sdl.GPUTexture,
}

texture_manager_create :: proc() -> Texture_Manager {
	return {queued_uploads = make([dynamic]Texture_Upload)}
}

texture_manager_destroy :: proc(manager: Texture_Manager, device: ^sdl.GPUDevice) {
	for upload in manager.queued_uploads {
		image.destroy(upload.image)
		sdl.ReleaseGPUTexture(device, upload.texture)
	}

	delete(manager.queued_uploads)

	if manager.transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(device, manager.transfer_buffer)
	}
}

texture_manager_upload :: proc(
	manager: ^Texture_Manager,
	device: ^sdl.GPUDevice,
	copy_pass: ^sdl.GPUCopyPass,
) {
	// Resize the transfer buffer if needed.
	if manager.transfer_buffer_size < manager.queued_upload_max_size {
		if manager.transfer_buffer != nil {
			sdl.ReleaseGPUTransferBuffer(device, manager.transfer_buffer)
		}

		transfer_buffer := sdl.CreateGPUTransferBuffer(
			device,
			{usage = .UPLOAD, size = u32(manager.queued_upload_max_size)},
		)

		if transfer_buffer == nil {
			panic("Failed to allocate transfer buffer")
		}

		manager.transfer_buffer = transfer_buffer
		manager.transfer_buffer_size = manager.queued_upload_max_size
	}

	// Upload data to the textures.
	for upload in manager.queued_uploads {
		buf_ptr := sdl.MapGPUTransferBuffer(device, manager.transfer_buffer, true)
		buf := slice.from_ptr(([^]u8)(buf_ptr), manager.transfer_buffer_size)
		copy(buf, upload.image.pixels.buf[:])
		sdl.UnmapGPUTransferBuffer(device, manager.transfer_buffer)

		sdl.UploadToGPUTexture(
			copy_pass,
			{
				transfer_buffer = manager.transfer_buffer,
				pixels_per_row = u32(upload.image.width),
				rows_per_layer = u32(upload.image.height),
			},
			{
				texture = upload.texture,
				w = u32(upload.image.width),
				h = u32(upload.image.height),
				d = 1,
			},
			false,
		)

		image.destroy(upload.image)
	}

	// Clean up.
	clear(&manager.queued_uploads)
	manager.queued_upload_max_size = 0
}

gfx_texture_create :: proc(app: ^App, image: ^image.Image) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(
		app.device,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM_SRGB,
			usage = {.SAMPLER},
			width = u32(image.width),
			height = u32(image.height),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)

	if texture == nil {
		return nil
	}

	manager := &app.texture_manager
	append(&manager.queued_uploads, Texture_Upload{image, texture})
	manager.queued_upload_max_size = max(manager.queued_upload_max_size, len(image.pixels.buf))
	return texture
}

