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
var mesh_instances_model_buffers : Array[RID] = []
var mesh_instances_model_sets : Array[RID] = []

@export var shadow_tier_count = 2
@export var tier_settings: Array[ShadowTierSettings]

var shadow_tiers: Array[ShadowTier] = []

@export var vertex_shader_path: String = "res://shadow_system/shaders/shadow_vert.spv"
@export var fragment_shader_path: String = "res://shadow_system/shaders/shadow_frag.spv"

@export var debug_position := false

#var rect: TextureRect

var custom_aabb : AABB

func _ready() -> void:
	custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	rd = RenderingServer.get_rendering_device()
	
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	
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
	
	_setup_pipeline()
	_run_pipeline()

	call_deferred("_register_existing_shadow_meshes")
	call_deferred("_run")
	
	var shadow_aabb = shadow_tiers[0].aabb
	#draw_aabb_wireframe(shadow_aabb, self, Color.WHITE)
	
	
func _on_frame_pre_draw() -> void:
	if Engine.is_editor_hint(): return
	
	view = Projection(get_fixed_view_transform(global_transform))
	
	_run()
	

func get_tex():
	if shadow_tiers.size() > 0:
		return shadow_tiers[0].color_texture

func _run():
	for shadow_tier in shadow_tiers:
		shadow_tier._update_buffer()
	var shadow_aabb = shadow_tiers[0].aabb * global_transform
	_run_pipeline()
	
	if (debug_position): 
		RenderingServer.global_shader_parameter_set("light_pos", global_position)


func _run_pipeline():
	for shadow_tier in shadow_tiers:
		var shadow_world_aabb = shadow_tier._rebuild_light_local_aabb2()

		for i in range(mesh_instances.size()):
			var mesh = mesh_instances[i] as ShadowMesh
			if mesh.get_dirty():
				_update_model_buffer(mesh.get_model_matrix(), i)
				mesh.set_dirty(false)
		var draw_list = rd.draw_list_begin(shadow_tier.fb_rid, RenderingDevice.DRAW_CLEAR_ALL, clear_colors, 1.0, 0, Rect2(), 0)
		rd.draw_list_bind_render_pipeline(draw_list, pipeline)
		rd.draw_list_bind_uniform_set(draw_list, shadow_tier.view_proj_uniform_set, 0)
		var counter = 0;
		for i in range(mesh_instances.size()):
			var mesh = mesh_instances[i] as ShadowMesh
			if !mesh.is_visible(): continue
			
			var world_aabb = mesh.get_aabb() * mesh.global_transform
			if(shadow_world_aabb.intersects(world_aabb)):# || shadow_world_aabb.encloses(world_aabb)):
				var model_set = mesh_instances_model_sets[i]
				
				if mesh.is_indexed():
					rd.draw_list_bind_vertex_array(draw_list, mesh.get_vertex_array_rid())
					rd.draw_list_bind_index_array(draw_list, mesh.get_index_array_rid())
					rd.draw_list_bind_uniform_set(draw_list, model_set, 1)
					rd.draw_list_draw(draw_list, true, 1)
				else:
					rd.draw_list_bind_vertex_array(draw_list, mesh.get_vertex_array_rid())
					rd.draw_list_bind_uniform_set(draw_list, model_set, 1)
					rd.draw_list_draw(draw_list, false, 1)  # false = non-indexed draw
			else:
				counter += 1;
		#print(counter, " skipped due to AABB")
			
		rd.draw_list_end()


func _register_existing_shadow_meshes():
	for node in get_tree().get_nodes_in_group("shadow_meshes"):
		if node is ShadowMesh:
			_register_shadow_caster(node)

func _on_node_added(node: Node):
	if node is ShadowMesh:
		_register_shadow_caster(node)

	
func _register_shadow_caster(caster : ShadowMesh):
	mesh_instances.append(caster)
	_create_model_buffer(caster.get_model_matrix()) 
	
func _unregister_shadow_caster(caster: ShadowMesh):
	mesh_instances.erase(caster)
	
func _create_model_buffer(byte_array : PackedByteArray):
	var model_buffer = rd.uniform_buffer_create(byte_array.size(), byte_array)
	mesh_instances_model_buffers.append(model_buffer)
	var model_uniform = RDUniform.new()
	model_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	model_uniform.binding = 1
	model_uniform.add_id(model_buffer)
	
	mesh_instances_model_sets.append(rd.uniform_set_create([model_uniform], shader_rid, 1))

func _update_model_buffer(byte_array : PackedByteArray, index : int):
	rd.buffer_update(mesh_instances_model_buffers[index], 0, byte_array.size(), byte_array)
	
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
	mesh_instances.clear()
