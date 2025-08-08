@tool
extends Node3D
class_name Shadow

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var clear_colors: PackedColorArray

var view : Projection

var shadow_helper : ShadowHelper

@export var camera_path: NodePath

var mesh_instances: Array[ShadowMesh] = []
var shadow_cascades: Array[ShadowCascade] = []

@export var new_vertex_shader_path: String = "res://shadow_system/shaders/new_shadow_vert.spv"
@export var new_frag_shader_path: String = "res://shadow_system/shaders/new_shadow_frag.spv"
@export var vertex_shader_path: String = "res://shadow_system/shaders/shadow_vert.spv"
@export var fragment_shader_path: String = "res://shadow_system/shaders/shadow_frag.spv"

@export var debug_position := false

var rect: TextureRect
var camera: Camera3D

var CASCADE_NUMBER = 5


func _ready() -> void:
	camera = get_viewport().get_camera_3d()
	while camera == null:
		await get_tree().process_frame
		camera = get_viewport().get_camera_3d()
	
	
	rd = RenderingServer.get_rendering_device()
	
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	
	var view = Projection(get_fixed_view_transform(global_transform))

	_load_shader()
	_create_formats()
	
	_setup_pipeline()
	
	_create_formats_new()
	_create_view_proj_buffer()
	
	shadow_helper = ShadowHelper.new()
	shadow_helper.init(rd, pipeline, shader_rid, new_pipeline)

	call_deferred("_register_existing_shadow_meshes")
	
	camera = get_viewport().get_camera_3d()
	
	if(camera):
		_create_cascades()
	else: print("no camera")
	


func _create_cascades(split_count: int = CASCADE_NUMBER, lambda: float = 0.99975) -> void:
	var near = camera.near
	var far = camera.far
	shadow_cascades.clear()
	
	for i in range(split_count):
		var p = float(i + 1) / float(split_count)

		var linear_split = near + (far - near) * p
		var log_split = near * pow(far / near, p)
		
		var split_dist = lerp(linear_split, log_split, lambda)

		var split_start =  near if (i == 0) else shadow_cascades[i - 1].end
		var split_end = split_dist
		
		print("cascade ", i, " : ", split_start, " ", split_end)
		
		var cascade
		if (i == 0):
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end, "cascade_1_map", "cascade_1_view_proj", "cascade_1_range")
		elif (i == 1):
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end, "cascade_2_map", "cascade_2_view_proj", "cascade_2_range")
		elif (i == 2):
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end, "cascade_3_map", "cascade_3_view_proj", "cascade_3_range")
		elif (i == 3):
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end, "cascade_4_map", "cascade_4_view_proj", "cascade_4_range")
		elif (i == 4):
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end, "cascade_5_map", "cascade_5_view_proj", "cascade_5_range")
		else:
			cascade = ShadowCascade.new(rd, self, camera, split_start, split_end)
		add_child(cascade)
		cascade._create_cascade()
		cascade.start = split_start
		cascade.end = split_end
		shadow_cascades.append(cascade)
	
func _on_frame_pre_draw() -> void:
	if Engine.is_editor_hint() || !shadow_helper: return
	
	#view = Projection(get_fixed_view_transform(global_transform))

	_update_model_matrices()
	
	for i in shadow_cascades.size():
		shadow_cascades[i]._create_cascade()
		#shadow_helper.run_cascade_no_aabb(shadow_cascades[i].fb_rid, shadow_cascades[i].view_proj_uniform_set, mesh_instances)
	
	_update_view_proj_buffer()
	_run_cascades_instanced()
		
func _update_model_matrices():
	shadow_helper.update_model_matrices(mesh_instances)

func _run_cascades_instanced():
	shadow_helper.run_cascades_instanced(fb_rid, view_proj_uniform_set, mesh_instances, CASCADE_NUMBER)

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
	var new_vert_code = FileAccess.get_file_as_bytes(new_vertex_shader_path)
	var new_frag_code = FileAccess.get_file_as_bytes(new_frag_shader_path)
	var vert_code = FileAccess.get_file_as_bytes(vertex_shader_path)
	var frag_code = FileAccess.get_file_as_bytes(fragment_shader_path)

	var shader_spirv = RDShaderSPIRV.new()
	shader_spirv.bytecode_vertex = vert_code
	shader_spirv.bytecode_fragment = frag_code
	
	var new_shader_spirv = RDShaderSPIRV.new()
	new_shader_spirv.bytecode_vertex = new_vert_code
	new_shader_spirv.bytecode_fragment = new_frag_code

	if shader_spirv.compile_error_vertex == "" and shader_spirv.compile_error_fragment == "":
		shader_rid = rd.shader_create_from_spirv(shader_spirv)
	else:
		push_error("Shader compilation failed!")
		
	if new_shader_spirv.compile_error_vertex == "" and new_shader_spirv.compile_error_fragment == "":
		new_shader_rid = rd.shader_create_from_spirv(new_shader_spirv)
	else:
		push_error("Shader compilation failed!")



var texture_format : RDTextureFormat
var depth_format_new : RDTextureFormat
var fb_format2 : int
var RESOLUTION = 4096
var fb_rid
var new_pipeline : RID
var new_shader_rid : RID
var texture_array : Texture2DArrayRD

func _create_formats_new():
	texture_format = RDTextureFormat.new()
	#texture_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	texture_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	#texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
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
	depth_format_new.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
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
	print(texture_array.get_format())
	texture_array.texture_rd_rid = color_tex_rid
	print(texture_array.get_format())
	
	RenderingServer.global_shader_parameter_set("cascade_maps", texture_array)

	#fb_format2 = rd.framebuffer_format_create([color_attach, depth_attach])
	fb_format2 = rd.framebuffer_format_create([color_attach2, depth_attach2], CASCADE_NUMBER) 
	fb_rid = rd.framebuffer_create([color_tex_rid, depth_tex_rid], fb_format2, CASCADE_NUMBER)
	
	
var view_proj_uniform_buffer: RID
var view_proj_uniform_set: RID
func _create_view_proj_buffer():
	var byte_array : PackedByteArray
	byte_array.resize(64 * CASCADE_NUMBER)
	view_proj_uniform_buffer = rd.uniform_buffer_create(byte_array.size(), byte_array)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(view_proj_uniform_buffer)
	
	view_proj_uniform_set = rd.uniform_set_create([uniform], new_shader_rid, 0)
	
func _update_view_proj_buffer():
	if shadow_cascades.size() != CASCADE_NUMBER: return
	
	var byte_array : PackedByteArray
	for cascade in shadow_cascades:
		byte_array.append_array(cascade.cached_view_proj)
		
	rd.buffer_update(view_proj_uniform_buffer, 0, byte_array.size(), byte_array)


var color_format : RDTextureFormat
var depth_format : RDTextureFormat
var fb_format : int


func _create_formats():
	color_format = RDTextureFormat.new()
	color_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	color_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	depth_format = RDTextureFormat.new()
	depth_format.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	depth_format.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	
	var color_attach := RDAttachmentFormat.new()
	color_attach.format = color_format.format
	color_attach.usage_flags = color_format.usage_bits

	var depth_attach := RDAttachmentFormat.new()
	depth_attach.format = depth_format.format
	depth_attach.usage_flags = depth_format.usage_bits

	fb_format = rd.framebuffer_format_create([color_attach, depth_attach])

func _setup_pipeline():
	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0
	vertex_attr.frequency

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
	new_pipeline = rd.render_pipeline_create(new_shader_rid, fb_format2, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)
	
	clear_colors = PackedColorArray([Color(1.0, 0, 0, 0.5), Color(0, 0, 0, 0.5), Color(0, 0, 0, 1)])


func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr

	
func _exit_tree():
	if pipeline.is_valid(): rd.free_rid(pipeline)
