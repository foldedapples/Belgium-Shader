uniform sampler2D gtexture;

in vec2 vUv;
in vec4 vColor;

/* RENDERTARGETS: 1 */
layout(location = 0) out vec4 outAlbedo;

void main() {
    vec4 c = texture(gtexture, vUv) * vColor;
    if (c.a < 0.004) discard;
    outAlbedo = c;
}
