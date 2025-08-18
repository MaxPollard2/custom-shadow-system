#include "ShadowHelper.h"

void godot::ShadowHelper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("init", "rd", "pipeline", "shader"), &ShadowHelper::init);
    ClassDB::bind_method(D_METHOD("update_model_matrices", "mesh_array"), &ShadowHelper::update_model_matrices);
    ClassDB::bind_method(D_METHOD("run_cascades_instanced", "framebuffer", "view_proj_set", "mesh_array", "instance count", "shadow_transform", "shadow_AABB"), &ShadowHelper::run_cascades_instanced);
}

godot::ShadowHelper::ShadowHelper()
{
}

void godot::ShadowHelper::init(RenderingDevice *_rd, RID _pipeline, RID _shader_rid)
{
    rd = _rd;
    pipeline = _pipeline;
    shader_rid = _shader_rid;

    clear_colors.append(Color(1.0, 0.0, 0.0, 1.0));
    clear_colors.append(Color(1.0, 0.0, 0.0, 1.0));
    clear_colors.append(Color(1.0, 0.0, 0.0, 1.0));
    clear_colors.append(Color(1.0, 0.0, 0.0, 1.0));
    clear_colors.append(Color(1.0, 0.0, 0.0, 1.0));
    UtilityFunctions::print("initing");

    packed_matrices.resize(64 * 1000);
    matrices_buffer = rd->storage_buffer_create(64 * 1000, packed_matrices);

    Ref<RDUniform> u; 
    u.instantiate();
    u->set_uniform_type(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER);
    u->set_binding(0);
    u->add_id(matrices_buffer);
    matrices_set = rd->uniform_set_create(Array::make(u), shader_rid, 1);

    push_constants.resize(16);
}

void godot::ShadowHelper::update_model_matrices(const Array &meshes)
{
    if (!rd || !pipeline.is_valid()) return;

    uint8_t *dst = packed_matrices.ptrw();

    for (int i = 0; i < meshes.size(); ++i) {
        ShadowMesh *m = Object::cast_to<ShadowMesh>(meshes[i]);
        
        if (m->get_dirty())
        {
            const uint8_t *src = m->get_model_matrix_ptr();

            memcpy(&dst[i * 64], src, 64);
            
            m->set_dirty(false);
        }
    }

    rd->buffer_update(matrices_buffer, 0, 64 * 1000, packed_matrices);
}


void godot::ShadowHelper::run_cascades_instanced(RID fb, RID vp_set, const Array &meshes, int instance_count, Transform3D shadow_transform, AABB shadow_aabb) {
    if (!rd || !pipeline.is_valid()) return;

    int64_t draw_list = rd->draw_list_begin(fb, RenderingDevice::DRAW_CLEAR_ALL, clear_colors);
    rd->draw_list_bind_render_pipeline(draw_list, pipeline);
    rd->draw_list_bind_uniform_set(draw_list, vp_set, 0);
    rd->draw_list_bind_uniform_set(draw_list, matrices_set, 1); // models buffer

    //int counter = 0;

    for (int i = 0; i < meshes.size(); i++) {
        ShadowMesh *m = Object::cast_to<ShadowMesh>(meshes[i]);
        if (!m || !m->is_visible()) continue;

        //AABB local = m->get_aabb();
        //AABB mesh_aabb_light = shadow_transform.xform(local);

        AABB local_aabb = m->get_aabb();
        Transform3D world_xf = m->get_global_transform();
        AABB world_aabb = world_xf.xform(local_aabb);
        AABB light_aabb = shadow_transform.xform(world_aabb);

        
        if (!shadow_aabb.intersects(light_aabb))
        {
            //counter++;
            continue;
        }

        push_constants.encode_u32(0, i);
        rd->draw_list_set_push_constant(draw_list, push_constants, 16);

        rd->draw_list_bind_vertex_array(draw_list, m->get_vertex_array_rid());

        const bool indexed = m->is_indexed();
        if (indexed) {
            rd->draw_list_bind_index_array(draw_list, m->get_index_array_rid());
        }

        rd->draw_list_draw(draw_list, indexed, instance_count);
    }

    //UtilityFunctions::print(counter, " ", (meshes.size() - counter));

    rd->draw_list_end();
}