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

enum {READ, WRITE};

-(void)awakeFromNib {
	self.textView.continuousSpellCheckingEnabled = NO;
	self.textView.automaticQuoteSubstitutionEnabled = NO;
	self.textView.enabledTextCheckingTypes = 0;
	_font = [NSFont fontWithName:@"Menlo" size:11];
	self.textView.typingAttributes = @{NSFontAttributeName: _font};

	_interpreter = new cling::Interpreter(argc, argv, llvmdir);

	_interpreter->loadFile("iostream");
	_interpreter->loadFile("cocos2d.h");
	_interpreter->loadFile("cocostudio/CocoStudio.h");

	_interpreter->process("using namespace std;");
	_interpreter->process("using namespace cocos2d;");

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

	redirectedOutput = [[NSMutableString alloc] init];

	if( pipe( redirectionPipe ) != -1 ) {
		oldStandardOutput = dup( fileno(stdout) );
		oldStandardError = dup( fileno(stderr) );
	}
	setbuf( stdout, NULL );
	setbuf( stderr, NULL );
}

- (void) dealloc {
	if( redirecting  ) {
		[self stopRedirecting];
	}

	if( oldStandardOutput > 0 ) {
		close( oldStandardOutput );
	}
	if( oldStandardError > 0 ) {
		close( oldStandardError );
	}
	if( redirectionPipe[READ] > 0 ) {
		close( redirectionPipe[READ] );
	}
	if( redirectionPipe[WRITE] > 0 ) {
		close( redirectionPipe[WRITE] );
	}
}

- (void)sendEvent:(NSEvent*)event {
	if ([event type] == NSKeyDown) {
		if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
			if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"x"] == NSOrderedSame) {
				// Cut
				if ([NSApp sendAction:@selector(cut:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"c"] == NSOrderedSame) {
				// Copy
				if ([NSApp sendAction:@selector(copy:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"v"] == NSOrderedSame) {
				// Paste only the source code
				NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
				NSArray *classes = [[NSArray alloc] initWithObjects:[NSAttributedString class], nil];
				NSArray *items = [pasteBoard readObjectsForClasses:classes options:@{}];
				NSMutableAttributedString *string = [[items lastObject] mutableCopy];

				[string enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, string.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
					if (value) {
						[string replaceCharactersInRange:range withString:@"\n"];
					}
				}];

				[self textView:self.textView shouldChangeTextInRange:NSMakeRange(self.textView.string.length, 0) replacementString:string.string];
				return;

			} else if ([[event charactersIgnoringModifiers] isEqualToString:@"z"]) {
				// Undo
				if ([NSApp sendAction:@selector(undo:) to:nil from:self])
					return;

			} else if ([[event charactersIgnoringModifiers] caseInsensitiveCompare:@"a"] == NSOrderedSame) {
				// Select all
				if ([NSApp sendAction:@selector(selectAll:) to:nil from:self])
					return;
			}

		} else if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == (NSCommandKeyMask | NSShiftKeyMask)) {
			// Redo
			if ([[event charactersIgnoringModifiers] isEqualToString:@"Z"]) {
				if ([NSApp sendAction:@selector(redo:) to:nil from:self])
					return;
			}
		}

		switch( [event keyCode] ) {
			case 126: {     // up arrow
				__block NSRange currentRange =  self.textView.selectedRange;
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *text = self.textView.string;
					if (currentRange.location <= 0) currentRange.location = text.length + 1;

					NSInteger start = [text rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, currentRange.location - 1)].location;
					if (start == NSNotFound) start = -1;

					NSInteger length = [[text substringFromIndex:start + 1] rangeOfString:@"\n"].location;

					NSRange selectedRange = NSMakeRange(start + 1, length + 1);

					if ((([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) & NSShiftKeyMask) != 0) {
						selectedRange = NSUnionRange(selectedRange, currentRange);
					}

					self.textView.selectedRange = selectedRange;
					[self.textView scrollRangeToVisible:selectedRange];
				});
			}
				break;
			case 125: {     // down arrow
				__block NSRange currentRange =  self.textView.selectedRange;
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *text = self.textView.string;

					NSInteger end = [[text substringFromIndex:currentRange.location + currentRange.length] rangeOfString:@"\n"].location;
					NSInteger length = 0;
					if (end == NSNotFound) {
						if (currentRange.length > 0) {
							end = text.length + 1;
						} else {
							end = [text rangeOfString:@"\n"].location + 1;
							length = end;
						}
					} else {
						end += currentRange.location + currentRange.length + 1;
						length = end - [text rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, currentRange.location + currentRange.length)].location - 1;
					}

					NSRange selectedRange = NSMakeRange(end - length, length);

					if ((([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) & NSShiftKeyMask) != 0) {
						selectedRange = NSUnionRange(selectedRange, currentRange);
					}

					self.textView.selectedRange = selectedRange;
					[self.textView scrollRangeToVisible:selectedRange];
				});
			}
				break;
			case 124:       // right arrow
			case 123:       // left arrow
				break;
			default:
				break;
		}
	}
	[super sendEvent:event];
}

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
	NSString *text = self.textView.string;
	NSInteger commandLinePosition = [text rangeOfString:@"\n" options:NSBackwardsSearch].location + 1;
	NSString *replacement = replacementString.copy;
	NSRange selectedRange = self.textView.selectedRange;

	//BOOL isMultiline = range.location != NSNotFound;
	BOOL inCommandLine = commandLinePosition <= affectedCharRange.location;
	BOOL hasNewline = [replacementString rangeOfString:@"\n"].location != NSNotFound;
	BOOL hasSelection = selectedRange.length > 0;

	enum {APPEND_CHAR, INSERT_CHAR, APPEND_SELECTION, REPLACE_SELECTION, PASS_THROUGH} state;

	if (!inCommandLine && !hasNewline && !hasSelection) {
		state = APPEND_CHAR;
	} else if (!inCommandLine && hasNewline && !hasSelection) {
		state = APPEND_CHAR;
	} else if (!inCommandLine && !hasNewline && hasSelection) {
		state = APPEND_CHAR;
	} else if (!inCommandLine && hasNewline && hasSelection) {
		state = APPEND_SELECTION;
	} else if (inCommandLine && !hasNewline && !hasSelection) {
		state = PASS_THROUGH;
	} else if (inCommandLine && hasNewline && !hasSelection) {
		state = INSERT_CHAR;
	} else if (inCommandLine && !hasNewline && hasSelection) {
		state = PASS_THROUGH;
	} else if (inCommandLine && hasNewline && hasSelection) {
		state = REPLACE_SELECTION;
	}

	if (state == PASS_THROUGH) {
		return YES;
	}

	NSDictionary *attributes = @{NSFontAttributeName: _font};

	switch (state) {
		case APPEND_CHAR:
			[self appendString:replacement attributes:attributes];
			break;

		case INSERT_CHAR:
			[self.textView.textStorage replaceCharactersInRange:selectedRange withString:replacement];
			break;

		case APPEND_SELECTION:
			[self appendString:[self stringByRemovingLastNewline:[text substringWithRange:selectedRange]] attributes:attributes];
			break;

		case REPLACE_SELECTION:
			[self.textView.textStorage replaceCharactersInRange:selectedRange withString:replacement];
			break;

		default: //PASS_THROUGH
			break;
	}

	NSArray *expressions = [[self.textView.string substringFromIndex:commandLinePosition] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

	[self.textView.textStorage replaceCharactersInRange:NSMakeRange(commandLinePosition, self.textView.string.length - commandLinePosition) withString:@""];

	NSDictionary *resultAttributes = @{NSFontAttributeName: _font,
									   NSForegroundColorAttributeName: [NSColor grayColor]};

	for (NSInteger i = 0; i < expressions.count; i++) {
		NSString *expression = expressions[i];
		[self appendString:expression attributes:attributes];
		if (expression.length > 0 && i < expressions.count - 1) {
			NSString *result = [self processExpression:expression];
			[self appendString:result attributes:resultAttributes];
		}
	}

	// Scroll to the bottom
	self.textView.selectedRange = NSMakeRange(self.textView.string.length, 0);
	[self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
	[self.textView setNeedsDisplay:YES];

#if 0
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *expression = nil;

		if (selectedRange.length == 0) {
			expression = replacement;
		} else {
			expression = [self stringByRemovingNewline:[text substringWithRange:selectedRange]];
		}

		[self appendString:expression attributes:@{NSFontAttributeName: _font}];

		NSString *expression = [text substringFromIndex:NSMaxRange(range)];

		NSString *result = [NSString stringWithFormat:@"%@", [self processExpression:expression]];

		if (result.length - 1 == [result rangeOfString:@"\n" options:NSBackwardsSearch].location) {
			result = [result substringToIndex:[result length] - 1];
		}
		attributedString = [[NSAttributedString alloc] initWithString:result
														   attributes:@{NSFontAttributeName: _font,
																		NSForegroundColorAttributeName: [NSColor grayColor]}];
		[self.textView.textStorage appendAttributedString:attributedString];

		attributedString = [[NSAttributedString alloc] initWithString:@"\n"
														   attributes:@{NSFontAttributeName: _font,
																		NSForegroundColorAttributeName: [NSColor blackColor]}];

		[self.textView.textStorage appendAttributedString:attributedString];

		// Scroll to the bottom
		self.textView.selectedRange = NSMakeRange(text.length, 0);
		[self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
		[self.textView setNeedsDisplay:YES];
	});
#endif

	return NO;
}

- (NSString *)processExpression:(NSString *)expression {
	[self startRedirecting];

	_interpreter->process(expression.UTF8String);

	[self stopRedirecting];

	NSString *result = [NSString stringWithFormat:@"\n%@", [self output]];

	[self clearOutput];

	return result;
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

- (NSString *)stringByRemovingLastNewline:(NSString *)string {
	if (string.length - 1 == [string rangeOfString:@"\n" options:NSBackwardsSearch].location) {
		string = [string substringToIndex:string.length - 1];
	}
	return string;
}

- (void)appendString:(NSString *)string attributes:(NSDictionary *)attributes {
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string
																		   attributes:attributes];
	[self.textView.textStorage appendAttributedString:attributedString];
	self.textView.selectedRange = NSMakeRange(self.textView.string.length, 0);
}

#pragma mark - std redirection

- (void) startRedirecting {
	if( redirecting ) return;

	dup2( redirectionPipe[WRITE], fileno(stdout) );
	dup2( redirectionPipe[WRITE], fileno(stderr) );
	redirecting = true;
}

- (void) stopRedirecting {
	if( !redirecting ) return;

	dup2( oldStandardOutput, fileno(stdout) );
	dup2( oldStandardError, fileno(stderr) );
	redirecting = false;
}

- (NSString*) output {
	const size_t bufferSize = 4096;
	char buffer[bufferSize];
	fcntl( redirectionPipe[READ], F_SETFL, O_NONBLOCK );
	ssize_t bytesRead = read( redirectionPipe[READ], buffer, bufferSize - 1 );
	while( bytesRead > 0 ) {
		buffer[bytesRead] = 0;
		NSString* tempString = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
		[redirectedOutput appendString:tempString];
		bytesRead = read( redirectionPipe[READ], buffer, bufferSize );
	}

	return [NSString stringWithFormat:@"%@", redirectedOutput];
}

- (void) clearOutput {
	[redirectedOutput setString:@""];
}

@end
