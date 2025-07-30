#ifndef SHADOWHELPER_H
#define SHADOWHELPER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <ShadowMesh.h>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>


namespace godot {


class ShadowHelper : public RefCounted {
    GDCLASS(ShadowHelper, RefCounted)


public:
    PackedByteArray packed_matrices;
    RID matrices_buffer;
    RID matrices_set;

    PackedByteArray push_constants;

    RenderingDevice *rd = nullptr;
    RID pipeline;
    RID shader_rid;
    PackedColorArray clear_colors;

    ShadowHelper();

    void init(RenderingDevice *_rd, RID _pipeline, RID _shader_rid);

    void update_model_matrices(const Array &meshes);

    void run_cascade(RID fb, RID vp_set0, const Array &meshes, const AABB &cascade_world_aabb);

protected:
    static void _bind_methods();

private:

};

}

#endif