#include "tcApp.h"
#include <tcxVirtualCam.h>

using namespace tcx;

static VirtualCam vcam;
static Fbo fbo;
static bool camReady = false;

void tcApp::setup() {
    fbo.allocate(960, 600);
    camReady = vcam.setup("TrussC Virtual Camera", 960, 600);
    vcam.setFrameRate(30);
}

void tcApp::update() {
}

void tcApp::draw() {
    // Render scene into FBO (this is what gets shipped out as the camera feed)
    fbo.begin();
    clear(colors::navy);

    setColor(colors::cornflowerBlue);
    pushMatrix();
    translate(fbo.getWidth() / 2.0f, fbo.getHeight() / 2.0f);
    rotate(getElapsedTimef() * 0.3f);
    drawRect(-120, -120, 240, 240);
    popMatrix();

    setColor(1);
    drawBitmapString("tcxVirtualCam - " + to_string((int)getFrameRate()) + " fps", 20, 20);
    fbo.end();

    // Ship the frame to the virtual camera (no-op until a backend is wired in)
    if (camReady) {
        vcam.send(fbo);
    }

    // Mirror to the window so you can see what consumers would see
    clear(0.12f);
    fbo.draw(0, 0);

    setColor(1);
    string status = camReady
        ? "VirtualCam: " + vcam.getName() + " (sending)"
        : "VirtualCam: backend unavailable (stub mode)";
    drawBitmapString(status, 20, getWindowHeight() - 20);
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
