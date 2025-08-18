@tool
extends Node3D
class_name Shadow

var rd: RenderingDevice

var shadow_helper : ShadowHelper

@export var camera_path: NodePath

var mesh_instances: Array[ShadowMesh] = []
var shadow_cascades: Array[ShadowCascade] = []

var vertex_shader_path: String = "res://shadow_system/shaders/new_shadow_vert.spv"
var frag_shader_path: String = "res://shadow_system/shaders/new_shadow_frag.spv"

@export var debug_position := false

@export var floating_origin := true
@export var floating_origin_provider_path : NodePath
var floating_origin_provider

var rect: TextureRect
var camera: Camera3D

var CASCADE_NUMBER = 6
var MAX_CASCADE = 20
var texture_format : RDTextureFormat
var depth_format_new : RDTextureFormat
var fb_format : int
var RESOLUTION = 2048#4096
var fb_rid
var pipeline : RID
var shader_rid : RID
var texture_array : Texture2DArrayRD

var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID


func _ready() -> void:
	camera = get_viewport().get_camera_3d()
	while camera == null:
		await get_tree().process_frame
		camera = get_viewport().get_camera_3d()
	
	rd = RenderingServer.get_rendering_device()
	
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	
	_load_shader()
	
	_setup_pipeline()
	_create_formats_new()
	
	_create_view_proj_buffer()
	
	shadow_helper = ShadowHelper.new()
	shadow_helper.init(rd, pipeline, shader_rid)

	call_deferred("_register_existing_shadow_meshes")
	
	camera = get_viewport().get_camera_3d()
	
	if(floating_origin && !floating_origin_provider_path.is_empty()):
		floating_origin_provider = get_node(floating_origin_provider_path)
	
	if(camera):
		_create_cascades()
	else: print("no camera")


func _create_cascades(split_count: int = CASCADE_NUMBER) -> void:
	shadow_cascades.clear()

	for i in range(split_count):
		var idx := i + 1
		var vp_name := "cascade_%d_view_proj" % idx
		var range_name := "cascade_%d_range" % idx

		var cascade := ShadowCascade.new(rd, self, camera, RESOLUTION, vp_name, range_name)
		cascade._create_cascade()
		shadow_cascades.append(cascade)

	_set_cascades()


func _set_cascades(lambda: float = 0.95, max_range = 100000, first_cascade = 60):
	var near = camera.near
	var far = min(max_range, camera.far)
	var split_start = near
	
	
	var v = 1 / float(shadow_cascades.size())
	var a = near + (far - near) * v
	var b = near * pow(far / near, v)
	
	lambda = (first_cascade - a) / (b - a)
		
	
	for i in shadow_cascades.size():
		var p = float(i + 1) / float(shadow_cascades.size())

		var linear_split = near + (far - near) * p
		var log_split = near * pow(far / near, p)
		
		var split_dist = lerp(linear_split, log_split, lambda)
		
		var split_end = split_dist
		
		print("cascade ", i, " : ", split_start, " ", split_end)
		
		var cascade = shadow_cascades[i]
		cascade._set_range(split_start, split_end)
		
		split_start = split_end
	
func _on_frame_pre_draw() -> void:
	if Engine.is_editor_hint() || !shadow_helper: return

	_update_model_matrices()
	
	for i in shadow_cascades.size():
		shadow_cascades[i]._create_cascade()
	
	_update_view_proj_buffer()
	_run_cascades_instanced()
		
func _update_model_matrices():
	shadow_helper.update_model_matrices(mesh_instances)

func _run_cascades_instanced():
	var aabb_info := _create_aabb()
	shadow_helper.run_cascades_instanced(fb_rid, view_proj_uniform_set, mesh_instances, CASCADE_NUMBER, aabb_info.transform, aabb_info.aabb)
	
func _create_aabb(near: float = camera.near, far: float = 100000.0) -> Dictionary:
	var corners := get_frustum_corners(camera, near, far)

	var center := Vector3.ZERO
	for p in corners:
		center += p
	center *= 1.0 / 8.0

	var light_dir := basis.z.normalized()
	var light_origin := center + light_dir * 250000.0
	var light_to_world := Transform3D(basis.orthonormalized(), light_origin)
	var world_to_light := light_to_world.affine_inverse()

	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var p : Vector3 = world_to_light * corners[i]
		min_v = min_v.min(p)
		max_v = max_v.max(p)

	var depth = -min_v.z
	max_v.z += depth

	var aabb := AABB(min_v, max_v - min_v)
	aabb.position.z *= 5
	aabb.size.z *= 4

	return {
		"transform": world_to_light,
		"aabb": aabb
	}


func _register_existing_shadow_meshes():
	for node in get_tree().get_nodes_in_group("shadow_meshes"):
		if node is ShadowMesh:
			_register_shadow_caster(node)

func _on_node_added(node: Node):
	if node is ShadowMesh:
		_register_shadow_caster(node)

	
func _register_shadow_caster(caster : ShadowMesh):
	mesh_instances.append(caster)
	
func _unregister_shadow_caster(caster: ShadowMesh):
	mesh_instances.erase(caster)

	
func get_fixed_view_transform(xform : Transform3D) -> Transform3D:
	xform.basis = xform.basis.orthonormalized()

	xform.basis.z = -xform.basis.z

	return xform.affine_inverse()


func _load_shader():
	var vert_code = FileAccess.get_file_as_bytes(vertex_shader_path)
	var frag_code = FileAccess.get_file_as_bytes(frag_shader_path)
	
	var shader_spirv = RDShaderSPIRV.new()
	shader_spirv.bytecode_vertex = vert_code
	shader_spirv.bytecode_fragment = frag_code
		
	if shader_spirv.compile_error_vertex == "" and shader_spirv.compile_error_fragment == "":
		shader_rid = rd.shader_create_from_spirv(shader_spirv)
	else:
		push_error("Shader compilation failed!")


func _create_formats_new():
	texture_format = RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	texture_format.array_layers = CASCADE_NUMBER
	texture_format.width = RESOLUTION
	texture_format.height = RESOLUTION
	
	depth_format_new = RDTextureFormat.new()
	depth_format_new.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	depth_format_new.usage_bits = (RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT) 
	depth_format_new.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	depth_format_new.array_layers = CASCADE_NUMBER
	depth_format_new.width = RESOLUTION
	depth_format_new.height = RESOLUTION
		
	var color_attach2 := RDAttachmentFormat.new()
	color_attach2.format = texture_format.format
	color_attach2.usage_flags = texture_format.usage_bits

	var depth_attach2 := RDAttachmentFormat.new()
	depth_attach2.format = depth_format_new.format
	depth_attach2.usage_flags = depth_format_new.usage_bits
	
	var color_tex_rid := rd.texture_create(texture_format, RDTextureView.new())
	var depth_tex_rid := rd.texture_create(depth_format_new, RDTextureView.new())
	
	texture_array = Texture2DArrayRD.new()
	texture_array.texture_rd_rid = color_tex_rid
	
	RenderingServer.global_shader_parameter_set("cascade_maps", texture_array)

	fb_format = rd.framebuffer_format_create([color_attach2, depth_attach2], CASCADE_NUMBER) 
	fb_rid = rd.framebuffer_create([color_tex_rid, depth_tex_rid], fb_format, CASCADE_NUMBER)
	
	
func _create_view_proj_buffer():
	var byte_array : PackedByteArray
	var matrix_size = 64 * MAX_CASCADE
	var range_size = 16 * MAX_CASCADE # 12 bytes for range, 4 per pad
	var info_size = 16 # 4bytes for cascade count, 4 bytes for resolutiom, 8 for pad
	byte_array.resize(matrix_size + range_size + info_size) 
	view_proj_uniform_buffer = rd.uniform_buffer_create(byte_array.size(), byte_array)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)
	
	view_proj_uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)


func _update_view_proj_buffer():
	if shadow_cascades.size() != CASCADE_NUMBER:
		return
	
	var byte_array = PackedByteArray()
	var range_array = PackedVector4Array()
	var dummy_array = PackedByteArray()
	dummy_array.resize(64)
	
	for i in range(MAX_CASCADE):
		if i < CASCADE_NUMBER:
			byte_array.append_array(shadow_cascades[i].cached_view_proj)
		else:
			byte_array.append_array(dummy_array) # 64 bytes of zero 
	
	for i in range(MAX_CASCADE):
		if i < CASCADE_NUMBER:
			var r = shadow_cascades[i]._range
			range_array.append(Vector4(r.x, r.y, r.z, 0.0))
		else:
			range_array.append(Vector4.ZERO)
	
	# Info (vec4)
	var info = PackedFloat32Array([float(CASCADE_NUMBER), float(RESOLUTION), 0.0, 0.0])
	
	# Append all to buffer
	byte_array.append_array(range_array.to_byte_array())
	byte_array.append_array(info.to_byte_array())
	
	rd.buffer_update(view_proj_uniform_buffer, 0, byte_array.size(), byte_array)


func _setup_pipeline():
	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0

	var vertex_format = rd.vertex_format_create([vertex_attr])

	var raster = RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_FRONT

	var depth = RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS

	var msaa = RDPipelineMultisampleState.new()
	var blend = RDPipelineColorBlendState.new()
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()
	blend_attachment.enable_blend = false
	blend.attachments = [blend_attachment]

	pipeline = rd.render_pipeline_create(shader_rid, fb_format, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)


#func _exit_tree():
	#if pipeline.is_valid(): rd.free_rid(pipeline)


func get_frustum_corners(_camera: Camera3D, near: float, far: float) -> Array:
	var corners = []

	var fov = _camera.fov
	var aspect = get_viewport().get_visible_rect().size.aspect()
	#var aspect = 1920.0 / 1080.0 #replace with viewport aspect ratio

	var height_near = 2.0 * tan(deg_to_rad(fov) * 0.5) * near
	var width_near = height_near * aspect
	var height_far = 2.0 * tan(deg_to_rad(fov) * 0.5) * far
	var width_far = height_far * aspect

	var cam_transform = _camera.global_transform
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
