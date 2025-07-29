#ifndef SHADOWHELPER_H
#define SHADOWHELPER_H

#include <godot_cpp/classes/ref_counted.hpp>


namespace godot {


class ShadowHelper : public RefCounted {
    GDCLASS(ShadowHelper, RefCounted)


public:
    ShadowHelper();

protected:
    static void _bind_methods();

private:

};

}

#endif