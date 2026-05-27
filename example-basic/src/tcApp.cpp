#include "tcApp.h"
#include <tcxVirtualCam.h>

using namespace tcx;

static VirtualCam vcam;
static Fbo      fbo;
static Mesh     cube;
static Texture  barsTex;
static EasyCam  cam;
static bool     camReady = false;

// SMPTE-ish 7-bar color pattern at the texture resolution we want
static Pixels buildColorBars(int w, int h) {
    static const Color bars[7] = {
        Color(0.75f, 0.75f, 0.75f),  // grey
        Color(0.75f, 0.75f, 0.00f),  // yellow
        Color(0.00f, 0.75f, 0.75f),  // cyan
        Color(0.00f, 0.75f, 0.00f),  // green
        Color(0.75f, 0.00f, 0.75f),  // magenta
        Color(0.75f, 0.00f, 0.00f),  // red
        Color(0.00f, 0.00f, 0.75f),  // blue
    };
    Pixels p;
    p.allocate(w, h, 4);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int idx = (x * 7) / w;
            p.setColor(x, y, bars[idx]);
        }
    }
    return p;
}

void tcApp::setup() {
    fbo.allocate(960, 600);

    cube = createBox(140.0f);
    Pixels barsPx = buildColorBars(256, 256);
    barsTex.allocate(barsPx);

    cam.setDistance(380.0f);

    camReady = vcam.setup("TrussC Virtual Camera", 960, 600);
    vcam.setFrameRate(30);
}

void tcApp::update() {
}

void tcApp::draw() {
    fbo.begin();
    clear(0.07f, 0.08f, 0.11f);

    cam.begin();
        pushMatrix();
        float t = getElapsedTimef();
        rotateY(t * 0.6f);
        rotateX(t * 0.4f);
        setColor(1);
        cube.draw(barsTex);
        popMatrix();
    cam.end();

    // Big title overlay
    {
        pushMatrix();
        translate(fbo.getWidth() / 2, fbo.getHeight() / 2);
        pushStyle();
        setColor(0.1, 0, 0.5, 0.5);
        fill();
        drawRectSquircle(-250, -70, 500, 140, 70);
        setColor(1);
        setTextAlign(Center, Center);
        drawBitmapString("TrussC Virtual Cam", 0, 0, 3.0f);
        popStyle();
        popMatrix();
    }

    // Small status footer
    string status = camReady
        ? "sending - " + to_string((int)getFrameRate()) + " fps"
        : "backend unavailable (stub mode)";
    drawBitmapString(status, 40, fbo.getHeight() - 30);
    fbo.end();

    // Ship to virtual camera (no-op until backend lands)
    if (camReady) vcam.send(fbo);

    // Mirror to window so the dev can see what consumers would see
    clear(0.12f);
    fbo.draw(0, 0);
}

void tcApp::keyPressed(int key) {}
void tcApp::keyReleased(int key) {}

void tcApp::mousePressed(Vec2 pos, int button) {}
void tcApp::mouseReleased(Vec2 pos, int button) {}
void tcApp::mouseMoved(Vec2 pos) {}
void tcApp::mouseDragged(Vec2 pos, int button) {}
void tcApp::mouseScrolled(Vec2 delta) {}

void tcApp::windowResized(int width, int height) {}
void tcApp::filesDropped(const vector<string>& files) {}
void tcApp::exit() {}
