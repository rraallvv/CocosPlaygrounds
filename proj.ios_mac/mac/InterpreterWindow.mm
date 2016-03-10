//
//  InterpreterWindow.m
//  CocosPlaygrounds
//
//  Created by Rhody Lugo on 3/9/16.
//
//

#import "InterpreterWindow.h"

#define STR(s) #s

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

@implementation InterpreterWindow

- (void)textDidChange:(NSNotification *)notification {
	//NSLog(@"Ok");
}

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
	__block NSString *text = self.textView.string;
	NSRange range = [text rangeOfString:@"\n" options:NSBackwardsSearch];

	BOOL isMultiline = range.location != NSNotFound;
	BOOL isCursorInLastLine = range.location >= affectedCharRange.location;
	BOOL newTextHasNewline = [replacementString rangeOfString:@"\n"].location != NSNotFound;

	if ((isMultiline && isCursorInLastLine) || newTextHasNewline) {
		NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:replacementString];
		[self.textView.textStorage appendAttributedString:attributedString];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.textView scrollRangeToVisible:NSMakeRange(text.length, 0)];
			[self.textView setSelectedRange:NSMakeRange(text.length, 0)];
		});
		return NO;
	}
	return YES;
}

- (void)setupInterpreter {
	_interpreter = new cling::Interpreter(argc, argv, llvmdir);
	
	_interpreter->loadFile("iostream");
	_interpreter->loadFile("cocos2d.h");
	_interpreter->loadFile("cocostudio/CocoStudio.h");

	_interpreter->process(STR(using namespace std;));
	_interpreter->process(STR(using namespace cocos2d;));
	_interpreter->process(STR(cout << "Hello World!" << endl;));

	std::string s = "exported string";

	[self exportToInterpreter:"string" name:"s" object:&s];
	[self exportToInterpreter:"string *" name:"ps" object:&s];
	_interpreter->process(STR(cout << s << endl;));
	_interpreter->process(STR(cout << *ps << endl;));

	_interpreter->process(STR(
							 auto rootNode = CSLoader::createNode("MainScene.csb");

							 auto layer = Layer::create();
							 layer->addChild(rootNode);

							 auto scene = Scene::create();
							 scene->addChild(layer);

							 Director::getInstance()->runWithScene(scene);
							 ));

	NSWindowController *wc = (__bridge NSWindowController *)(__bridge_retained void *)[[NSWindowController alloc] initWithWindowNibName:@"Interpreter"];
	[wc showWindow:nil];
}

- (void)exportToInterpreter:(const std::string)typeName name:(std::string)name object:(void *)object {
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
	snprintf(buff, sizeof(buff), "%s %s=%cstatic_cast<%s*>((void*)%p);", typeName.c_str(), name.c_str(), exportAsPointer ? ' ' : '*', rawType.c_str(), object);

	_interpreter->process(buff);
}

@end
