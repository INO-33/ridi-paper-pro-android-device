#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

namespace {

constexpr EGLint kWidth = 1872;
constexpr EGLint kHeight = 1404;
constexpr int kWarmupFrames = 1;
constexpr int kMeasuredFrames = 3;

uint64_t nowNs() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL + ts.tv_nsec;
}

void fail(const char* operation) {
    fprintf(stderr, "FAIL %s egl=0x%04x gl=0x%04x\n",
            operation, static_cast<unsigned>(eglGetError()),
            static_cast<unsigned>(glGetError()));
    exit(1);
}

GLuint compileShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[512]{};
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        fprintf(stderr, "FAIL shader: %s\n", log);
        exit(1);
    }
    return shader;
}

GLuint makeProgram() {
    static const char* vertexSource =
            "attribute vec2 position;\n"
            "attribute vec2 texcoord;\n"
            "varying vec2 uv;\n"
            "void main() { uv = texcoord; gl_Position = vec4(position, 0.0, 1.0); }\n";
    static const char* fragmentSource =
            "precision mediump float;\n"
            "varying vec2 uv;\n"
            "uniform sampler2D texture0;\n"
            "void main() { gl_FragColor = texture2D(texture0, uv); }\n";

    GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource);
    GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource);
    GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glBindAttribLocation(program, 1, "texcoord");
    glLinkProgram(program);
    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (ok != GL_TRUE)
        fail("glLinkProgram");
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    return program;
}

void printTiming(const char* name, const uint64_t* samples, int count) {
    uint64_t sum = 0;
    uint64_t minimum = UINT64_MAX;
    uint64_t maximum = 0;
    for (int i = 0; i < count; ++i) {
        sum += samples[i];
        if (samples[i] < minimum) minimum = samples[i];
        if (samples[i] > maximum) maximum = samples[i];
    }
    printf("%s frames=%d min_ms=%.3f avg_ms=%.3f max_ms=%.3f\n",
           name, count, minimum / 1000000.0,
           (sum / static_cast<double>(count)) / 1000000.0,
           maximum / 1000000.0);
}

}  // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr))
        fail("eglInitialize");

    const EGLint configAttributes[] = {
            EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_RED_SIZE, 5,
            EGL_GREEN_SIZE, 6,
            EGL_BLUE_SIZE, 5,
            EGL_NONE,
    };
    EGLConfig config = nullptr;
    EGLint configCount = 0;
    if (!eglChooseConfig(display, configAttributes, &config, 1, &configCount) ||
        configCount != 1)
        fail("eglChooseConfig");

    const EGLint pbufferAttributes[] = {
            EGL_WIDTH, kWidth,
            EGL_HEIGHT, kHeight,
            EGL_NONE,
    };
    EGLSurface surface = eglCreatePbufferSurface(display, config, pbufferAttributes);
    if (surface == EGL_NO_SURFACE)
        fail("eglCreatePbufferSurface");

    const EGLint contextAttributes[] = {
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE,
    };
    EGLContext context =
            eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
    if (context == EGL_NO_CONTEXT ||
        !eglMakeCurrent(display, surface, surface, context))
        fail("eglCreateContext/eglMakeCurrent");

    printf("renderer=%s\nversion=%s\nsize=%dx%d\n",
           reinterpret_cast<const char*>(glGetString(GL_RENDERER)),
           reinterpret_cast<const char*>(glGetString(GL_VERSION)),
           kWidth, kHeight);
    glViewport(0, 0, kWidth, kHeight);

    GLuint program = makeProgram();
    glUseProgram(program);
    const GLfloat positions[] = {-1, -1, 1, -1, -1, 1, 1, 1};
    const GLfloat texcoords[] = {0, 0, 1, 0, 0, 1, 1, 1};
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, positions);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, texcoords);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);

    constexpr int textureWidth = 256;
    constexpr int textureHeight = 256;
    auto* pixels = static_cast<uint32_t*>(
            malloc(textureWidth * textureHeight * sizeof(uint32_t)));
    if (!pixels)
        fail("malloc");
    for (int y = 0; y < textureHeight; ++y) {
        for (int x = 0; x < textureWidth; ++x) {
            const uint32_t gray = ((x ^ y) & 16) ? 0xff : 0x30;
            pixels[y * textureWidth + x] =
                    0xff000000U | gray << 16 | gray << 8 | gray;
        }
    }

    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureWidth, textureHeight,
                 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    free(pixels);

    uint64_t clearSamples[kMeasuredFrames]{};
    uint64_t quadSamples[kMeasuredFrames]{};
    for (int frame = -kWarmupFrames; frame < kMeasuredFrames; ++frame) {
        uint64_t start = nowNs();
        glClearColor(1, 1, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glFinish();
        if (frame >= 0)
            clearSamples[frame] = nowNs() - start;
    }
    for (int frame = -kWarmupFrames; frame < kMeasuredFrames; ++frame) {
        uint64_t start = nowNs();
        glClearColor(1, 1, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glFinish();
        if (frame >= 0)
            quadSamples[frame] = nowNs() - start;
    }

    printTiming("clear", clearSamples, kMeasuredFrames);
    printTiming("textured_quad", quadSamples, kMeasuredFrames);

    glDeleteTextures(1, &texture);
    glDeleteProgram(program);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
    return 0;
}
