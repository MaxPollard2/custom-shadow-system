#include "ShadowMesh.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/classes/rd_vertex_attribute.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/classes/rendering_server.hpp>



using namespace godot;

void ShadowMesh::_bind_methods() {
    // Core methods
    ClassDB::bind_method(D_METHOD("generate_from_mesh", "mesh_instance_3d"), &ShadowMesh::generate_from_mesh);
    ClassDB::bind_method(D_METHOD("update_from_mesh", "mesh_instance_3d"), &ShadowMesh::update_from_mesh);
    ClassDB::bind_method(D_METHOD("update_model_matrix"), &ShadowMesh::update_model_matrix);

    // Accessors
    ClassDB::bind_method(D_METHOD("get_vertex_array_rid"), &ShadowMesh::get_vertex_array_rid);
    ClassDB::bind_method(D_METHOD("get_index_array_rid"), &ShadowMesh::get_index_array_rid);
    ClassDB::bind_method(D_METHOD("has_index_array"), &ShadowMesh::has_index_array);
    ClassDB::bind_method(D_METHOD("get_model_matrix"), &ShadowMesh::get_model_matrix);
    ClassDB::bind_method(D_METHOD("get_dirty"), &ShadowMesh::get_dirty);
    ClassDB::bind_method(D_METHOD("set_dirty", "bool value"), &ShadowMesh::set_dirty);
    ClassDB::bind_method(D_METHOD("is_indexed"), &ShadowMesh::is_indexed);


    ClassDB::bind_method(D_METHOD("set_mesh_path", "path"), &ShadowMesh::set_mesh_path);
    ClassDB::bind_method(D_METHOD("get_mesh_path"),         &ShadowMesh::get_mesh_path);
    ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "mesh_path"), "set_mesh_path", "get_mesh_path");

}

ShadowMesh::ShadowMesh() 
{
}

void ShadowMesh::_notification(int p_what)
{
    switch (p_what) {
        case NOTIFICATION_TRANSFORM_CHANGED: {
            update_model_matrix();
            dirty_transform = true;
        } break;

        case NOTIFICATION_READY: {
            _ready();
        } break;

        case NOTIFICATION_EXIT_TREE: {
            _exit_tree();
        } break;
    }
}

void ShadowMesh::_ready() 
{
    RenderingServer *rs = RenderingServer::get_singleton();
    rd = rs->get_rendering_device();

    if (model_matrix.size() != 64)
    {
        model_matrix.resize(64);
    }

    set_notify_transform(true);

    if (mesh_path != NodePath())
    {
        Node *n = get_node_or_null(mesh_path);
        if (n && n->is_class("MeshInstance3D")) {
            MeshInstance3D *mesh_instance = Object::cast_to<MeshInstance3D>(n);
            if (mesh_instance) {
                generate_from_mesh(mesh_instance);
                set_global_transform(mesh_instance->get_global_transform());
                set_dirty(true);
            }
        }
    }

    add_to_group("shadow_meshes");
}

void ShadowMesh::generate_from_mesh(MeshInstance3D *mesh_instance)
{
    Ref<RDVertexAttribute> vertex_attribute;
    vertex_attribute.instantiate();
    vertex_attribute->set_offset(0);
    vertex_attribute->set_stride(12);
    vertex_attribute->set_location(0);
    vertex_attribute->set_format(RenderingDevice::DATA_FORMAT_R32G32B32_SFLOAT);

    TypedArray<Ref<RDVertexAttribute>> attributes;
    attributes.push_back(vertex_attribute);

    int64_t vertex_format = rd->vertex_format_create(attributes);

    Ref<Mesh> mesh = mesh_instance->get_mesh();
    Array mesh_arrays = mesh->surface_get_arrays(0);

    PackedVector3Array vertex_array = mesh_arrays[Mesh::ARRAY_VERTEX];

    vertex_buffer = rd->vertex_buffer_create(vertex_array.size() * 12, vertex_array.to_byte_array());

    TypedArray<RID> vertex_buffer_array;
    vertex_buffer_array.push_back(vertex_buffer);
    vertex_array_rid = rd->vertex_array_create(vertex_array.size(), vertex_format, vertex_buffer_array);

    PackedInt32Array index_array = mesh_arrays[Mesh::ARRAY_INDEX];
    indexed = !index_array.is_empty();

    if (indexed)
    {
        index_buffer = rd->index_buffer_create(index_array.size(), RenderingDevice::INDEX_BUFFER_FORMAT_UINT32, index_array.to_byte_array());
        index_array_rid = rd->index_array_create(index_buffer, 0, index_array.size());
    }
}

void godot::ShadowMesh::update_from_mesh(MeshInstance3D *mesh_instance)
{
    Ref<Mesh> mesh = mesh_instance->get_mesh();
    Array mesh_arrays = mesh->surface_get_arrays(0);

    PackedVector3Array vertex_array = mesh_arrays[Mesh::ARRAY_VERTEX];
    PackedInt32Array index_array = mesh_arrays[Mesh::ARRAY_INDEX];

    rd->buffer_update(vertex_buffer, 0, vertex_array.size() * 12, vertex_array.to_byte_array());
    if (indexed)
    {
        rd->buffer_update(index_buffer, 0, index_array.size() * 4, index_array.to_byte_array());
    }
}

void ShadowMesh::update_model_matrix()
{
    const Basis &b = get_global_basis();

    const Vector3 c0 = b.get_column(0);
    const Vector3 c1 = b.get_column(1);
    const Vector3 c2 = b.get_column(2);
    const Vector3 o  = get_global_transform().get_origin();

    float m[16] = {
        (float)c0.x, (float)c0.y, (float)c0.z, 0.0f,
        (float)c1.x, (float)c1.y, (float)c1.z, 0.0f,
        (float)c2.x, (float)c2.y, (float)c2.z, 0.0f,
        (float)o.x,  (float)o.y,  (float)o.z,  1.0f
    };
    
    std::memcpy(model_matrix.ptrw(), m, sizeof(m));
}


void ShadowMesh::set_mesh_path(const NodePath &p_path) {
    mesh_path = p_path;
}


void ShadowMesh::_exit_tree() {
    if (rd) {
        if (vertex_array_rid.is_valid())
            if(vertex_buffer.is_valid()) rd->free_rid(vertex_buffer);
            if(vertex_array_rid.is_valid()) rd->free_rid(vertex_array_rid);
        if (index_array_rid.is_valid())
            if(index_buffer.is_valid()) rd->free_rid(index_buffer);
            if(index_array_rid.is_valid()) rd->free_rid(index_array_rid);
    }
}