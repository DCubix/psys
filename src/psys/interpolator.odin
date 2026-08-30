package psys

import "core:math/linalg"
import "base:intrinsics"

LerpValue :: struct($T: typeid)
    where intrinsics.type_is_float(T) ||
        (intrinsics.type_is_array(T) && intrinsics.type_is_float(intrinsics.type_elem_type(T)))
{
    stop: f32,
    value: T,
}

interpolate :: proc(values: []LerpValue($T), t: f32) -> T {
    if len(values) == 0 {
        zero: T
        return zero
    }
    if len(values) < 2 do return values[0].value

    for i in 0..<len(values)-1 {
        v0 := values[i + 0]
        v1 := values[i + 1]
        if t >= v0.stop && t <= v1.stop {
            factor := (t - v0.stop) / (v1.stop - v0.stop)
            return linalg.lerp(v0.value, v1.value, factor)
        }
    }

    return values[len(values)-1].value
}
