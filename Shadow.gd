@tool
extends Node3D
class_name Shadow

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var clear_colors: PackedColorArray

var view : Projection

@export var orthographic := false:
	set(value):
		orthographic = value
		for shadow_tier in shadow_tiers:
			shadow_tier.orthographic = value
			shadow_tier._update_projection()

#@export var rect_path: NodePath
@export var camera_path: NodePath

var mesh_instances: Array[ShadowMesh] = []

@export var shadow_tier_count = 2
@export var tier_settings: Array[ShadowTierSettings]

var shadow_tiers: Array[ShadowTier] = []

@export var vertex_shader_path: String = "res://shadow_system/shaders/shadow_vert.spv"
@export var fragment_shader_path: String = "res://shadow_system/shaders/shadow_frag.spv"

#var rect: TextureRect


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	
	var view = Projection(get_fixed_view_transform(global_transform))

	_load_shader()
	_create_formats()

	for i in shadow_tier_count:
		shadow_tiers.append(ShadowTier.new(self, rd))
		if (i < tier_settings.size()):
			shadow_tiers[i].resolution = tier_settings[i].resolution
			shadow_tiers[i].far = tier_settings[i].far
			shadow_tiers[i].near = tier_settings[i].near
			shadow_tiers[i].size = tier_settings[i].size
			shadow_tiers[i].global_uniform_texture_name = tier_settings[i].global_uniform_texture_name
			shadow_tiers[i].global_uniform_mat4_name = tier_settings[i].global_uniform_mat4_name
			shadow_tiers[i].global_uniform_size_name = tier_settings[i].global_uniform_size_name
		shadow_tiers[i]._setup()
		#shadow_tier._init(self, rd)
	
	
	_setup_pipeline()
	
	_run_pipeline()
	
	#rect = get_node(rect_path)
	#rect.texture =  shadow_tiers[0].color_texture;
	
	get_tree().connect("node_added", Callable(self, "_on_node_added"))
	call_deferred("_register_existing_shadow_meshes")
	call_deferred("_run", 0.0)

	#print("Shadow, online.")	
	
	
	
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_run(delta)
	
	view = Projection(get_fixed_view_transform(global_transform))
	
#var counter = 0
#var first = true
#func _physics_process(delta: float) -> void:
	#counter += 1
	#if counter == 120:
		#if first:
			#rect.texture =  shadow_tiers[0].color_texture;
		#else:
			#rect.texture =  shadow_tiers[1].color_texture;
		#first = !first
		#counter = 0
	

func get_tex():
	if shadow_tiers.size() > 0:
		return shadow_tiers[0].color_texture

func _run(delta: float):
	for shadow_tier in shadow_tiers:
		shadow_tier._update_buffer()
		
	_run_pipeline()
	
	#RenderingServer.global_shader_parameter_set("light_pos", global_position)


func _run_pipeline():
	for shadow_tier in shadow_tiers:
		var draw_list = rd.draw_list_begin(shadow_tier.fb_rid, RenderingDevice.DRAW_CLEAR_ALL, clear_colors, 1.0, 0, Rect2(), 0)
		rd.draw_list_bind_render_pipeline(draw_list, pipeline)
		rd.draw_list_bind_uniform_set(draw_list, shadow_tier.view_proj_uniform_set, 0)
		for i in range(mesh_instances.size()):
			var mesh = mesh_instances[i]
			if mesh.visible == false: continue
			rd.draw_list_bind_vertex_array(draw_list, mesh.get_vertex_array_rid())

			if mesh.has_index_array():
				rd.draw_list_bind_index_array(draw_list, mesh.get_index_array_rid())
				rd.draw_list_bind_uniform_set(draw_list, mesh.get_model_uniform_set(), 1)
				rd.draw_list_draw(draw_list, true, 1)
			else:
				rd.draw_list_bind_uniform_set(draw_list, mesh.get_model_uniform_set(), 1)
				rd.draw_list_draw(draw_list, false, 1)  # false = non-indexed draw
		rd.draw_list_end()
	
func _register_existing_shadow_meshes():
	for node in get_tree().get_nodes_in_group("shadow_meshes"):
		_register_shadow_caster(node)


func _on_node_added(node: Node):
	if node is ShadowMesh:
		_register_shadow_caster(node)


func _register_shadow_caster(caster: ShadowMesh):
	caster.initialize(rd, shader_rid, self)
	mesh_instances.append(caster)
	
func _unregister_shadow_caster(caster: ShadowMesh):
	mesh_instances.erase(caster)
	
func get_fixed_view_transform(xform : Transform3D) -> Transform3D:
	xform.basis = xform.basis.orthonormalized()

	xform.basis.z = -xform.basis.z

	return xform.affine_inverse()


func _load_shader():
	var vert_code = FileAccess.get_file_as_bytes(vertex_shader_path)
	var frag_code = FileAccess.get_file_as_bytes(fragment_shader_path)

	var shader_spirv = RDShaderSPIRV.new()
	shader_spirv.bytecode_vertex = vert_code
	shader_spirv.bytecode_fragment = frag_code

	if shader_spirv.compile_error_vertex != "":
		print("Vertex shader error:\n", shader_spirv.compile_error_vertex)
	if shader_spirv.compile_error_fragment != "":
		print("Fragment shader error:\n", shader_spirv.compile_error_fragment)

	if shader_spirv.compile_error_vertex == "" and shader_spirv.compile_error_fragment == "":
		shader_rid = rd.shader_create_from_spirv(shader_spirv)
	else:
		push_error("Shader compilation failed!")


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

	var vertex_format = rd.vertex_format_create([vertex_attr])

	var raster = RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_FRONT

	var depth = RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS
	#depth.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER

	var msaa = RDPipelineMultisampleState.new()
	var blend = RDPipelineColorBlendState.new()
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()
	blend_attachment.enable_blend = false
	blend.attachments = [blend_attachment]

	pipeline = rd.render_pipeline_create(shader_rid, fb_format, vertex_format, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, msaa, depth, blend)
	
	clear_colors = PackedColorArray([Color(1.0, 0, 0, 0.5), Color(0, 0, 0, 0.5), Color(0, 0, 0, 1)])


func flatten_projection_column_major(p: Projection) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.append_array([p.x.x, p.x.y, p.x.z, p.x.w])
	arr.append_array([p.y.x, p.y.y, p.y.z, p.y.w])
	arr.append_array([p.z.x, p.z.y, p.z.z, p.z.w])
	arr.append_array([p.w.x, p.w.y, p.w.z, p.w.w])
	return arr

	
func _exit_tree():
	rd.free_rid(pipeline)
	#rect.texture = null
	mesh_instances.clear()
