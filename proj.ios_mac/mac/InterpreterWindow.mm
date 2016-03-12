//
//  InterpreterWindow.m
//  CocosPlaygrounds
//
//  Created by Rhody Lugo on 3/9/16.
//
//

#import "InterpreterWindow.h"
#include <iostream>
#include <fcntl.h>

using namespace std;

enum {READ, WRITE};

class IOutputRedirector
{
public:
	IOutputRedirector() {}
	virtual    ~IOutputRedirector(){}

	virtual void    StartRedirecting() = 0;
	virtual void    StopRedirecting()  = 0;

	virtual std::string GetOutput()    = 0;
	virtual void        ClearOutput()  = 0;
};

class CStdoutRedirector : public IOutputRedirector
{
public:
	CStdoutRedirector();
	virtual ~CStdoutRedirector();

	virtual void StartRedirecting();
	virtual void StopRedirecting();

	virtual std::string GetOutput();
	virtual void        ClearOutput();

private:
	int    _pipe[2];
	int    _oldStdOut;
	int    _oldStdErr;
	bool   _redirecting;
	std::string _redirectedOutput;
};

CStdoutRedirector::CStdoutRedirector()
: IOutputRedirector()
, _oldStdOut( 0 )
, _oldStdErr( 0 )
, _redirecting( false )
{
	_pipe[READ] = 0;
	_pipe[WRITE] = 0;
	if( pipe( _pipe ) != -1 ) {
		_oldStdOut = dup( fileno(stdout) );
		_oldStdErr = dup( fileno(stderr) );
	}

	setbuf( stdout, NULL );
	setbuf( stderr, NULL );
}

CStdoutRedirector::~CStdoutRedirector()
{
	if( _redirecting ) {
		StopRedirecting();
	}

	if( _oldStdOut > 0 ) {
		close( _oldStdOut );
	}
	if( _oldStdErr > 0 ) {
		close( _oldStdErr );
	}
	if( _pipe[READ] > 0 ) {
		close( _pipe[READ] );
	}
	if( _pipe[WRITE] > 0 ) {
		close( _pipe[WRITE] );
	}
}

void
CStdoutRedirector::StartRedirecting()
{
	if( _redirecting ) return;

	dup2( _pipe[WRITE], fileno(stdout) );
	dup2( _pipe[WRITE], fileno(stderr) );
	_redirecting = true;
}

void
CStdoutRedirector::StopRedirecting()
{
	if( !_redirecting ) return;

	dup2( _oldStdOut, fileno(stdout) );
	dup2( _oldStdErr, fileno(stderr) );
	_redirecting = false;
}

string
CStdoutRedirector::GetOutput()
{
	const size_t bufSize = 4096;
	char buf[bufSize];
	fcntl( _pipe[READ], F_SETFL, O_NONBLOCK );
	ssize_t bytesRead = read( _pipe[READ], buf, bufSize - 1 );
	while( bytesRead > 0 ) {
		buf[bytesRead] = 0;
		_redirectedOutput += buf;
		bytesRead = read( _pipe[READ], buf, bufSize );
	}

	return _redirectedOutput;
}

void
CStdoutRedirector::ClearOutput()
{
	_redirectedOutput.clear();
}

#define STR(s) #s

#define MAX_LEN 8192
char buffer[MAX_LEN+1] = {0};
int out_pipe[2];
int saved_stdout;
bool capturing = false;

bool startCapturing() {
	saved_stdout = dup(STDOUT_FILENO);  /* save stdout for display later */

	if( pipe(out_pipe) != 0 ) {          /* make a pipe */
		return false;
	}

	dup2(out_pipe[1], STDOUT_FILENO);   /* redirect stdout to the pipe */
	close(out_pipe[1]);
	capturing = true;

	return true;
}

void stopCapturing() {
	if (!capturing) {
		return;
	}

	fflush(stdout);

	read(out_pipe[0], buffer, MAX_LEN); /* read from pipe into buffer */

	dup2(saved_stdout, STDOUT_FILENO);  /* reconnect stdout for testing */

	capturing = false;
}

std::string getCaptured() {
	return buffer;
}

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
		dispatch_async(dispatch_get_main_queue(), ^{
			NSRange selectedRange = self.textView.selectedRange;
			NSFont *font = [NSFont fontWithName:@"Menlo" size:11];
			NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];

			CStdoutRedirector theRedirector;
			theRedirector.StartRedirecting();

			if (selectedRange.length == 0) {
				[self.textView scrollRangeToVisible:NSMakeRange(text.length, 0)];
				[self.textView setSelectedRange:NSMakeRange(text.length, 0)];
				NSString *expression = [text substringFromIndex:NSMaxRange(range)];
				NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:replacementString attributes:attributes];
				[self.textView.textStorage appendAttributedString:attributedString];
				_interpreter->process(expression.UTF8String);

			} else {
				NSString *expression = [text substringWithRange:selectedRange];
				expression = [text substringWithRange:selectedRange];
				if (expression.length - 1 != [expression rangeOfString:@"\n" options:NSBackwardsSearch].location) {
					expression  = [expression stringByAppendingString:@"\n"];
				}
				NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:expression attributes:attributes];
				[self.textView.textStorage appendAttributedString:attributedString];
				_interpreter->process(expression.UTF8String);
			}

			theRedirector.StopRedirecting();
			NSString *expression = [NSString stringWithFormat:@"%s", theRedirector.GetOutput().c_str()];
			if (expression.length - 1 == [expression rangeOfString:@"\n" options:NSBackwardsSearch].location) {
				expression = [expression substringToIndex:[expression length] - 1];
			}
			NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:expression
																				   attributes:@{NSFontAttributeName: font,
																								NSForegroundColorAttributeName: [NSColor grayColor]}];
			theRedirector.ClearOutput();
			[self.textView.textStorage appendAttributedString:attributedString];

			attributedString = [[NSAttributedString alloc] initWithString:@"\n"
															   attributes:@{NSFontAttributeName: font,
																			NSForegroundColorAttributeName: [NSColor blackColor]}];

			[self.textView.textStorage appendAttributedString:attributedString];

			[self.textView setNeedsDisplay:YES];
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
