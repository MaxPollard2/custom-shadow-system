extends Node
class_name ShadowCascade

var resolution = Vector2(4096, 4096)#(2048, 2048)#
var color_texture: Texture2DRD

var start : float
var end : float

var shadow : Shadow
var rd : RenderingDevice
var camera : Camera3D
var near : float
var far : float

var fb_rid

var view : Transform3D
var projection : Projection
var view_proj : Projection
var cached_view_proj : PackedByteArray

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID


var glob_tex_name : String = ""
var glob_mat_name : String = ""
var glob_range_name : String = ""


func _init(_rd : RenderingDevice, _shadow : Shadow, _camera : Camera3D, _near : float, _far : float, _glob_tex_name : String = "", _glob_mat_name : String = "", _glob_range_name : String = "") -> void:
	rd = _rd
	shadow = _shadow
	camera = _camera
	near = _near
	far = _far
	
	glob_tex_name = _glob_tex_name
	glob_mat_name = _glob_mat_name
	glob_range_name = _glob_range_name
	
	_setup_buffers()
	
	
func _setup_buffers() -> void:
	var view_proj_matrix = flatten_projection_column_major(Projection.ZERO).to_byte_array()
	view_proj_uniform_buffer = rd.uniform_buffer_create(view_proj_matrix.size(), view_proj_matrix)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)
	
	view_proj_uniform_set = rd.uniform_set_create([uniform], shadow.shader_rid, 0)
	
	_create_render_target()
	
func _create_cascade():
	#https://alextardif.com/shadowmapping.html
	var corners = get_frustum_corners(camera, near, far * 1.0);
	var world_center := Vector3.ZERO
	for c in corners:
		world_center += c;
	world_center /= 8
		
	var light_origin = world_center + (shadow.basis.z.normalized() * 250000)
	var cascade_transform := Transform3D(shadow.basis.orthonormalized(), light_origin).affine_inverse()
	
	var radius : float = (world_center - corners[6]).length()#(corners[0] - corners[6]).length() * 0.5 #top left to bottom right
	var texelsPerUnit = (resolution.x / (radius * 2.0));
	
	var l = cascade_transform * world_center
	l.x = round(l.x * texelsPerUnit) / texelsPerUnit
	l.y = round(l.y * texelsPerUnit) / texelsPerUnit
	cascade_transform.origin = l
	
	for i in corners.size():
		corners[i] = cascade_transform * (corners[i])

	var min_v = corners[0]
	var max_v = corners[0]
		
	for c in corners:
		min_v = min_v.min(c)
		max_v = max_v.max(c)
	
	var center_x = floor(((min_v.x + max_v.x) * 0.5) * texelsPerUnit) / texelsPerUnit
	var center_y = floor(((min_v.y + max_v.y) * 0.5) * texelsPerUnit) / texelsPerUnit
	
	var half_size = ceil(radius * texelsPerUnit) / texelsPerUnit
	
	var left = center_x - half_size
	var right = center_x + half_size
	var bottom = center_y - half_size
	var top = center_y + half_size
	
	var near_p = -0.001#max.z
	var far_p  = min_v.z

	projection = make_ortho_from_bounds(left, right, bottom, top, near_p, far_p)
	
	var view_proj = projection * Projection(cascade_transform)
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	if (glob_mat_name != ""):
		RenderingServer.global_shader_parameter_set(glob_mat_name, view_proj)
	if (glob_range_name != ""):
		RenderingServer.global_shader_parameter_set(glob_range_name, Vector3(near, far, abs(far_p - near_p)))

	
	rd.buffer_update(view_proj_uniform_buffer, 0, cached_view_proj.size(), cached_view_proj)
	

func make_ortho_from_bounds(left, right, bottom, top, near, far) -> Projection:
	var rl = right - left
	var tb = top   - bottom
	var fn = far   - near

	var x = Vector4( 2.0 / rl, 0.0,       0.0,       0.0)
	var y = Vector4( 0.0,      2.0 / tb,  0.0,       0.0)
	var z = Vector4( 0.0,      0.0,      1.0 / fn,   0.0)
	var w = Vector4(-(right+left)/rl, -(top+bottom)/tb, -near/fn, 1.0)

	return Projection(x, y, z, w)
	

func get_frustum_corners(camera: Camera3D, near: float, far: float) -> Array:
	var corners = []

	var fov = camera.fov
	var aspect = get_viewport().get_visible_rect().size.aspect()
	#var aspect = 1920.0 / 1080.0 #replace with viewport aspect ratio

	var height_near = 2.0 * tan(deg_to_rad(fov) * 0.5) * near
	var width_near = height_near * aspect
	var height_far = 2.0 * tan(deg_to_rad(fov) * 0.5) * far
	var width_far = height_far * aspect

	var cam_transform = camera.global_transform
	var forward = -cam_transform.basis.z
	var right = cam_transform.basis.x
	var up = cam_transform.basis.y

	var near_center = cam_transform.origin + forward * near
	var far_center = cam_transform.origin + forward * far

	# Near plane
	corners.append(near_center + up * (height_near * 0.5) - right * (width_near * 0.5)) # top left
	corners.append(near_center + up * (height_near * 0.5) + right * (width_near * 0.5)) # top right
	corners.append(near_center - up * (height_near * 0.5) - right * (width_near * 0.5)) # bottom left
	corners.append(near_center - up * (height_near * 0.5) + right * (width_near * 0.5)) # bottom right

	# Far plane
	corners.append(far_center + up * (height_far * 0.5) - right * (width_far * 0.5)) # top left
	corners.append(far_center + up * (height_far * 0.5) + right * (width_far * 0.5)) # top right
	corners.append(far_center - up * (height_far * 0.5) - right * (width_far * 0.5)) # bottom left
	corners.append(far_center - up * (height_far * 0.5) + right * (width_far * 0.5)) # bottom right

	return corners
	
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

	fb_rid = rd.framebuffer_create([color_tex_rid, depth_tex_rid], shadow.fb_format)
	
	if (glob_tex_name != ""):
		RenderingServer.global_shader_parameter_set(glob_tex_name, color_texture)
		print("setting tex")
		#RenderingServer.global_shader_parameter_set(global_uniform_size_name, size)
	
	
func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr
