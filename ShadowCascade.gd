extends Node
class_name ShadowCascade

var color_texture: Texture2DRD

var start : float
var end : float

var shadow : Shadow
var rd : RenderingDevice
var camera : Camera3D
var near : float
var far : float
var resolution : int

var fb_rid

var view : Transform3D
var projection : Projection
var view_proj : Projection
var cached_view_proj : PackedByteArray
var _range : Vector4

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID

var glob_mat_name : String = ""
var glob_range_name : String = ""


func _init(_rd : RenderingDevice, _shadow : Shadow, _camera : Camera3D, _resolution : int, _glob_mat_name : String = "", _glob_range_name : String = "") -> void:
	rd = _rd
	shadow = _shadow
	camera = _camera
	resolution = _resolution
	
	glob_mat_name = _glob_mat_name
	glob_range_name = _glob_range_name
	
func _set_range(_near : float, _far : float):
	near = _near
	far = _far
	
	
func _create_cascade():
	#https://alextardif.com/shadowmapping.html
	var corners = get_frustum_corners(near, far * 1.0);
	var world_center := Vector3.ZERO
	for c in corners:
		world_center += c;
	world_center /= 8
		
	var light_origin = world_center + (shadow.basis.z.normalized() * 250000)
	var cascade_transform := Transform3D(shadow.basis.orthonormalized(), light_origin).affine_inverse()
	
	var radius : float = (world_center - corners[6]).length()# * 0.75#(corners[0] - corners[6]).length() * 0.5 #top left to bottom right
	var texels_per_unit = (resolution / (radius * 2.0));
	
	var floating_offset : Vector3 = Vector3.ZERO
	if shadow.floating_origin:
		floating_offset = _get_floating_offset()
		floating_offset = cascade_transform.basis * floating_offset
		
		floating_offset.z = 0
		floating_offset.x = fposmod(floating_offset.x * texels_per_unit, 1.0) / texels_per_unit
		floating_offset.y = fposmod(floating_offset.y * texels_per_unit, 1.0) / texels_per_unit
	
	var l = cascade_transform * world_center
	l.x = floor(l.x * texels_per_unit) / texels_per_unit
	l.y = floor(l.y * texels_per_unit) / texels_per_unit
	
	l += floating_offset
	
	cascade_transform.origin = l
	
	for i in corners.size():
		corners[i] = cascade_transform * (corners[i])

	var min_v = corners[0]
	var max_v = corners[0]
		
	for c in corners:
		min_v = min_v.min(c)
		max_v = max_v.max(c)
	
	var center_x = floor(((min_v.x + max_v.x) * 0.5) * texels_per_unit) / texels_per_unit
	var center_y = floor(((min_v.y + max_v.y) * 0.5) * texels_per_unit) / texels_per_unit
	
	var half_size = ceil(radius * texels_per_unit) / texels_per_unit
	
	var left = center_x - half_size
	var right = center_x + half_size
	var bottom = center_y - half_size
	var top = center_y + half_size
	
	var near_p = -0.001#max.z
	var far_p  = min_v.z

	projection = make_ortho_from_bounds(left, right, bottom, top, near_p, far_p)
	
	view_proj = projection * Projection(cascade_transform)
	cached_view_proj = flatten_projection_column_major(view_proj).to_byte_array()
	
	if (glob_mat_name != ""):
		RenderingServer.global_shader_parameter_set(glob_mat_name, view_proj)
	if (glob_range_name != ""):
		_range = Vector4(near, far, abs(far_p - near_p), 0.0)
		RenderingServer.global_shader_parameter_set(glob_range_name, Vector3(near, far, abs(far_p - near_p)))
		

func _get_floating_offset():
	if shadow.floating_origin_provider && shadow.floating_origin_provider.has_method("get_accumulated_offset"):
		return shadow.floating_origin_provider.get_accumulated_offset()
	else:
		return Vector3.ZERO
	

func make_ortho_from_bounds(left, right, bottom, top, _near, _far) -> Projection:
	var rl = right - left
	var tb = top   - bottom
	var fn = _far   - _near

	var x = Vector4( 2.0 / rl, 0.0,       0.0,       0.0)
	var y = Vector4( 0.0,      2.0 / tb,  0.0,       0.0)
	var z = Vector4( 0.0,      0.0,      1.0 / fn,   0.0)
	var w = Vector4(-(right+left)/rl, -(top+bottom)/tb, -_near/fn, 1.0)

	return Projection(x, y, z, w)
	

func get_frustum_corners(_near: float, _far: float) -> Array:
	var corners = []

	var fov = camera.fov
	var aspect = camera.get_viewport().get_visible_rect().size.aspect()
	#var aspect = 1920.0 / 1080.0 #replace with viewport aspect ratio

	var height_near = 2.0 * tan(deg_to_rad(fov) * 0.5) * _near
	var width_near = height_near * aspect
	var height_far = 2.0 * tan(deg_to_rad(fov) * 0.5) * _far
	var width_far = height_far * aspect

	var cam_transform = camera.global_transform
	var forward = -cam_transform.basis.z
	var right = cam_transform.basis.x
	var up = cam_transform.basis.y

	var near_center = cam_transform.origin + forward * _near
	var far_center = cam_transform.origin + forward * _far

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
	
	
func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr
