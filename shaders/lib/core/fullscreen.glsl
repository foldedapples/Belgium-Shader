#ifndef CORE_FULLSCREEN_GLSL
#define CORE_FULLSCREEN_GLSL
// Vertex stage shared by every full-screen fragment pass. Iris draws a quad covering
// [0,1]^2 in texture coordinates; reduced-resolution passes (scale.<pass>) get the same
// quad mapped onto their scaled viewport.
#ifdef STAGE_VERTEX
out vec2 texCoord;
void main() {
    gl_Position = ftransform();
    texCoord = gl_MultiTexCoord0.xy;
}
#endif
#endif
