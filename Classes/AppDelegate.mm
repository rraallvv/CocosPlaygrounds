#include "AppDelegate.h"
#include <iostream>
#import <Cocoa/Cocoa.h>

USING_NS_CC;

static const int argc = 10;
static const char *argv[argc] = {
	"/usr/local/opt/root/etc",
	"-I/usr/local/opt/root/etc",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/cocos",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/cocos/editor-support",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/external",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/external/glfw3/include/mac",
};
static const char *llvmdir = "/usr/local/opt/root/etc/cling";

#define STR(s) #s

AppDelegate::AppDelegate()
: _interpreter(argc, argv, llvmdir)
{
	_interpreter.loadFile("iostream");
	_interpreter.loadFile("cocos2d.h");
	_interpreter.loadFile("cocostudio/CocoStudio.h");

	_interpreter.process(STR(using namespace std;));
	_interpreter.process(STR(using namespace cocos2d;));
	_interpreter.process(STR(cout << "Hello World!" << endl;));

	std::string s = "exported string";

	exportToInterpreter("string", "s", &s);
	exportToInterpreter("string *", "ps", &s);
	_interpreter.process(STR(cout << s << endl;));
	_interpreter.process(STR(cout << *ps << endl;));
}

AppDelegate::~AppDelegate()
{
}

void AppDelegate::exportToInterpreter(const std::string &typeName, const std::string& name, void *obj) {
	char buff[100];
	std::string rawType = typeName;
	bool exportAsPointer = rawType.back() == '*';

	rawType.erase(std::remove(rawType.begin(), rawType.end(), '&'), rawType.end());
	rawType.erase(std::remove(rawType.begin(), rawType.end(), '*'), rawType.end());
	rawType.erase(0, rawType.find_first_not_of(' '));
	rawType.erase(rawType.find_last_not_of(' ') + 1);

	//produce sth like:
	//Type& qling=*static_cast<Type*>((void*)47315771);"
	//or
	//Type* qling=static_cast<Type*>((void*)47315771);"
	snprintf(buff, sizeof(buff), "%s %s=%cstatic_cast<%s*>((void*)%p);", typeName.c_str(), name.c_str(), exportAsPointer ? ' ' : '*', rawType.c_str(), obj);

	_interpreter.process(buff);
}

//if you want a different context,just modify the value of glContextAttrs
//it will takes effect on all platforms
void AppDelegate::initGLContextAttrs() {
    //set OpenGL context attributions,now can only set six attributions:
    //red,green,blue,alpha,depth,stencil
    GLContextAttrs glContextAttrs = {8, 8, 8, 8, 24, 8};

    GLView::setGLContextAttrs(glContextAttrs);
}

bool AppDelegate::applicationDidFinishLaunching() {
    // initialize director
    auto director = Director::getInstance();
    auto glview = director->getOpenGLView();
    if(!glview) {
		glview = GLViewImpl::createWithRect("CocosPlaygrounds", cocos2d::Rect(0, 0, 960, 640));
        director->setOpenGLView(glview);
    }

    director->getOpenGLView()->setDesignResolutionSize(960, 640, ResolutionPolicy::SHOW_ALL);

    // turn on display FPS
    director->setDisplayStats(true);

    // set FPS. the default value is 1.0/60 if you don't call this
    director->setAnimationInterval(1.0 / 60);

    FileUtils::getInstance()->addSearchPath("res");

	_interpreter.process(STR(
							 auto rootNode = CSLoader::createNode("MainScene.csb");

							 auto layer = Layer::create();
							 layer->addChild(rootNode);

							 auto scene = Scene::create();
							 scene->addChild(layer);

							 Director::getInstance()->runWithScene(scene);
						 ));

	NSWindowController *wc = [[NSWindowController alloc] initWithWindowNibName:@"Interpreter"];
	[wc showWindow:nil];

    return true;
}

// This function will be called when the app is inactive. When comes a phone call,it's be invoked too
void AppDelegate::applicationDidEnterBackground() {
    Director::getInstance()->stopAnimation();

    // if you use SimpleAudioEngine, it must be pause
    // SimpleAudioEngine::getInstance()->pauseBackgroundMusic();
}

// this function will be called when the app is active again
void AppDelegate::applicationWillEnterForeground() {
    Director::getInstance()->startAnimation();

    // if you use SimpleAudioEngine, it must resume here
    // SimpleAudioEngine::getInstance()->resumeBackgroundMusic();
}
