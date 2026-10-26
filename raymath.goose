// rl: raymath for Goose. raymath.h is a header of inline C functions, so
// the raylib shared library does not export them; this is a port of
// raylib 6.2's raymath.h to Goose, function for function, with the same
// names and the same arithmetic (tools/raymath_check.goose compares the two).
//
// Differences from the C header:
//   * the *Equals functions return bool rather than int;
//   * Vector3ToFloatV and MatrixToFloatV return f32[3] and f32[16];
//   * out-parameters (Vector3OrthoNormalize, QuaternionToAxisAngle,
//     MatrixDecompose) are references: rl::MatrixDecompose(m, t, r, s).
//
// The Matrix struct's fields are declared in raylib's order, m0, m4, m8,
// m12, m1, ...: a positional Matrix { ... } fills it row by row, as a C
// initializer does.

namespace rl;

import math;

let EPSILON: f32 = 0.000001;

fn rm_fmin(a: f32, b: f32) -> f32 { if b < a { b } else { a } }
fn rm_fmax(a: f32, b: f32) -> f32 { if a < b { b } else { a } }
fn rm_fabs(x: f32) -> f32 { if x < 0.0 { -x } else { x } }
fn rm_close(a: f32, b: f32) -> bool {
    rm_fabs(a - b) <= EPSILON*rm_fmax(1.0, rm_fmax(rm_fabs(a), rm_fabs(b)))
}

// --- utils ------------------------------------------------------------------

// Clamp float value
fn Clamp(value: f32, min: f32, max: f32) -> f32 {
    var result = if value < min { min } else { value };
    if result > max { result = max; }
    return result;
}

// Calculate linear interpolation between two floats
fn Lerp(start: f32, end: f32, amount: f32) -> f32 { start + amount*(end - start) }

// Normalize input value within input range
fn Normalize(value: f32, start: f32, end: f32) -> f32 { (value - start)/(end - start) }

// Remap input value within input range to output range
fn Remap(value: f32, inputStart: f32, inputEnd: f32, outputStart: f32, outputEnd: f32) -> f32 {
    (value - inputStart)/(inputEnd - inputStart)*(outputEnd - outputStart) + outputStart
}

// Wrap input value from min to max
fn Wrap(value: f32, min: f32, max: f32) -> f32 {
    value - (max - min)*floor((value - min)/(max - min))
}

// Check whether two given floats are almost equal
fn FloatEquals(x: f32, y: f32) -> bool { rm_close(x, y) }

// --- Vector2 ----------------------------------------------------------------

// Vector with components value 0.0
fn Vector2Zero() -> Vector2 { Vector2 { 0.0, 0.0 } }

// Vector with components value 1.0
fn Vector2One() -> Vector2 { Vector2 { 1.0, 1.0 } }

// Add two vectors (v1 + v2)
fn Vector2Add(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { v1.x + v2.x, v1.y + v2.y } }

// Add vector and float value
fn Vector2AddValue(v: Vector2, add: f32) -> Vector2 { Vector2 { v.x + add, v.y + add } }

// Subtract two vectors (v1 - v2)
fn Vector2Subtract(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { v1.x - v2.x, v1.y - v2.y } }

// Subtract vector by float value
fn Vector2SubtractValue(v: Vector2, sub: f32) -> Vector2 { Vector2 { v.x - sub, v.y - sub } }

// Calculate vector length
fn Vector2Length(v: Vector2) -> f32 { sqrt((v.x*v.x) + (v.y*v.y)) }

// Calculate vector square length
fn Vector2LengthSqr(v: Vector2) -> f32 { (v.x*v.x) + (v.y*v.y) }

// Calculate two vectors dot product
fn Vector2DotProduct(v1: Vector2, v2: Vector2) -> f32 { v1.x*v2.x + v1.y*v2.y }

// Calculate two vectors cross product
fn Vector2CrossProduct(v1: Vector2, v2: Vector2) -> f32 { v1.x*v2.y - v1.y*v2.x }

// Calculate distance between two vectors
fn Vector2Distance(v1: Vector2, v2: Vector2) -> f32 {
    sqrt((v1.x - v2.x)*(v1.x - v2.x) + (v1.y - v2.y)*(v1.y - v2.y))
}

// Calculate square distance between two vectors
fn Vector2DistanceSqr(v1: Vector2, v2: Vector2) -> f32 {
    (v1.x - v2.x)*(v1.x - v2.x) + (v1.y - v2.y)*(v1.y - v2.y)
}

// Calculate the signed angle from v1 to v2, relative to the origin (0, 0)
// NOTE: Coordinate system convention: positive X right, positive Y down,
// positive angles appear clockwise, and negative angles appear counterclockwise
fn Vector2Angle(v1: Vector2, v2: Vector2) -> f32 {
    let dot = v1.x*v2.x + v1.y*v2.y;
    let det = v1.x*v2.y - v1.y*v2.x;
    return atan2(det, dot);
}

// Calculate angle defined by a two vectors line
// NOTE: Parameters need to be normalized
fn Vector2LineAngle(start: Vector2, end: Vector2) -> f32 {
    -atan2(end.y - start.y, end.x - start.x)
}

// Scale vector (multiply by value)
fn Vector2Scale(v: Vector2, scale: f32) -> Vector2 { Vector2 { v.x*scale, v.y*scale } }

// Multiply vector by vector
fn Vector2Multiply(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { v1.x*v2.x, v1.y*v2.y } }

// Negate vector
fn Vector2Negate(v: Vector2) -> Vector2 { Vector2 { -v.x, -v.y } }

// Divide vector by vector
fn Vector2Divide(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { v1.x/v2.x, v1.y/v2.y } }

// Normalize provided vector
fn Vector2Normalize(v: Vector2) -> Vector2 {
    var result = Vector2 { 0.0, 0.0 };
    let length = sqrt((v.x*v.x) + (v.y*v.y));
    if length > 0.0 {
        let ilength = 1.0/length;
        result.x = v.x*ilength;
        result.y = v.y*ilength;
    }
    return result;
}

// Transforms a Vector2 by a given Matrix
fn Vector2Transform(v: Vector2, mat: Matrix) -> Vector2 {
    let x = v.x;
    let y = v.y;
    let z: f32 = 0.0;
    return Vector2 { mat.m0*x + mat.m4*y + mat.m8*z + mat.m12, mat.m1*x + mat.m5*y + mat.m9*z + mat.m13 };
}

// Calculate linear interpolation between two vectors
fn Vector2Lerp(v1: Vector2, v2: Vector2, amount: f32) -> Vector2 {
    Vector2 { v1.x + amount*(v2.x - v1.x), v1.y + amount*(v2.y - v1.y) }
}

// Calculate reflected vector to normal
fn Vector2Reflect(v: Vector2, normal: Vector2) -> Vector2 {
    let dotProduct = v.x*normal.x + v.y*normal.y;
    return Vector2 { v.x - (2.0*normal.x)*dotProduct, v.y - (2.0*normal.y)*dotProduct };
}

// Get min value for each pair of components
fn Vector2Min(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { rm_fmin(v1.x, v2.x), rm_fmin(v1.y, v2.y) } }

// Get max value for each pair of components
fn Vector2Max(v1: Vector2, v2: Vector2) -> Vector2 { Vector2 { rm_fmax(v1.x, v2.x), rm_fmax(v1.y, v2.y) } }

// Rotate vector by angle
fn Vector2Rotate(v: Vector2, angle: f32) -> Vector2 {
    let cosres = cos(angle);
    let sinres = sin(angle);
    return Vector2 { v.x*cosres - v.y*sinres, v.x*sinres + v.y*cosres };
}

// Move Vector towards target
fn Vector2MoveTowards(v: Vector2, target: Vector2, maxDistance: f32) -> Vector2 {
    let dx = target.x - v.x;
    let dy = target.y - v.y;
    let value = (dx*dx) + (dy*dy);
    if value == 0.0 || (maxDistance >= 0.0 && value <= maxDistance*maxDistance) { return target; }
    let dist = sqrt(value);
    return Vector2 { v.x + dx/dist*maxDistance, v.y + dy/dist*maxDistance };
}

// Invert the given vector
fn Vector2Invert(v: Vector2) -> Vector2 { Vector2 { 1.0/v.x, 1.0/v.y } }

// Clamp the components of the vector between min and max values specified by the given vectors
fn Vector2Clamp(v: Vector2, min: Vector2, max: Vector2) -> Vector2 {
    Vector2 { rm_fmin(max.x, rm_fmax(min.x, v.x)), rm_fmin(max.y, rm_fmax(min.y, v.y)) }
}

// Clamp the magnitude of the vector between two min and max values
fn Vector2ClampValue(v: Vector2, min: f32, max: f32) -> Vector2 {
    var result = v;
    var length = (v.x*v.x) + (v.y*v.y);
    if length > 0.0 {
        length = sqrt(length);
        var scale: f32 = 1.0;
        if length < min { scale = min/length; }
        else if length > max { scale = max/length; }
        result.x = v.x*scale;
        result.y = v.y*scale;
    }
    return result;
}

// Check whether two given vectors are almost equal
fn Vector2Equals(p: Vector2, q: Vector2) -> bool { rm_close(p.x, q.x) && rm_close(p.y, q.y) }

// Compute the direction of a refracted ray
// v: normalized direction of the incoming ray
// n: normalized normal vector of the interface of two optical media
// r: ratio of the refractive index of the medium from where the ray comes
//    to the refractive index of the medium on the other side of the surface
fn Vector2Refract(v: Vector2, n: Vector2, r: f32) -> Vector2 {
    let dot = v.x*n.x + v.y*n.y;
    var d = 1.0 - r*r*(1.0 - dot*dot);
    if d >= 0.0 {
        d = sqrt(d);
        return Vector2 { r*v.x - (r*dot + d)*n.x, r*v.y - (r*dot + d)*n.y };
    }
    return Vector2 { 0.0, 0.0 };
}

// --- Vector3 ----------------------------------------------------------------

// Vector with components value 0.0
fn Vector3Zero() -> Vector3 { Vector3 { 0.0, 0.0, 0.0 } }

// Vector with components value 1.0
fn Vector3One() -> Vector3 { Vector3 { 1.0, 1.0, 1.0 } }

// Add two vectors
fn Vector3Add(v1: Vector3, v2: Vector3) -> Vector3 { Vector3 { v1.x + v2.x, v1.y + v2.y, v1.z + v2.z } }

// Add vector and float value
fn Vector3AddValue(v: Vector3, add: f32) -> Vector3 { Vector3 { v.x + add, v.y + add, v.z + add } }

// Subtract two vectors
fn Vector3Subtract(v1: Vector3, v2: Vector3) -> Vector3 { Vector3 { v1.x - v2.x, v1.y - v2.y, v1.z - v2.z } }

// Subtract vector by float value
fn Vector3SubtractValue(v: Vector3, sub: f32) -> Vector3 { Vector3 { v.x - sub, v.y - sub, v.z - sub } }

// Multiply vector by scalar
fn Vector3Scale(v: Vector3, scalar: f32) -> Vector3 { Vector3 { v.x*scalar, v.y*scalar, v.z*scalar } }

// Multiply vector by vector
fn Vector3Multiply(v1: Vector3, v2: Vector3) -> Vector3 { Vector3 { v1.x*v2.x, v1.y*v2.y, v1.z*v2.z } }

// Calculate two vectors cross product
fn Vector3CrossProduct(v1: Vector3, v2: Vector3) -> Vector3 {
    Vector3 { v1.y*v2.z - v1.z*v2.y, v1.z*v2.x - v1.x*v2.z, v1.x*v2.y - v1.y*v2.x }
}

// Calculate one vector perpendicular vector
fn Vector3Perpendicular(v: Vector3) -> Vector3 {
    var min = rm_fabs(v.x);
    var cardinalAxis = Vector3 { 1.0, 0.0, 0.0 };
    if rm_fabs(v.y) < min {
        min = rm_fabs(v.y);
        cardinalAxis = Vector3 { 0.0, 1.0, 0.0 };
    }
    if rm_fabs(v.z) < min {
        cardinalAxis = Vector3 { 0.0, 0.0, 1.0 };
    }
    // Cross product between vectors
    return Vector3 {
        v.y*cardinalAxis.z - v.z*cardinalAxis.y,
        v.z*cardinalAxis.x - v.x*cardinalAxis.z,
        v.x*cardinalAxis.y - v.y*cardinalAxis.x
    };
}

// Calculate vector length
fn Vector3Length(v: Vector3) -> f32 { sqrt(v.x*v.x + v.y*v.y + v.z*v.z) }

// Calculate vector square length
fn Vector3LengthSqr(v: Vector3) -> f32 { v.x*v.x + v.y*v.y + v.z*v.z }

// Calculate two vectors dot product
fn Vector3DotProduct(v1: Vector3, v2: Vector3) -> f32 { v1.x*v2.x + v1.y*v2.y + v1.z*v2.z }

// Calculate distance between two vectors
fn Vector3Distance(v1: Vector3, v2: Vector3) -> f32 {
    let dx = v2.x - v1.x;
    let dy = v2.y - v1.y;
    let dz = v2.z - v1.z;
    return sqrt(dx*dx + dy*dy + dz*dz);
}

// Calculate square distance between two vectors
fn Vector3DistanceSqr(v1: Vector3, v2: Vector3) -> f32 {
    let dx = v2.x - v1.x;
    let dy = v2.y - v1.y;
    let dz = v2.z - v1.z;
    return dx*dx + dy*dy + dz*dz;
}

// Calculate angle between two vectors
fn Vector3Angle(v1: Vector3, v2: Vector3) -> f32 {
    let cross = Vector3 { v1.y*v2.z - v1.z*v2.y, v1.z*v2.x - v1.x*v2.z, v1.x*v2.y - v1.y*v2.x };
    let len = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z);
    let dot = v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
    return atan2(len, dot);
}

// Negate provided vector (invert direction)
fn Vector3Negate(v: Vector3) -> Vector3 { Vector3 { -v.x, -v.y, -v.z } }

// Divide vector by vector
fn Vector3Divide(v1: Vector3, v2: Vector3) -> Vector3 { Vector3 { v1.x/v2.x, v1.y/v2.y, v1.z/v2.z } }

// Normalize provided vector
fn Vector3Normalize(v: Vector3) -> Vector3 {
    var result = v;
    let length = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if length != 0.0 {
        let ilength = 1.0/length;
        result.x *= ilength;
        result.y *= ilength;
        result.z *= ilength;
    }
    return result;
}

// Calculate the projection of the vector v1 on to v2
fn Vector3Project(v1: Vector3, v2: Vector3) -> Vector3 {
    let v1dv2 = v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
    let v2dv2 = v2.x*v2.x + v2.y*v2.y + v2.z*v2.z;
    let mag = v1dv2/v2dv2;
    return Vector3 { v2.x*mag, v2.y*mag, v2.z*mag };
}

// Calculate the rejection of the vector v1 on to v2
fn Vector3Reject(v1: Vector3, v2: Vector3) -> Vector3 {
    let v1dv2 = v1.x*v2.x + v1.y*v2.y + v1.z*v2.z;
    let v2dv2 = v2.x*v2.x + v2.y*v2.y + v2.z*v2.z;
    let mag = v1dv2/v2dv2;
    return Vector3 { v1.x - (v2.x*mag), v1.y - (v2.y*mag), v1.z - (v2.z*mag) };
}

// Orthonormalize provided vectors
// Makes vectors normalized and orthogonal to each other
// Gram-Schmidt function implementation
fn Vector3OrthoNormalize(v1: Vector3&, v2: Vector3&) {
    // Vector3Normalize(*v1);
    var v = v1;
    var length = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if length == 0.0 { length = 1.0; }
    var ilength = 1.0/length;
    v1.x *= ilength;
    v1.y *= ilength;
    v1.z *= ilength;

    // Vector3CrossProduct(*v1, *v2)
    var vn1 = Vector3 { v1.y*v2.z - v1.z*v2.y, v1.z*v2.x - v1.x*v2.z, v1.x*v2.y - v1.y*v2.x };

    // Vector3Normalize(vn1);
    v = vn1;
    length = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if length == 0.0 { length = 1.0; }
    ilength = 1.0/length;
    vn1.x *= ilength;
    vn1.y *= ilength;
    vn1.z *= ilength;

    // Vector3CrossProduct(vn1, *v1)
    let vn2 = Vector3 { vn1.y*v1.z - vn1.z*v1.y, vn1.z*v1.x - vn1.x*v1.z, vn1.x*v1.y - vn1.y*v1.x };
    v2 = vn2;
}

// Transforms a Vector3 by a given Matrix
fn Vector3Transform(v: Vector3, mat: Matrix) -> Vector3 {
    let x = v.x;
    let y = v.y;
    let z = v.z;
    return Vector3 {
        mat.m0*x + mat.m4*y + mat.m8*z + mat.m12,
        mat.m1*x + mat.m5*y + mat.m9*z + mat.m13,
        mat.m2*x + mat.m6*y + mat.m10*z + mat.m14
    };
}

// Transform a vector by quaternion rotation
fn Vector3RotateByQuaternion(v: Vector3, q: Quaternion) -> Vector3 {
    return Vector3 {
        v.x*(q.x*q.x + q.w*q.w - q.y*q.y - q.z*q.z) + v.y*(2.0*q.x*q.y - 2.0*q.w*q.z) + v.z*(2.0*q.x*q.z + 2.0*q.w*q.y),
        v.x*(2.0*q.w*q.z + 2.0*q.x*q.y) + v.y*(q.w*q.w - q.x*q.x + q.y*q.y - q.z*q.z) + v.z*(-2.0*q.w*q.x + 2.0*q.y*q.z),
        v.x*(-2.0*q.w*q.y + 2.0*q.x*q.z) + v.y*(2.0*q.w*q.x + 2.0*q.y*q.z) + v.z*(q.w*q.w - q.x*q.x - q.y*q.y + q.z*q.z)
    };
}

// Rotates a vector around an axis
fn Vector3RotateByAxisAngle(v: Vector3, axis_in: Vector3, angle_in: f32) -> Vector3 {
    // Using Euler-Rodrigues Formula
    var result = v;
    var axis = axis_in;
    var angle = angle_in;

    // Vector3Normalize(axis);
    var length = sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z);
    if length == 0.0 { length = 1.0; }
    let ilength = 1.0/length;
    axis.x *= ilength;
    axis.y *= ilength;
    axis.z *= ilength;

    angle /= 2.0;
    var a = sin(angle);
    let b = axis.x*a;
    let c = axis.y*a;
    let d = axis.z*a;
    a = cos(angle);
    let w = Vector3 { b, c, d };

    // Vector3CrossProduct(w, v)
    var wv = Vector3 { w.y*v.z - w.z*v.y, w.z*v.x - w.x*v.z, w.x*v.y - w.y*v.x };

    // Vector3CrossProduct(w, wv)
    var wwv = Vector3 { w.y*wv.z - w.z*wv.y, w.z*wv.x - w.x*wv.z, w.x*wv.y - w.y*wv.x };

    // Vector3Scale(wv, 2*a)
    a *= 2.0;
    wv.x *= a;
    wv.y *= a;
    wv.z *= a;

    // Vector3Scale(wwv, 2)
    wwv.x *= 2.0;
    wwv.y *= 2.0;
    wwv.z *= 2.0;

    result.x += wv.x;
    result.y += wv.y;
    result.z += wv.z;

    result.x += wwv.x;
    result.y += wwv.y;
    result.z += wwv.z;

    return result;
}

// Move Vector towards target
fn Vector3MoveTowards(v: Vector3, target: Vector3, maxDistance: f32) -> Vector3 {
    let dx = target.x - v.x;
    let dy = target.y - v.y;
    let dz = target.z - v.z;
    let value = (dx*dx) + (dy*dy) + (dz*dz);
    if value == 0.0 || (maxDistance >= 0.0 && value <= maxDistance*maxDistance) { return target; }
    let dist = sqrt(value);
    return Vector3 { v.x + dx/dist*maxDistance, v.y + dy/dist*maxDistance, v.z + dz/dist*maxDistance };
}

// Calculate linear interpolation between two vectors
fn Vector3Lerp(v1: Vector3, v2: Vector3, amount: f32) -> Vector3 {
    Vector3 { v1.x + amount*(v2.x - v1.x), v1.y + amount*(v2.y - v1.y), v1.z + amount*(v2.z - v1.z) }
}

// Calculate cubic hermite interpolation between two vectors and their tangents
// as described in the GLTF 2.0 specification
fn Vector3CubicHermite(v1: Vector3, tangent1: Vector3, v2: Vector3, tangent2: Vector3, amount: f32) -> Vector3 {
    let amountPow2 = amount*amount;
    let amountPow3 = amount*amount*amount;
    let h00 = 2.0*amountPow3 - 3.0*amountPow2 + 1.0;
    let h10 = amountPow3 - 2.0*amountPow2 + amount;
    let h01 = -2.0*amountPow3 + 3.0*amountPow2;
    let h11 = amountPow3 - amountPow2;
    return Vector3 {
        h00*v1.x + h10*tangent1.x + h01*v2.x + h11*tangent2.x,
        h00*v1.y + h10*tangent1.y + h01*v2.y + h11*tangent2.y,
        h00*v1.z + h10*tangent1.z + h01*v2.z + h11*tangent2.z
    };
}

// Calculate reflected vector to normal
fn Vector3Reflect(v: Vector3, normal: Vector3) -> Vector3 {
    // I is the original vector
    // N is the normal of the incident plane
    // R = I - (2*N*(DotProduct[I, N]))
    let dotProduct = v.x*normal.x + v.y*normal.y + v.z*normal.z;
    return Vector3 {
        v.x - (2.0*normal.x)*dotProduct,
        v.y - (2.0*normal.y)*dotProduct,
        v.z - (2.0*normal.z)*dotProduct
    };
}

// Get min value for each pair of components
fn Vector3Min(v1: Vector3, v2: Vector3) -> Vector3 {
    Vector3 { rm_fmin(v1.x, v2.x), rm_fmin(v1.y, v2.y), rm_fmin(v1.z, v2.z) }
}

// Get max value for each pair of components
fn Vector3Max(v1: Vector3, v2: Vector3) -> Vector3 {
    Vector3 { rm_fmax(v1.x, v2.x), rm_fmax(v1.y, v2.y), rm_fmax(v1.z, v2.z) }
}

// Compute barycenter coordinates (u, v, w) for point p with respect to triangle (a, b, c)
// NOTE: Assumes P is on the plane of the triangle
fn Vector3Barycenter(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3 {
    let v0 = Vector3 { b.x - a.x, b.y - a.y, b.z - a.z };
    let v1 = Vector3 { c.x - a.x, c.y - a.y, c.z - a.z };
    let v2 = Vector3 { p.x - a.x, p.y - a.y, p.z - a.z };
    let d00 = v0.x*v0.x + v0.y*v0.y + v0.z*v0.z;
    let d01 = v0.x*v1.x + v0.y*v1.y + v0.z*v1.z;
    let d11 = v1.x*v1.x + v1.y*v1.y + v1.z*v1.z;
    let d20 = v2.x*v0.x + v2.y*v0.y + v2.z*v0.z;
    let d21 = v2.x*v1.x + v2.y*v1.y + v2.z*v1.z;

    let denom = d00*d11 - d01*d01;

    var result = Vector3 { 0.0, 0.0, 0.0 };
    result.y = (d11*d20 - d01*d21)/denom;
    result.z = (d00*d21 - d01*d20)/denom;
    result.x = 1.0 - (result.z + result.y);
    return result;
}

// Projects a Vector3 from screen space into object space
fn Vector3Unproject(source: Vector3, projection: Matrix, view: Matrix) -> Vector3 {
    // Calculate unprojected matrix (multiply view matrix by projection matrix) and invert it.
    // raymath.h builds both with positional initializers, which fill m0, m4,
    // m8, ...: the product and the inverse come out transposed, and so here.
    let matViewProj = MatrixTranspose(MatrixMultiply(view, projection));
    let matViewProjInv = MatrixTranspose(MatrixInvert(matViewProj));

    // Create quaternion from source point
    let quat = Quaternion { source.x, source.y, source.z, 1.0 };

    // Multiply quat point by unprojected matrix
    let qtransformed = QuaternionTransform(quat, matViewProjInv);

    // Normalized world points in vectors
    return Vector3 { qtransformed.x/qtransformed.w, qtransformed.y/qtransformed.w, qtransformed.z/qtransformed.w };
}

// Get Vector3 as float array
fn Vector3ToFloatV(v: Vector3) -> f32[3] { [v.x, v.y, v.z] }

// Invert the given vector
fn Vector3Invert(v: Vector3) -> Vector3 { Vector3 { 1.0/v.x, 1.0/v.y, 1.0/v.z } }

// Clamp the components of the vector between min and max values specified by the given vectors
fn Vector3Clamp(v: Vector3, min: Vector3, max: Vector3) -> Vector3 {
    Vector3 {
        rm_fmin(max.x, rm_fmax(min.x, v.x)),
        rm_fmin(max.y, rm_fmax(min.y, v.y)),
        rm_fmin(max.z, rm_fmax(min.z, v.z))
    }
}

// Clamp the magnitude of the vector between two values
fn Vector3ClampValue(v: Vector3, min: f32, max: f32) -> Vector3 {
    var result = v;
    var length = (v.x*v.x) + (v.y*v.y) + (v.z*v.z);
    if length > 0.0 {
        length = sqrt(length);
        var scale: f32 = 1.0;
        if length < min { scale = min/length; }
        else if length > max { scale = max/length; }
        result.x = v.x*scale;
        result.y = v.y*scale;
        result.z = v.z*scale;
    }
    return result;
}

// Check whether two given vectors are almost equal
fn Vector3Equals(p: Vector3, q: Vector3) -> bool {
    rm_close(p.x, q.x) && rm_close(p.y, q.y) && rm_close(p.z, q.z)
}

// Compute the direction of a refracted ray
// v: normalized direction of the incoming ray
// n: normalized normal vector of the interface of two optical media
// r: ratio of the refractive index of the medium from where the ray comes
//    to the refractive index of the medium on the other side of the surface
fn Vector3Refract(v: Vector3, n: Vector3, r: f32) -> Vector3 {
    let dot = v.x*n.x + v.y*n.y + v.z*n.z;
    var d = 1.0 - r*r*(1.0 - dot*dot);
    if d >= 0.0 {
        d = sqrt(d);
        return Vector3 { r*v.x - (r*dot + d)*n.x, r*v.y - (r*dot + d)*n.y, r*v.z - (r*dot + d)*n.z };
    }
    return Vector3 { 0.0, 0.0, 0.0 };
}

// --- Vector4 ----------------------------------------------------------------

fn Vector4Zero() -> Vector4 { Vector4 { 0.0, 0.0, 0.0, 0.0 } }

fn Vector4One() -> Vector4 { Vector4 { 1.0, 1.0, 1.0, 1.0 } }

fn Vector4Add(v1: Vector4, v2: Vector4) -> Vector4 {
    Vector4 { v1.x + v2.x, v1.y + v2.y, v1.z + v2.z, v1.w + v2.w }
}

fn Vector4AddValue(v: Vector4, add: f32) -> Vector4 { Vector4 { v.x + add, v.y + add, v.z + add, v.w + add } }

fn Vector4Subtract(v1: Vector4, v2: Vector4) -> Vector4 {
    Vector4 { v1.x - v2.x, v1.y - v2.y, v1.z - v2.z, v1.w - v2.w }
}

fn Vector4SubtractValue(v: Vector4, add: f32) -> Vector4 { Vector4 { v.x - add, v.y - add, v.z - add, v.w - add } }

fn Vector4Length(v: Vector4) -> f32 { sqrt((v.x*v.x) + (v.y*v.y) + (v.z*v.z) + (v.w*v.w)) }

fn Vector4LengthSqr(v: Vector4) -> f32 { (v.x*v.x) + (v.y*v.y) + (v.z*v.z) + (v.w*v.w) }

fn Vector4DotProduct(v1: Vector4, v2: Vector4) -> f32 { v1.x*v2.x + v1.y*v2.y + v1.z*v2.z + v1.w*v2.w }

// Calculate distance between two vectors
fn Vector4Distance(v1: Vector4, v2: Vector4) -> f32 {
    sqrt((v1.x - v2.x)*(v1.x - v2.x) + (v1.y - v2.y)*(v1.y - v2.y) +
               (v1.z - v2.z)*(v1.z - v2.z) + (v1.w - v2.w)*(v1.w - v2.w))
}

// Calculate square distance between two vectors
fn Vector4DistanceSqr(v1: Vector4, v2: Vector4) -> f32 {
    (v1.x - v2.x)*(v1.x - v2.x) + (v1.y - v2.y)*(v1.y - v2.y) +
    (v1.z - v2.z)*(v1.z - v2.z) + (v1.w - v2.w)*(v1.w - v2.w)
}

fn Vector4Scale(v: Vector4, scale: f32) -> Vector4 { Vector4 { v.x*scale, v.y*scale, v.z*scale, v.w*scale } }

// Multiply vector by vector
fn Vector4Multiply(v1: Vector4, v2: Vector4) -> Vector4 { Vector4 { v1.x*v2.x, v1.y*v2.y, v1.z*v2.z, v1.w*v2.w } }

// Negate vector
fn Vector4Negate(v: Vector4) -> Vector4 { Vector4 { -v.x, -v.y, -v.z, -v.w } }

// Divide vector by vector
fn Vector4Divide(v1: Vector4, v2: Vector4) -> Vector4 { Vector4 { v1.x/v2.x, v1.y/v2.y, v1.z/v2.z, v1.w/v2.w } }

// Normalize provided vector
fn Vector4Normalize(v: Vector4) -> Vector4 {
    var result = Vector4 { 0.0, 0.0, 0.0, 0.0 };
    let length = sqrt((v.x*v.x) + (v.y*v.y) + (v.z*v.z) + (v.w*v.w));
    if length > 0.0 {
        let ilength = 1.0/length;
        result.x = v.x*ilength;
        result.y = v.y*ilength;
        result.z = v.z*ilength;
        result.w = v.w*ilength;
    }
    return result;
}

// Get min value for each pair of components
fn Vector4Min(v1: Vector4, v2: Vector4) -> Vector4 {
    Vector4 { rm_fmin(v1.x, v2.x), rm_fmin(v1.y, v2.y), rm_fmin(v1.z, v2.z), rm_fmin(v1.w, v2.w) }
}

// Get max value for each pair of components
fn Vector4Max(v1: Vector4, v2: Vector4) -> Vector4 {
    Vector4 { rm_fmax(v1.x, v2.x), rm_fmax(v1.y, v2.y), rm_fmax(v1.z, v2.z), rm_fmax(v1.w, v2.w) }
}

// Calculate linear interpolation between two vectors
fn Vector4Lerp(v1: Vector4, v2: Vector4, amount: f32) -> Vector4 {
    Vector4 {
        v1.x + amount*(v2.x - v1.x),
        v1.y + amount*(v2.y - v1.y),
        v1.z + amount*(v2.z - v1.z),
        v1.w + amount*(v2.w - v1.w)
    }
}

// Move Vector towards target
fn Vector4MoveTowards(v: Vector4, target: Vector4, maxDistance: f32) -> Vector4 {
    let dx = target.x - v.x;
    let dy = target.y - v.y;
    let dz = target.z - v.z;
    let dw = target.w - v.w;
    let value = (dx*dx) + (dy*dy) + (dz*dz) + (dw*dw);
    if value == 0.0 || (maxDistance >= 0.0 && value <= maxDistance*maxDistance) { return target; }
    let dist = sqrt(value);
    return Vector4 {
        v.x + dx/dist*maxDistance,
        v.y + dy/dist*maxDistance,
        v.z + dz/dist*maxDistance,
        v.w + dw/dist*maxDistance
    };
}

// Invert the given vector
fn Vector4Invert(v: Vector4) -> Vector4 { Vector4 { 1.0/v.x, 1.0/v.y, 1.0/v.z, 1.0/v.w } }

// Check whether two given vectors are almost equal
fn Vector4Equals(p: Vector4, q: Vector4) -> bool {
    rm_close(p.x, q.x) && rm_close(p.y, q.y) && rm_close(p.z, q.z) && rm_close(p.w, q.w)
}

// --- Matrix -----------------------------------------------------------------

// Compute matrix determinant
fn MatrixDeterminant(mat: Matrix) -> f32 {
    let m0 = mat.m0;   let m1 = mat.m1;   let m2 = mat.m2;   let m3 = mat.m3;
    let m4 = mat.m4;   let m5 = mat.m5;   let m6 = mat.m6;   let m7 = mat.m7;
    let m8 = mat.m8;   let m9 = mat.m9;   let m10 = mat.m10; let m11 = mat.m11;
    let m12 = mat.m12; let m13 = mat.m13; let m14 = mat.m14; let m15 = mat.m15;
    return (m0*((m5*(m10*m15 - m11*m14) - m9*(m6*m15 - m7*m14) + m13*(m6*m11 - m7*m10))) -
        m4*((m1*(m10*m15 - m11*m14) - m9*(m2*m15 - m3*m14) + m13*(m2*m11 - m3*m10))) +
        m8*((m1*(m6*m15 - m7*m14) - m5*(m2*m15 - m3*m14) + m13*(m2*m7 - m3*m6))) -
        m12*((m1*(m6*m11 - m7*m10) - m5*(m2*m11 - m3*m10) + m9*(m2*m7 - m3*m6))));
}

// Get the trace of the matrix (sum of the values along the diagonal)
fn MatrixTrace(mat: Matrix) -> f32 { mat.m0 + mat.m5 + mat.m10 + mat.m15 }

// Transposes provided matrix
fn MatrixTranspose(mat: Matrix) -> Matrix {
    var result = Matrix { .. };
    result.m0 = mat.m0;
    result.m1 = mat.m4;
    result.m2 = mat.m8;
    result.m3 = mat.m12;
    result.m4 = mat.m1;
    result.m5 = mat.m5;
    result.m6 = mat.m9;
    result.m7 = mat.m13;
    result.m8 = mat.m2;
    result.m9 = mat.m6;
    result.m10 = mat.m10;
    result.m11 = mat.m14;
    result.m12 = mat.m3;
    result.m13 = mat.m7;
    result.m14 = mat.m11;
    result.m15 = mat.m15;
    return result;
}

// Invert provided matrix
fn MatrixInvert(mat: Matrix) -> Matrix {
    let a00 = mat.m0;  let a01 = mat.m1;  let a02 = mat.m2;  let a03 = mat.m3;
    let a10 = mat.m4;  let a11 = mat.m5;  let a12 = mat.m6;  let a13 = mat.m7;
    let a20 = mat.m8;  let a21 = mat.m9;  let a22 = mat.m10; let a23 = mat.m11;
    let a30 = mat.m12; let a31 = mat.m13; let a32 = mat.m14; let a33 = mat.m15;

    let b00 = a00*a11 - a01*a10;
    let b01 = a00*a12 - a02*a10;
    let b02 = a00*a13 - a03*a10;
    let b03 = a01*a12 - a02*a11;
    let b04 = a01*a13 - a03*a11;
    let b05 = a02*a13 - a03*a12;
    let b06 = a20*a31 - a21*a30;
    let b07 = a20*a32 - a22*a30;
    let b08 = a20*a33 - a23*a30;
    let b09 = a21*a32 - a22*a31;
    let b10 = a21*a33 - a23*a31;
    let b11 = a22*a33 - a23*a32;

    // Calculate the invert determinant (inlined to avoid double-caching)
    let invDet = 1.0/(b00*b11 - b01*b10 + b02*b09 + b03*b08 - b04*b07 + b05*b06);

    var result = Matrix { .. };
    result.m0 = (a11*b11 - a12*b10 + a13*b09)*invDet;
    result.m1 = (-a01*b11 + a02*b10 - a03*b09)*invDet;
    result.m2 = (a31*b05 - a32*b04 + a33*b03)*invDet;
    result.m3 = (-a21*b05 + a22*b04 - a23*b03)*invDet;
    result.m4 = (-a10*b11 + a12*b08 - a13*b07)*invDet;
    result.m5 = (a00*b11 - a02*b08 + a03*b07)*invDet;
    result.m6 = (-a30*b05 + a32*b02 - a33*b01)*invDet;
    result.m7 = (a20*b05 - a22*b02 + a23*b01)*invDet;
    result.m8 = (a10*b10 - a11*b08 + a13*b06)*invDet;
    result.m9 = (-a00*b10 + a01*b08 - a03*b06)*invDet;
    result.m10 = (a30*b04 - a31*b02 + a33*b00)*invDet;
    result.m11 = (-a20*b04 + a21*b02 - a23*b00)*invDet;
    result.m12 = (-a10*b09 + a11*b07 - a12*b06)*invDet;
    result.m13 = (a00*b09 - a01*b07 + a02*b06)*invDet;
    result.m14 = (-a30*b03 + a31*b01 - a32*b00)*invDet;
    result.m15 = (a20*b03 - a21*b01 + a22*b00)*invDet;
    return result;
}

// Get identity matrix
fn MatrixIdentity() -> Matrix {
    Matrix { 1.0, 0.0, 0.0, 0.0,
             0.0, 1.0, 0.0, 0.0,
             0.0, 0.0, 1.0, 0.0,
             0.0, 0.0, 0.0, 1.0 }
}

// Add two matrices
fn MatrixAdd(left: Matrix, right: Matrix) -> Matrix {
    var result = Matrix { .. };
    result.m0 = left.m0 + right.m0;
    result.m1 = left.m1 + right.m1;
    result.m2 = left.m2 + right.m2;
    result.m3 = left.m3 + right.m3;
    result.m4 = left.m4 + right.m4;
    result.m5 = left.m5 + right.m5;
    result.m6 = left.m6 + right.m6;
    result.m7 = left.m7 + right.m7;
    result.m8 = left.m8 + right.m8;
    result.m9 = left.m9 + right.m9;
    result.m10 = left.m10 + right.m10;
    result.m11 = left.m11 + right.m11;
    result.m12 = left.m12 + right.m12;
    result.m13 = left.m13 + right.m13;
    result.m14 = left.m14 + right.m14;
    result.m15 = left.m15 + right.m15;
    return result;
}

// Subtract two matrices (left - right)
fn MatrixSubtract(left: Matrix, right: Matrix) -> Matrix {
    var result = Matrix { .. };
    result.m0 = left.m0 - right.m0;
    result.m1 = left.m1 - right.m1;
    result.m2 = left.m2 - right.m2;
    result.m3 = left.m3 - right.m3;
    result.m4 = left.m4 - right.m4;
    result.m5 = left.m5 - right.m5;
    result.m6 = left.m6 - right.m6;
    result.m7 = left.m7 - right.m7;
    result.m8 = left.m8 - right.m8;
    result.m9 = left.m9 - right.m9;
    result.m10 = left.m10 - right.m10;
    result.m11 = left.m11 - right.m11;
    result.m12 = left.m12 - right.m12;
    result.m13 = left.m13 - right.m13;
    result.m14 = left.m14 - right.m14;
    result.m15 = left.m15 - right.m15;
    return result;
}

// Get two matrix multiplication
// NOTE: When multiplying matrices... the order matters!
fn MatrixMultiply(left: Matrix, right: Matrix) -> Matrix {
    var result = Matrix { .. };
    result.m0 = left.m0*right.m0 + left.m1*right.m4 + left.m2*right.m8 + left.m3*right.m12;
    result.m1 = left.m0*right.m1 + left.m1*right.m5 + left.m2*right.m9 + left.m3*right.m13;
    result.m2 = left.m0*right.m2 + left.m1*right.m6 + left.m2*right.m10 + left.m3*right.m14;
    result.m3 = left.m0*right.m3 + left.m1*right.m7 + left.m2*right.m11 + left.m3*right.m15;
    result.m4 = left.m4*right.m0 + left.m5*right.m4 + left.m6*right.m8 + left.m7*right.m12;
    result.m5 = left.m4*right.m1 + left.m5*right.m5 + left.m6*right.m9 + left.m7*right.m13;
    result.m6 = left.m4*right.m2 + left.m5*right.m6 + left.m6*right.m10 + left.m7*right.m14;
    result.m7 = left.m4*right.m3 + left.m5*right.m7 + left.m6*right.m11 + left.m7*right.m15;
    result.m8 = left.m8*right.m0 + left.m9*right.m4 + left.m10*right.m8 + left.m11*right.m12;
    result.m9 = left.m8*right.m1 + left.m9*right.m5 + left.m10*right.m9 + left.m11*right.m13;
    result.m10 = left.m8*right.m2 + left.m9*right.m6 + left.m10*right.m10 + left.m11*right.m14;
    result.m11 = left.m8*right.m3 + left.m9*right.m7 + left.m10*right.m11 + left.m11*right.m15;
    result.m12 = left.m12*right.m0 + left.m13*right.m4 + left.m14*right.m8 + left.m15*right.m12;
    result.m13 = left.m12*right.m1 + left.m13*right.m5 + left.m14*right.m9 + left.m15*right.m13;
    result.m14 = left.m12*right.m2 + left.m13*right.m6 + left.m14*right.m10 + left.m15*right.m14;
    result.m15 = left.m12*right.m3 + left.m13*right.m7 + left.m14*right.m11 + left.m15*right.m15;
    return result;
}

// Multiply every component of a matrix by a value
fn MatrixMultiplyValue(left: Matrix, value: f32) -> Matrix {
    Matrix {
        left.m0*value, left.m4*value, left.m8*value, left.m12*value,
        left.m1*value, left.m5*value, left.m9*value, left.m13*value,
        left.m2*value, left.m6*value, left.m10*value, left.m14*value,
        left.m3*value, left.m7*value, left.m11*value, left.m15*value
    }
}

// Get translation matrix
fn MatrixTranslate(x: f32, y: f32, z: f32) -> Matrix {
    Matrix { 1.0, 0.0, 0.0, x,
             0.0, 1.0, 0.0, y,
             0.0, 0.0, 1.0, z,
             0.0, 0.0, 0.0, 1.0 }
}

// Create rotation matrix from axis and angle
// NOTE: Angle should be provided in radians
fn MatrixRotate(axis: Vector3, angle: f32) -> Matrix {
    var x = axis.x;
    var y = axis.y;
    var z = axis.z;

    let lengthSquared = x*x + y*y + z*z;

    if lengthSquared != 1.0 && lengthSquared != 0.0 {
        let ilength = 1.0/sqrt(lengthSquared);
        x *= ilength;
        y *= ilength;
        z *= ilength;
    }

    let sinres = sin(angle);
    let cosres = cos(angle);
    let t = 1.0 - cosres;

    var result = Matrix { .. };
    result.m0 = x*x*t + cosres;
    result.m1 = y*x*t + z*sinres;
    result.m2 = z*x*t - y*sinres;
    result.m3 = 0.0;

    result.m4 = x*y*t - z*sinres;
    result.m5 = y*y*t + cosres;
    result.m6 = z*y*t + x*sinres;
    result.m7 = 0.0;

    result.m8 = x*z*t + y*sinres;
    result.m9 = y*z*t - x*sinres;
    result.m10 = z*z*t + cosres;
    result.m11 = 0.0;

    result.m12 = 0.0;
    result.m13 = 0.0;
    result.m14 = 0.0;
    result.m15 = 1.0;
    return result;
}

// Get x-rotation matrix
// NOTE: Angle must be provided in radians
fn MatrixRotateX(angle: f32) -> Matrix {
    var result = MatrixIdentity();
    let cosres = cos(angle);
    let sinres = sin(angle);
    result.m5 = cosres;
    result.m6 = sinres;
    result.m9 = -sinres;
    result.m10 = cosres;
    return result;
}

// Get y-rotation matrix
// NOTE: Angle must be provided in radians
fn MatrixRotateY(angle: f32) -> Matrix {
    var result = MatrixIdentity();
    let cosres = cos(angle);
    let sinres = sin(angle);
    result.m0 = cosres;
    result.m2 = -sinres;
    result.m8 = sinres;
    result.m10 = cosres;
    return result;
}

// Get z-rotation matrix
// NOTE: Angle must be provided in radians
fn MatrixRotateZ(angle: f32) -> Matrix {
    var result = MatrixIdentity();
    let cosres = cos(angle);
    let sinres = sin(angle);
    result.m0 = cosres;
    result.m1 = sinres;
    result.m4 = -sinres;
    result.m5 = cosres;
    return result;
}

// Get xyz-rotation matrix
// NOTE: Angle must be provided in radians
fn MatrixRotateXYZ(angle: Vector3) -> Matrix {
    var result = MatrixIdentity();

    let cosz = cos(-angle.z);
    let sinz = sin(-angle.z);
    let cosy = cos(-angle.y);
    let siny = sin(-angle.y);
    let cosx = cos(-angle.x);
    let sinx = sin(-angle.x);

    result.m0 = cosz*cosy;
    result.m1 = (cosz*siny*sinx) - (sinz*cosx);
    result.m2 = (cosz*siny*cosx) + (sinz*sinx);

    result.m4 = sinz*cosy;
    result.m5 = (sinz*siny*sinx) + (cosz*cosx);
    result.m6 = (sinz*siny*cosx) - (cosz*sinx);

    result.m8 = -siny;
    result.m9 = cosy*sinx;
    result.m10 = cosy*cosx;
    return result;
}

// Get zyx-rotation matrix
// NOTE: Angle must be provided in radians
fn MatrixRotateZYX(angle: Vector3) -> Matrix {
    let cz = cos(angle.z);
    let sz = sin(angle.z);
    let cy = cos(angle.y);
    let sy = sin(angle.y);
    let cx = cos(angle.x);
    let sx = sin(angle.x);

    var result = Matrix { .. };
    result.m0 = cz*cy;
    result.m4 = cz*sy*sx - cx*sz;
    result.m8 = sz*sx + cz*cx*sy;
    result.m12 = 0.0;

    result.m1 = cy*sz;
    result.m5 = cz*cx + sz*sy*sx;
    result.m9 = cx*sz*sy - cz*sx;
    result.m13 = 0.0;

    result.m2 = -sy;
    result.m6 = cy*sx;
    result.m10 = cy*cx;
    result.m14 = 0.0;

    result.m3 = 0.0;
    result.m7 = 0.0;
    result.m11 = 0.0;
    result.m15 = 1.0;
    return result;
}

// Get scaling matrix
fn MatrixScale(x: f32, y: f32, z: f32) -> Matrix {
    Matrix { x, 0.0, 0.0, 0.0,
             0.0, y, 0.0, 0.0,
             0.0, 0.0, z, 0.0,
             0.0, 0.0, 0.0, 1.0 }
}

// Get perspective projection matrix
fn MatrixFrustum(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) -> Matrix {
    let rl = (right - left) as f32;
    let tb = (top - bottom) as f32;
    let fn_ = (farPlane - nearPlane) as f32;

    var result = Matrix { .. };
    result.m0 = ((nearPlane as f32)*2.0)/rl;
    result.m5 = ((nearPlane as f32)*2.0)/tb;
    result.m8 = ((right as f32) + (left as f32))/rl;
    result.m9 = ((top as f32) + (bottom as f32))/tb;
    result.m10 = -((farPlane as f32) + (nearPlane as f32))/fn_;
    result.m11 = -1.0;
    result.m14 = -((farPlane as f32)*(nearPlane as f32)*2.0)/fn_;
    return result;
}

// Get perspective projection matrix
// NOTE: Fovy angle must be provided in radians
fn MatrixPerspective(fovY: f64, aspect: f64, nearPlane: f64, farPlane: f64) -> Matrix {
    let top = nearPlane*tan(fovY*0.5);
    let bottom = -top;
    let right = top*aspect;
    let left = -right;

    // MatrixFrustum(-right, right, -top, top, near, far);
    let rl = (right - left) as f32;
    let tb = (top - bottom) as f32;
    let fn_ = (farPlane - nearPlane) as f32;

    var result = Matrix { .. };
    result.m0 = ((nearPlane as f32)*2.0)/rl;
    result.m5 = ((nearPlane as f32)*2.0)/tb;
    result.m8 = ((right as f32) + (left as f32))/rl;
    result.m9 = ((top as f32) + (bottom as f32))/tb;
    result.m10 = -((farPlane as f32) + (nearPlane as f32))/fn_;
    result.m11 = -1.0;
    result.m14 = -((farPlane as f32)*(nearPlane as f32)*2.0)/fn_;
    return result;
}

// Get orthographic projection matrix
fn MatrixOrtho(left: f64, right: f64, bottom: f64, top: f64, nearPlane: f64, farPlane: f64) -> Matrix {
    let rl = (right - left) as f32;
    let tb = (top - bottom) as f32;
    let fn_ = (farPlane - nearPlane) as f32;

    var result = Matrix { .. };
    result.m0 = 2.0/rl;
    result.m5 = 2.0/tb;
    result.m10 = -2.0/fn_;
    result.m12 = -((left as f32) + (right as f32))/rl;
    result.m13 = -((top as f32) + (bottom as f32))/tb;
    result.m14 = -((farPlane as f32) + (nearPlane as f32))/fn_;
    result.m15 = 1.0;
    return result;
}

// Get camera look-at matrix (view matrix)
fn MatrixLookAt(eye: Vector3, target: Vector3, up: Vector3) -> Matrix {
    // Vector3Subtract(eye, target)
    var vz = Vector3 { eye.x - target.x, eye.y - target.y, eye.z - target.z };

    // Vector3Normalize(vz)
    var v = vz;
    var length = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if length == 0.0 { length = 1.0; }
    var ilength = 1.0/length;
    vz.x *= ilength;
    vz.y *= ilength;
    vz.z *= ilength;

    // Vector3CrossProduct(up, vz)
    var vx = Vector3 { up.y*vz.z - up.z*vz.y, up.z*vz.x - up.x*vz.z, up.x*vz.y - up.y*vz.x };

    // Vector3Normalize(x)
    v = vx;
    length = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if length == 0.0 { length = 1.0; }
    ilength = 1.0/length;
    vx.x *= ilength;
    vx.y *= ilength;
    vx.z *= ilength;

    // Vector3CrossProduct(vz, vx)
    let vy = Vector3 { vz.y*vx.z - vz.z*vx.y, vz.z*vx.x - vz.x*vx.z, vz.x*vx.y - vz.y*vx.x };

    var result = Matrix { .. };
    result.m0 = vx.x;
    result.m1 = vy.x;
    result.m2 = vz.x;
    result.m3 = 0.0;
    result.m4 = vx.y;
    result.m5 = vy.y;
    result.m6 = vz.y;
    result.m7 = 0.0;
    result.m8 = vx.z;
    result.m9 = vy.z;
    result.m10 = vz.z;
    result.m11 = 0.0;
    result.m12 = -(vx.x*eye.x + vx.y*eye.y + vx.z*eye.z);   // Vector3DotProduct(vx, eye)
    result.m13 = -(vy.x*eye.x + vy.y*eye.y + vy.z*eye.z);   // Vector3DotProduct(vy, eye)
    result.m14 = -(vz.x*eye.x + vz.y*eye.y + vz.z*eye.z);   // Vector3DotProduct(vz, eye)
    result.m15 = 1.0;
    return result;
}

// Get float array of matrix data
fn MatrixToFloatV(mat: Matrix) -> f32[16] {
    [mat.m0, mat.m1, mat.m2, mat.m3, mat.m4, mat.m5, mat.m6, mat.m7,
     mat.m8, mat.m9, mat.m10, mat.m11, mat.m12, mat.m13, mat.m14, mat.m15]
}

// --- Quaternion -------------------------------------------------------------

// Add two quaternions
fn QuaternionAdd(q1: Quaternion, q2: Quaternion) -> Quaternion {
    Quaternion { q1.x + q2.x, q1.y + q2.y, q1.z + q2.z, q1.w + q2.w }
}

// Add quaternion and float value
fn QuaternionAddValue(q: Quaternion, add: f32) -> Quaternion {
    Quaternion { q.x + add, q.y + add, q.z + add, q.w + add }
}

// Subtract two quaternions
fn QuaternionSubtract(q1: Quaternion, q2: Quaternion) -> Quaternion {
    Quaternion { q1.x - q2.x, q1.y - q2.y, q1.z - q2.z, q1.w - q2.w }
}

// Subtract quaternion and float value
fn QuaternionSubtractValue(q: Quaternion, sub: f32) -> Quaternion {
    Quaternion { q.x - sub, q.y - sub, q.z - sub, q.w - sub }
}

// Get identity quaternion
fn QuaternionIdentity() -> Quaternion { Quaternion { 0.0, 0.0, 0.0, 1.0 } }

// Computes the length of a quaternion
fn QuaternionLength(q: Quaternion) -> f32 { sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w) }

// Normalize provided quaternion
fn QuaternionNormalize(q: Quaternion) -> Quaternion {
    var length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
    if length == 0.0 { length = 1.0; }
    let ilength = 1.0/length;
    return Quaternion { q.x*ilength, q.y*ilength, q.z*ilength, q.w*ilength };
}

// Invert provided quaternion
fn QuaternionInvert(q: Quaternion) -> Quaternion {
    var result = q;
    let lengthSq = q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w;
    if lengthSq != 0.0 {
        let invLength = 1.0/lengthSq;
        result.x *= -invLength;
        result.y *= -invLength;
        result.z *= -invLength;
        result.w *= invLength;
    }
    return result;
}

// Calculate two quaternion multiplication
fn QuaternionMultiply(q1: Quaternion, q2: Quaternion) -> Quaternion {
    let qax = q1.x; let qay = q1.y; let qaz = q1.z; let qaw = q1.w;
    let qbx = q2.x; let qby = q2.y; let qbz = q2.z; let qbw = q2.w;
    return Quaternion {
        qax*qbw + qaw*qbx + qay*qbz - qaz*qby,
        qay*qbw + qaw*qby + qaz*qbx - qax*qbz,
        qaz*qbw + qaw*qbz + qax*qby - qay*qbx,
        qaw*qbw - qax*qbx - qay*qby - qaz*qbz
    };
}

// Scale quaternion by float value
fn QuaternionScale(q: Quaternion, mul: f32) -> Quaternion {
    Quaternion { q.x*mul, q.y*mul, q.z*mul, q.w*mul }
}

// Divide two quaternions
fn QuaternionDivide(q1: Quaternion, q2: Quaternion) -> Quaternion {
    Quaternion { q1.x/q2.x, q1.y/q2.y, q1.z/q2.z, q1.w/q2.w }
}

// Calculate linear interpolation between two quaternions
fn QuaternionLerp(q1: Quaternion, q2: Quaternion, amount: f32) -> Quaternion {
    Quaternion {
        q1.x + amount*(q2.x - q1.x),
        q1.y + amount*(q2.y - q1.y),
        q1.z + amount*(q2.z - q1.z),
        q1.w + amount*(q2.w - q1.w)
    }
}

// Calculate slerp-optimized interpolation between two quaternions
fn QuaternionNlerp(q1: Quaternion, q2: Quaternion, amount: f32) -> Quaternion {
    // QuaternionLerp(q1, q2, amount)
    let q = QuaternionLerp(q1, q2, amount);

    // QuaternionNormalize(q);
    var length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
    if length == 0.0 { length = 1.0; }
    let ilength = 1.0/length;
    return Quaternion { q.x*ilength, q.y*ilength, q.z*ilength, q.w*ilength };
}

// Calculates spherical linear interpolation between two quaternions
fn QuaternionSlerp(q1: Quaternion, q2_in: Quaternion, amount: f32) -> Quaternion {
    var q2 = q2_in;
    var cosHalfTheta = q1.x*q2.x + q1.y*q2.y + q1.z*q2.z + q1.w*q2.w;

    if cosHalfTheta < 0.0 {
        q2.x = -q2.x; q2.y = -q2.y; q2.z = -q2.z; q2.w = -q2.w;
        cosHalfTheta = -cosHalfTheta;
    }

    if rm_fabs(cosHalfTheta) >= 1.0 { return q1; }
    if cosHalfTheta > 0.95 { return QuaternionNlerp(q1, q2, amount); }

    let halfTheta = acos(cosHalfTheta);
    let sinHalfTheta = sqrt(1.0 - cosHalfTheta*cosHalfTheta);

    if rm_fabs(sinHalfTheta) < EPSILON {
        return Quaternion {
            q1.x*0.5 + q2.x*0.5,
            q1.y*0.5 + q2.y*0.5,
            q1.z*0.5 + q2.z*0.5,
            q1.w*0.5 + q2.w*0.5
        };
    }
    let ratioA = sin((1.0 - amount)*halfTheta)/sinHalfTheta;
    let ratioB = sin(amount*halfTheta)/sinHalfTheta;
    return Quaternion {
        q1.x*ratioA + q2.x*ratioB,
        q1.y*ratioA + q2.y*ratioB,
        q1.z*ratioA + q2.z*ratioB,
        q1.w*ratioA + q2.w*ratioB
    };
}

// Calculate quaternion cubic spline interpolation using Cubic Hermite Spline algorithm
// as described in the GLTF 2.0 specification
fn QuaternionCubicHermiteSpline(q1: Quaternion, outTangent1: Quaternion, q2: Quaternion, inTangent2: Quaternion, t: f32) -> Quaternion {
    let t2 = t*t;
    let t3 = t2*t;
    let h00 = 2.0*t3 - 3.0*t2 + 1.0;
    let h10 = t3 - 2.0*t2 + t;
    let h01 = -2.0*t3 + 3.0*t2;
    let h11 = t3 - t2;

    let p0 = QuaternionScale(q1, h00);
    let m0 = QuaternionScale(outTangent1, h10);
    let p1 = QuaternionScale(q2, h01);
    let m1 = QuaternionScale(inTangent2, h11);

    var result = QuaternionAdd(p0, m0);
    result = QuaternionAdd(result, p1);
    result = QuaternionAdd(result, m1);
    return QuaternionNormalize(result);
}

// Calculate quaternion based on the rotation from one vector to another
fn QuaternionFromVector3ToVector3(from: Vector3, to: Vector3) -> Quaternion {
    let cos2Theta = from.x*to.x + from.y*to.y + from.z*to.z;    // Vector3DotProduct(from, to)
    let cross = Vector3 { from.y*to.z - from.z*to.y, from.z*to.x - from.x*to.z, from.x*to.y - from.y*to.x };
    let lengths = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z + cos2Theta*cos2Theta);

    var result = Quaternion { cross.x, cross.y, cross.z, lengths + cos2Theta };

    // Opposite vectors: rotate 180 degrees around any axis perpendicular to from
    if lengths > 0.0 && result.w <= lengths*EPSILON {
        if rm_fabs(from.x) > rm_fabs(from.z) {
            result.x = -from.y;
            result.y = from.x;
            result.z = 0.0;
        } else {
            result.x = 0.0;
            result.y = -from.z;
            result.z = from.y;
        }
        result.w = 0.0;
    }

    // QuaternionNormalize(q);
    let q = result;
    var length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
    if length == 0.0 { length = 1.0; }
    let ilength = 1.0/length;
    return Quaternion { q.x*ilength, q.y*ilength, q.z*ilength, q.w*ilength };
}

// Get a quaternion for a given rotation matrix
fn QuaternionFromMatrix(mat: Matrix) -> Quaternion {
    let fourWSquaredMinus1 = mat.m0  + mat.m5 + mat.m10;
    let fourXSquaredMinus1 = mat.m0  - mat.m5 - mat.m10;
    let fourYSquaredMinus1 = mat.m5  - mat.m0 - mat.m10;
    let fourZSquaredMinus1 = mat.m10 - mat.m0 - mat.m5;

    var biggestIndex = 0;
    var fourBiggestSquaredMinus1 = fourWSquaredMinus1;
    if fourXSquaredMinus1 > fourBiggestSquaredMinus1 {
        fourBiggestSquaredMinus1 = fourXSquaredMinus1;
        biggestIndex = 1;
    }
    if fourYSquaredMinus1 > fourBiggestSquaredMinus1 {
        fourBiggestSquaredMinus1 = fourYSquaredMinus1;
        biggestIndex = 2;
    }
    if fourZSquaredMinus1 > fourBiggestSquaredMinus1 {
        fourBiggestSquaredMinus1 = fourZSquaredMinus1;
        biggestIndex = 3;
    }

    let biggestVal = sqrt(fourBiggestSquaredMinus1 + 1.0)*0.5;
    let mult = 0.25/biggestVal;

    var result = Quaternion { 0.0, 0.0, 0.0, 0.0 };
    if biggestIndex == 0 {
        result.w = biggestVal;
        result.x = (mat.m6 - mat.m9)*mult;
        result.y = (mat.m8 - mat.m2)*mult;
        result.z = (mat.m1 - mat.m4)*mult;
    } else if biggestIndex == 1 {
        result.x = biggestVal;
        result.w = (mat.m6 - mat.m9)*mult;
        result.y = (mat.m1 + mat.m4)*mult;
        result.z = (mat.m8 + mat.m2)*mult;
    } else if biggestIndex == 2 {
        result.y = biggestVal;
        result.w = (mat.m8 - mat.m2)*mult;
        result.x = (mat.m1 + mat.m4)*mult;
        result.z = (mat.m6 + mat.m9)*mult;
    } else {
        result.z = biggestVal;
        result.w = (mat.m1 - mat.m4)*mult;
        result.x = (mat.m8 + mat.m2)*mult;
        result.y = (mat.m6 + mat.m9)*mult;
    }
    return result;
}

// Get a matrix for a given quaternion
fn QuaternionToMatrix(q: Quaternion) -> Matrix {
    var result = MatrixIdentity();

    let a2 = q.x*q.x;
    let b2 = q.y*q.y;
    let c2 = q.z*q.z;
    let ac = q.x*q.z;
    let ab = q.x*q.y;
    let bc = q.y*q.z;
    let ad = q.w*q.x;
    let bd = q.w*q.y;
    let cd = q.w*q.z;

    result.m0 = 1.0 - 2.0*(b2 + c2);
    result.m1 = 2.0*(ab + cd);
    result.m2 = 2.0*(ac - bd);

    result.m4 = 2.0*(ab - cd);
    result.m5 = 1.0 - 2.0*(a2 + c2);
    result.m6 = 2.0*(bc + ad);

    result.m8 = 2.0*(ac + bd);
    result.m9 = 2.0*(bc - ad);
    result.m10 = 1.0 - 2.0*(a2 + b2);
    return result;
}

// Get rotation quaternion for an angle and axis
// NOTE: Angle must be provided in radians
fn QuaternionFromAxisAngle(axis_in: Vector3, angle_in: f32) -> Quaternion {
    var result = Quaternion { 0.0, 0.0, 0.0, 1.0 };
    var axis = axis_in;
    var angle = angle_in;

    var length = sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z);

    if length != 0.0 {
        angle *= 0.5;

        // Vector3Normalize(axis)
        var ilength = 1.0/length;
        axis.x *= ilength;
        axis.y *= ilength;
        axis.z *= ilength;

        let sinres = sin(angle);
        let cosres = cos(angle);

        result.x = axis.x*sinres;
        result.y = axis.y*sinres;
        result.z = axis.z*sinres;
        result.w = cosres;

        // QuaternionNormalize(q);
        let q = result;
        length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
        if length == 0.0 { length = 1.0; }
        ilength = 1.0/length;
        result.x = q.x*ilength;
        result.y = q.y*ilength;
        result.z = q.z*ilength;
        result.w = q.w*ilength;
    }
    return result;
}

// Get the rotation angle and axis for a given quaternion
fn QuaternionToAxisAngle(q_in: Quaternion, outAxis: Vector3&, outAngle: f32&) {
    var q = q_in;
    if rm_fabs(q.w) > 1.0 {
        // QuaternionNormalize(q);
        var length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
        if length == 0.0 { length = 1.0; }
        let ilength = 1.0/length;
        q.x = q.x*ilength;
        q.y = q.y*ilength;
        q.z = q.z*ilength;
        q.w = q.w*ilength;
    }

    var resAxis = Vector3 { 0.0, 0.0, 0.0 };
    let resAngle = 2.0*acos(q.w);
    let den = sqrt(1.0 - q.w*q.w);

    if den > EPSILON {
        resAxis.x = q.x/den;
        resAxis.y = q.y/den;
        resAxis.z = q.z/den;
    } else {
        // This occurs when the angle is zero.
        // Not a problem: just set an arbitrary normalized axis.
        resAxis.x = 1.0;
    }

    outAxis = resAxis;
    outAngle = resAngle;
}

// Get the quaternion equivalent to Euler angles
// NOTE: Rotation order is ZYX
fn QuaternionFromEuler(pitch: f32, yaw: f32, roll: f32) -> Quaternion {
    let x0 = cos(pitch*0.5);
    let x1 = sin(pitch*0.5);
    let y0 = cos(yaw*0.5);
    let y1 = sin(yaw*0.5);
    let z0 = cos(roll*0.5);
    let z1 = sin(roll*0.5);

    return Quaternion {
        x1*y0*z0 - x0*y1*z1,
        x0*y1*z0 + x1*y0*z1,
        x0*y0*z1 - x1*y1*z0,
        x0*y0*z0 + x1*y1*z1
    };
}

// Get the Euler angles equivalent to quaternion (roll, pitch, yaw)
// NOTE: Angles are returned in a Vector3 struct in radians
fn QuaternionToEuler(q: Quaternion) -> Vector3 {
    // Roll (x-axis rotation)
    let x0 = 2.0*(q.w*q.x + q.y*q.z);
    let x1 = 1.0 - 2.0*(q.x*q.x + q.y*q.y);

    // Pitch (y-axis rotation)
    var y0 = 2.0*(q.w*q.y - q.z*q.x);
    y0 = if y0 > 1.0 { 1.0 } else { y0 };
    y0 = if y0 < -1.0 { -1.0 } else { y0 };

    // Yaw (z-axis rotation)
    let z0 = 2.0*(q.w*q.z + q.x*q.y);
    let z1 = 1.0 - 2.0*(q.y*q.y + q.z*q.z);

    return Vector3 { atan2(x0, x1), asin(y0), atan2(z0, z1) };
}

// Transform a quaternion given a transformation matrix
fn QuaternionTransform(q: Quaternion, mat: Matrix) -> Quaternion {
    Quaternion {
        mat.m0*q.x + mat.m4*q.y + mat.m8*q.z + mat.m12*q.w,
        mat.m1*q.x + mat.m5*q.y + mat.m9*q.z + mat.m13*q.w,
        mat.m2*q.x + mat.m6*q.y + mat.m10*q.z + mat.m14*q.w,
        mat.m3*q.x + mat.m7*q.y + mat.m11*q.z + mat.m15*q.w
    }
}

// Check whether two given quaternions are almost equal
fn QuaternionEquals(p: Quaternion, q: Quaternion) -> bool {
    (rm_close(p.x, q.x) && rm_close(p.y, q.y) && rm_close(p.z, q.z) && rm_close(p.w, q.w)) ||
    (rm_close(p.x, -q.x) && rm_close(p.y, -q.y) && rm_close(p.z, -q.z) && rm_close(p.w, -q.w))
}

// Compose a transformation matrix from rotational, translational and scaling components
fn MatrixCompose(translation: Vector3, rotation: Quaternion, scale: Vector3) -> Matrix {
    // Initialize vectors, scaled (0*scale keeps C's signed zeros) and rotated
    let right = Vector3RotateByQuaternion(Vector3Scale(Vector3 { 1.0, 0.0, 0.0 }, scale.x), rotation);
    let up = Vector3RotateByQuaternion(Vector3Scale(Vector3 { 0.0, 1.0, 0.0 }, scale.y), rotation);
    let forward = Vector3RotateByQuaternion(Vector3Scale(Vector3 { 0.0, 0.0, 1.0 }, scale.z), rotation);

    // Set result matrix output
    return Matrix {
        right.x, up.x, forward.x, translation.x,
        right.y, up.y, forward.y, translation.y,
        right.z, up.z, forward.z, translation.z,
        0.0, 0.0, 0.0, 1.0
    };
}

// Decompose a transformation matrix into its rotational, translational and scaling components and remove shear
fn MatrixDecompose(mat: Matrix, translation: Vector3&, rotation: Quaternion&, scale: Vector3&) {
    let eps: f32 = 1e-9;

    // Extract Translation
    translation.x = mat.m12;
    translation.y = mat.m13;
    translation.z = mat.m14;

    // Matrix Columns - Rotation will be extracted into here
    var matColumns: Vector3[3] = [Vector3 { mat.m0, mat.m1, mat.m2 },
                                  Vector3 { mat.m4, mat.m5, mat.m6 },
                                  Vector3 { mat.m8, mat.m9, mat.m10 }];

    // Shear Parameters XY, XZ, and YZ (extract and ignored)
    var shear: f32[3] = [0.0, 0.0, 0.0];

    // Normalized Scale Parameters
    var scl = Vector3 { 0.0, 0.0, 0.0 };

    // Max-Normalizing helps numerical stability
    var stabilizer = eps;
    for i in 3 {
        stabilizer = rm_fmax(stabilizer, rm_fabs(matColumns[i].x));
        stabilizer = rm_fmax(stabilizer, rm_fabs(matColumns[i].y));
        stabilizer = rm_fmax(stabilizer, rm_fabs(matColumns[i].z));
    }
    matColumns[0] = Vector3Scale(matColumns[0], 1.0/stabilizer);
    matColumns[1] = Vector3Scale(matColumns[1], 1.0/stabilizer);
    matColumns[2] = Vector3Scale(matColumns[2], 1.0/stabilizer);

    // X Scale
    scl.x = Vector3Length(matColumns[0]);
    if scl.x > eps { matColumns[0] = Vector3Scale(matColumns[0], 1.0/scl.x); }

    // Compute XY shear and make col2 orthogonal
    shear[0] = Vector3DotProduct(matColumns[0], matColumns[1]);
    matColumns[1] = Vector3Subtract(matColumns[1], Vector3Scale(matColumns[0], shear[0]));

    // Y Scale
    scl.y = Vector3Length(matColumns[1]);
    if scl.y > eps {
        matColumns[1] = Vector3Scale(matColumns[1], 1.0/scl.y);
        shear[0] /= scl.y; // Correct XY shear
    }

    // Compute XZ and YZ shears and make col3 orthogonal
    shear[1] = Vector3DotProduct(matColumns[0], matColumns[2]);
    matColumns[2] = Vector3Subtract(matColumns[2], Vector3Scale(matColumns[0], shear[1]));
    shear[2] = Vector3DotProduct(matColumns[1], matColumns[2]);
    matColumns[2] = Vector3Subtract(matColumns[2], Vector3Scale(matColumns[1], shear[2]));

    // Z Scale
    scl.z = Vector3Length(matColumns[2]);
    if scl.z > eps {
        matColumns[2] = Vector3Scale(matColumns[2], 1.0/scl.z);
        shear[1] /= scl.z; // Correct XZ shear
        shear[2] /= scl.z; // Correct YZ shear
    }

    // Check for a coordinate system flip: if the determinant is -1, negate
    // the z scaling factor
    if Vector3DotProduct(matColumns[0], Vector3CrossProduct(matColumns[1], matColumns[2])) < 0.0 {
        scl = Vector3Negate(scl);
        matColumns[0] = Vector3Negate(matColumns[0]);
        matColumns[1] = Vector3Negate(matColumns[1]);
        matColumns[2] = Vector3Negate(matColumns[2]);
    }

    // Set Scale
    scale = Vector3Scale(scl, stabilizer);

    // Extract Rotation
    let rotationMatrix = Matrix {
        matColumns[0].x, matColumns[1].x, matColumns[2].x, 0.0,
        matColumns[0].y, matColumns[1].y, matColumns[2].y, 0.0,
        matColumns[0].z, matColumns[1].z, matColumns[2].z, 0.0,
        0.0, 0.0, 0.0, 1.0
    };
    rotation = QuaternionFromMatrix(rotationMatrix);
}
