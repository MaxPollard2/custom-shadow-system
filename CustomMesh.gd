@tool
extends Node3D
class_name CustomMesh

enum AlbedoMode {
	Texture,
	Vertex,
	BaseColor
}

@export var base_albedo_type: AlbedoMode = AlbedoMode.Texture
@export var albedo_texture: Texture2D
@export var albedo_color: Color = Color(1.0, 1.0, 1.0)

@export var mesh : Mesh
var material: ShaderMaterial

@export var shadow_path: NodePath

var mesh_instance : MeshInstance3D
var shadow_instance : ShadowMesh

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	shadow_instance = ShadowMesh.new()
	
	add_child(mesh_instance)
	add_child(shadow_instance)
	
	
	if mesh:
		if mesh.resource_name != "": 
			name = mesh.resource_name
			print("hi")
			
		mesh_instance.mesh = mesh
		shadow_instance.generate_from_mesh(mesh_instance)
		var mesh_arrays = mesh_instance.mesh.surface_get_arrays(0)
		var vertex_array = mesh_arrays[mesh.ARRAY_VERTEX] as PackedVector3Array
		shadow_instance.set_aabb(mesh_instance.get_aabb())
		
	material = ShaderMaterial.new()
	material.shader = preload("res://shadow_system/newmain.gdshader").duplicate()
	_process_material()

	if material and mesh_instance:
		for s in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(s, material)
	

func _process_material():
	if material:
		match base_albedo_type:
			AlbedoMode.Texture:
				material.set_shader_parameter("albedo_type", 0)
				material.set_shader_parameter("albedo_texture", albedo_texture)
			AlbedoMode.Vertex:
				material.set_shader_parameter("albedo_type", 1)
			AlbedoMode.BaseColor:
				material.set_shader_parameter("albedo_type", 2)
				material.set_shader_parameter("albedo_color", albedo_color)

		for s in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(s, material)
