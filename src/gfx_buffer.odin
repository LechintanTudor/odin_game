package game

import "core:log"
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"

Gfx_Buffer :: struct {
	transfer_buffer: ^sdl.GPUTransferBuffer,
	buffer:          ^sdl.GPUBuffer,
	buffer_size:     u32,
}

gfx_buffer_destroy :: proc(b: Gfx_Buffer, device: ^sdl.GPUDevice) {
	if b.buffer_size != 0 {
		sdl.ReleaseGPUTransferBuffer(device, b.transfer_buffer)
		sdl.ReleaseGPUBuffer(device, b.buffer)
	}
}

@(require_results)
gfx_buffer_upload :: proc(
	b: ^Gfx_Buffer,
	device: ^sdl.GPUDevice,
	copy_pass: ^sdl.GPUCopyPass,
	vertexes: []$V,
	indexes: []u32,
) -> (
	offset: u32,
	ok: bool,
) #optional_ok {
	vertexes_size := len(vertexes) * size_of(V)
	indexes_offset := mem.align_forward_int(vertexes_size, align_of(u32))
	indexes_size := len(indexes) * size_of(u32)
	buffer_size := u32(indexes_offset + indexes_size)

	// Resize the buffers if needed.
	if b.buffer_size < buffer_size {
		buffer_creation_ok := true

		if b.buffer_size != 0 {
			sdl.ReleaseGPUTransferBuffer(device, b.transfer_buffer)
			sdl.ReleaseGPUBuffer(device, b.buffer)
		}

		transfer_buffer := sdl.CreateGPUTransferBuffer(
			device,
			{usage = .UPLOAD, size = buffer_size},
		)

		if transfer_buffer == nil {
			log.errorf("Failed to create transfer buffer: %v", sdl.GetError())
			buffer_creation_ok = false
		}

		buffer := sdl.CreateGPUBuffer(device, {usage = {.VERTEX, .INDEX}, size = buffer_size})

		if buffer == nil {
			log.errorf("Failed to create buffer: %v", sdl.GetError())
			buffer_creation_ok = false
		}

		if !buffer_creation_ok {
			if transfer_buffer != nil {
				sdl.ReleaseGPUTransferBuffer(device, transfer_buffer)
			}

			if buffer != nil {
				sdl.ReleaseGPUBuffer(device, buffer)
			}

			b.transfer_buffer = nil
			b.buffer = nil
			b.buffer_size = 0
			return
		}

		b.transfer_buffer = transfer_buffer
		b.buffer = buffer
		b.buffer_size = buffer_size
	}

	{
		ptr := sdl.MapGPUTransferBuffer(device, b.transfer_buffer, true)

		if ptr == nil {
			log.errorf("Failed to map transfer buffer: %v", sdl.GetError())
			return
		}

		dst_vertexes := slice.from_ptr(([^]V)(ptr), len(vertexes))
		copy(dst_vertexes[:], vertexes[:])

		dst_indexes := slice.from_ptr(([^]u32)(rawptr_offset(ptr, indexes_offset)), len(indexes))
		copy(dst_indexes[:], indexes[:])

		sdl.UnmapGPUTransferBuffer(device, b.transfer_buffer)
	}

	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = b.transfer_buffer, offset = 0},
		{buffer = b.buffer, size = buffer_size, offset = 0},
		true,
	)

	offset = u32(indexes_offset)
	ok = true
	return
}

@(private)
rawptr_offset :: proc(ptr: rawptr, offset: int) -> rawptr {
	return rawptr(mem.ptr_offset(([^]u8)(ptr), offset))
}

