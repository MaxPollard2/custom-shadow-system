#ifndef SHADOWMESH_H
#define SHADOWMESH_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>

namespace godot {


class ShadowMesh : public Node3D {
    GDCLASS(ShadowMesh, Node3D)

private:
    RenderingDevice *rd;

    RID vertex_buffer;
    RID vertex_array_rid;

    RID index_buffer;
    RID index_array_rid;

    Transform3D last_global_transorm;

    bool visible = true;
    bool dirty_transform = false;
    bool indexed = false;

    Vector<RID> rids;

    PackedByteArray model_matrix;

    AABB aabb;

protected:
    static void _bind_methods();

public:
    ShadowMesh();

    void _notification(int p_what);

    void _ready() override;

    void generate_from_mesh(MeshInstance3D *mesh_instance);

    void update_from_mesh(MeshInstance3D *mesh_instance);

    void update_model_matrix();

    void _exit_tree();

    RID get_vertex_array_rid() const { return vertex_array_rid; }
    RID get_index_array_rid()  const { return index_array_rid; }
    bool has_index_array() const { return indexed; }
    bool get_dirty() const { return dirty_transform; }
    void set_dirty(bool value) { dirty_transform = value; }


    PackedByteArray get_model_matrix() const { return model_matrix; }
    inline const uint8_t* get_model_matrix_ptr() const { return model_matrix.ptr(); }

    NodePath get_mesh_path() const { return mesh_path; }
    void set_mesh_path(const NodePath &p_path);

    bool is_indexed() const { return indexed; }

    void set_visible(bool v) { visible = v; }
    bool is_visible() const { return visible; }

    void set_aabb(AABB _aabb) { aabb = _aabb; }
    AABB get_aabb() const { return aabb; }

protected:

private:
    NodePath mesh_path;

    

};

}

#endif
