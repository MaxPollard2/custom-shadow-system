@tool
extends Node
class_name ShadowMesh

signal shadow_caster_ready(caster: ShadowMesh)

var rd: RenderingDevice
var mesh: Mesh
var shader_rid: RID

var vertex_array_rid: RID
var index_array_rid: RID
var model_buffer: RID
var model_uniform_set: RID

var last_global_transform: Transform3D

var shadow : Shadow

var visible := true

func _ready():
	add_to_group("shadow_meshes")
	var parent = get_parent()
	if parent is MeshInstance3D:
		mesh = parent.mesh
		if mesh:
			last_global_transform = parent.global_transform
			emit_signal("shadow_caster_ready", self)
			

			
func _process(_delta: float) -> void:
	var current_transform = get_parent().global_transform
	if current_transform != last_global_transform:
		last_global_transform = current_transform
		if rd:
			update_model_matrix()

func initialize(rd_: RenderingDevice, shader_rid_: RID, _shadow):
	if !mesh:
		var parent = get_parent()
		if parent is MeshInstance3D:
			mesh = parent.mesh
			if mesh:
				last_global_transform = parent.global_transform
				emit_signal("shadow_caster_ready", self)
	
	rd = rd_
	shader_rid = shader_rid_
	shadow = _shadow

	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.offset = 0
	vertex_attr.stride = 12
	vertex_attr.location = 0

	var vertex_format = rd.vertex_format_create([vertex_attr])

	var arrays = mesh.surface_get_arrays(0)
	var vertex_array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices = arrays[Mesh.ARRAY_INDEX]# as PackedInt32Array
	
	var vertex_buffer = rd.vertex_buffer_create(vertex_array.size() * 12, vertex_array.to_byte_array())
	vertex_array_rid = rd.vertex_array_create(vertex_array.size(), vertex_format, [vertex_buffer])
	
	if arrays[Mesh.ARRAY_INDEX]:
		var index_buffer = rd.index_buffer_create(indices.size(), RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, indices.to_byte_array())
		index_array_rid = rd.index_array_create(index_buffer, 0, indices.size())
	else:
		index_array_rid = RID()  # Invalid RID to indicate no index buffer
	
	var model_matrix = flatten_mat4_column_major(transform3d_to_mat4(get_parent().global_transform))
	model_buffer = rd.uniform_buffer_create(model_matrix.size() * 4, model_matrix.to_byte_array())

	var model_uniform = RDUniform.new()
	model_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	model_uniform.binding = 1
	model_uniform.add_id(model_buffer)

	model_uniform_set = rd.uniform_set_create([model_uniform], shader_rid, 1)


func update_model_matrix():
	var model = get_parent().global_transform
	var packed = flatten_mat4_column_major(transform3d_to_mat4(model)).to_byte_array()
	rd.buffer_update(model_buffer, 0, packed.size(), packed)

# Accessors
func get_vertex_array_rid() -> RID: return vertex_array_rid
func get_index_array_rid() -> RID: return index_array_rid
func get_model_uniform_set() -> RID: return model_uniform_set

func has_index_array() -> bool:
	return index_array_rid.is_valid()

func _exit_tree() -> void:
	shadow._unregister_shadow_caster(self)
	rd.free_rid(vertex_array_rid)
	if (get_index_array_rid().is_valid()): rd.free_rid(index_array_rid)
	rd.free_rid(model_uniform_set)

func transform3d_to_mat4(xform: Transform3D) -> Array:
	return [
		[xform.basis.x.x, xform.basis.y.x, xform.basis.z.x, xform.origin.x],
		[xform.basis.x.y, xform.basis.y.y, xform.basis.z.y, xform.origin.y],
		[xform.basis.x.z, xform.basis.y.z, xform.basis.z.z, xform.origin.z],
		[0.0,             0.0,             0.0,             1.0],
	]

func flatten_mat4_column_major(m: Array) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for col in range(4):
		for row in range(4):
			arr.append(m[row][col])
	return arr
