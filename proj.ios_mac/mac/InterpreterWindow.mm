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

-(void)awakeFromNib {
	self.textView.font = [NSFont fontWithName:@"Menlo" size:11];
	self.textView.continuousSpellCheckingEnabled = NO;
	self.textView.automaticQuoteSubstitutionEnabled = NO;
	self.textView.enabledTextCheckingTypes = 0;

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

	std::string expression =
	"/************ CocosPlaygrounds *************\n"
	" * Type C++ code and press enter to run it *\n"
	" *******************************************/\n\n"
	"auto rootNode = CSLoader::createNode(\"MainScene.csb\");\n"
	"auto layer = Layer::create();\n"
	"layer->addChild(rootNode);\n"
	"auto scene = Scene::create();\n"
	"scene->addChild(layer);\n"
	"Director::getInstance()->runWithScene(scene);\n";

	_interpreter->process(expression);

	self.textView.string = [NSString stringWithFormat:@"%s", expression.c_str()];
}

- (void)sendEvent:(NSEvent*)event {
	if ([event type] == NSKeyDown) {
		if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
			if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"x"] == NSOrderedSame) {
				if ([NSApp sendAction:@selector(cut:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"c"] == NSOrderedSame) {
				if ([NSApp sendAction:@selector(copy:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"v"] == NSOrderedSame) {
				if ([NSApp sendAction:@selector(paste:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] isEqualToString:@"z"]) {
				if ([NSApp sendAction:@selector(undo:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"a"] == NSOrderedSame) {
				if ([NSApp sendAction:@selector(selectAll:) to:nil from:self])
					return;
			}

		} else if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == (NSCommandKeyMask | NSShiftKeyMask)) {
			if ([[event charactersIgnoringModifiers] isEqualToString:@"Z"]) {
				if ([NSApp sendAction:@selector(redo:) to:nil from:self])
					return;
			}
		} else {
			switch( [event keyCode] ) {
				case 126: {     // up arrow
					__block NSInteger currentPosition =  self.textView.selectedRange.location;
					dispatch_async(dispatch_get_main_queue(), ^{
						NSString *text = self.textView.string;
						if (currentPosition <= 0) currentPosition = text.length;

						NSInteger start = [text rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, currentPosition - 1)].location;
						if (start == NSNotFound) start = -1;

						NSInteger length = [[text substringFromIndex:start + 1] rangeOfString:@"\n"].location;

						self.textView.selectedRange = NSMakeRange(start + 1, length + 1);
					});
				}
					break;
				case 125: {     // down arrow
					__block NSInteger currentPosition =  self.textView.selectedRange.location;
					dispatch_async(dispatch_get_main_queue(), ^{
						NSString *text = self.textView.string;

						NSInteger start = -1;
						if (currentPosition < text.length) {
							start = [[text substringFromIndex:currentPosition] rangeOfString:@"\n"].location;
							if (start == NSNotFound) {
								start = -1;
							} else {
								start = currentPosition + start;
							}
						}

						NSInteger length = [[text substringFromIndex:start + 1] rangeOfString:@"\n"].location;

						self.textView.selectedRange = NSMakeRange(start + 1, length + 1);
					});
				}
					break;
				case 124:       // right arrow
				case 123:       // left arrow
					NSLog(@"Arrow key pressed!");
					break;
				default:
					break;
			}
		}
	}
	[super sendEvent:event];
}

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
	__block NSString *text = self.textView.string;
	__block NSRange range = [text rangeOfString:@"\n" options:NSBackwardsSearch];

	BOOL isMultiline = range.location != NSNotFound;
	BOOL isCursorInLastLine = range.location >= affectedCharRange.location;
	BOOL newTextHasNewline = [replacementString rangeOfString:@"\n"].location != NSNotFound;

	if ((isMultiline && isCursorInLastLine) || newTextHasNewline) {
		NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:replacementString];
		[self.textView.textStorage appendAttributedString:attributedString];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.textView scrollRangeToVisible:NSMakeRange(text.length, 0)];
			[self.textView setSelectedRange:NSMakeRange(text.length, 0)];
			std::string expression = [text substringFromIndex:NSMaxRange(range)].UTF8String;
			_interpreter->process(expression);
		});
		return NO;
	}
	return YES;
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
