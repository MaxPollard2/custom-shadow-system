@tool
extends Node
class_name ShadowTier

var color_texture: Texture2DRD
#var depth_tex_rid: RID

var resolution = Vector2(2048, 2048)

var projection : Projection
var view_proj : Projection
var cached_view_proj : PackedByteArray

var local_aabb := AABB()

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID

var shadow : Shadow
var rd : RenderingDevice

var fb_rid: RID

var global_uniform_texture_name : String = ""
var global_uniform_mat4_name : String = ""
var global_uniform_size_name : String = ""

var aabb : AABB

@export var orthographic := false:
	set(value):
		orthographic = value
		_update_projection()

@export var size := 15.0:
	set(value):
		size = value
		_update_projection()
		
@export var fov_deg := 75.0:
	set(value):
		fov_deg = value
		_update_projection()
		
@export var near := 0.05:
	set(value):
		near = value
		_update_projection()
		
@export var far := 4000.0:
	set(value):
		far = value
		_update_projection()
		
func _init(_shadow, _rd):
	shadow = _shadow
	orthographic = shadow.orthographic
	rd = _rd
	
	_rebuild_light_local_aabb()
		
func _update_projection():
	if orthographic:
		projection = make_orthographic_projection()
	else:
		projection = make_perspective_projection()
	
	var view = shadow.view
	view_proj = projection * view
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	_rebuild_light_local_aabb()
		
func _rebuild_light_local_aabb() -> void:
	var half := size * 0.5
	#var length = far

	aabb = AABB(Vector3(-half, -half, near), Vector3(size, size, far))


####################################### This one was "working"	
func _rebuild_light_local_aabb2() -> AABB:
	var forward = -shadow.global_basis.z
	var up = shadow.global_basis.y
	var right = shadow.global_basis.x
	
	var pos = shadow.global_position
	
	var corners = [
		pos + (up * size) + (right * size),
		pos + (up * size) - (right * size),
		pos - (up * size) + (right * size),
		pos - (up * size) - (right * size),
		
		
		pos + (up * size) + (right * size) + (forward * far),
		pos + (up * size) - (right * size) + (forward * far),
		pos - (up * size) + (right * size) + (forward * far),
		pos - (up * size) - (right * size) + (forward * far),
	]
	
	var world_aabb = AABB(corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		world_aabb = world_aabb.expand(corners[i])
#
	return world_aabb

	
func _update_buffer():
	view_proj = projection * shadow.view
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	if (global_uniform_mat4_name != ""):
		#print("setting mat4")
		RenderingServer.global_shader_parameter_set(global_uniform_mat4_name, view_proj)
	
	rd.buffer_update(view_proj_uniform_buffer, 0, cached_view_proj.size(), cached_view_proj)
	
func _setup():
	_update_projection()
	
	var view = shadow.view
	view_proj = projection * view
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	var view_proj_matrix = cached_view_proj
	view_proj_uniform_buffer = rd.uniform_buffer_create(view_proj_matrix.size(), view_proj_matrix)

	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)

	view_proj_uniform_set = rd.uniform_set_create([uniform], shadow.shader_rid, 0)
	
	_create_render_target()
	
	if (global_uniform_texture_name != ""):
		print(global_uniform_texture_name, " ", global_uniform_size_name, ", ", size)
		RenderingServer.global_shader_parameter_set(global_uniform_texture_name, color_texture)
		RenderingServer.global_shader_parameter_set(global_uniform_size_name, size)
	
func _create_render_target():
	color_texture = Texture2DRD.new()
	
	var color_format := RDTextureFormat.new()
	color_format.format = shadow.color_format.format
	color_format.usage_bits = shadow.color_format.usage_bits
	color_format.width = resolution.x
	color_format.height = resolution.y

	var depth_format := RDTextureFormat.new()
	depth_format.format = shadow.depth_format.format
	depth_format.usage_bits = shadow.depth_format.usage_bits
	depth_format.width = resolution.x
	depth_format.height = resolution.y

	var color_tex_rid := rd.texture_create(color_format, RDTextureView.new())
	var depth_tex_rid := rd.texture_create(depth_format, RDTextureView.new())
	
	color_texture.texture_rd_rid = color_tex_rid

	var pass2 := RDFramebufferPass.new()
	pass2.color_attachments = [0]
	pass2.depth_attachment = 1

	fb_rid = rd.framebuffer_create_multipass([color_tex_rid, depth_tex_rid], [pass2], shadow.fb_format)


func make_orthographic_projection() -> Projection:
	var half_size = size * 0.5
	var left = -half_size
	var right = half_size
	var bottom = -half_size
	var top = half_size

	var fn = far - near
	var rl = right - left
	var tb = top - bottom

	var x = Vector4(2.0 / rl, 0.0, 0.0, 0.0)
	var y = Vector4(0.0, 2.0 / tb, 0.0, 0.0)
	var z = Vector4(0.0, 0.0, 1.0 / fn, 0.0)
	var w = Vector4(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1.0)

	return Projection(x, y, z, w)
	
func make_perspective_projection() -> Projection:
	var fov = deg_to_rad(fov_deg)
	var aspect = resolution.x / resolution.y
	var f = 1.0 / tan(fov / 2.0)

	var x = Vector4(f / aspect, 0.0, 0.0, 0.0)
	var y = Vector4(0.0, f, 0.0, 0.0)
	var z = Vector4(0.0, 0.0, far / (far - near), 1.0)
	var w = Vector4(0.0, 0.0, -(far * near) / (far - near), 0.0)

	return Projection(x, y, z, w)
	
	
func get_fixed_view_transform(xform : Transform3D) -> Transform3D:
	xform.basis = xform.basis.orthonormalized()
	xform.basis.z = -xform.basis.z

	return xform.affine_inverse()
	
	
func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr
