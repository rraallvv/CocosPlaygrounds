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

static const char *argv[] = {
	"/usr/local/opt/root/etc",
	"-I/usr/local/opt/root/etc",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/cocos",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/cocos/editor-support",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/external",
	"-I/Applications/Cocos/Cocos2d-x/cocos2d-x-3.10/external/glfw3/include/mac"
};
static const char *llvmdir = "/usr/local/opt/root/etc/cling";

@implementation InterpreterWindow

enum {READ, WRITE};

-(id)init {
	if (self = [super initWithContentRect:NSMakeRect(0, 0, 480, 270)
								styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
								  backing:NSBackingStoreNonretained
									defer:NO
								   screen:[NSScreen mainScreen]]) {

		CGFloat margin = 4;

		NSRect scrollViewRect = NSInsetRect(self.contentView.bounds, margin, margin);

		NSScrollView *scrollview = [[NSScrollView alloc] initWithFrame:scrollViewRect];
		//scrollview.backgroundColor = [[NSColor blueColor] colorWithAlphaComponent:0.2];
		scrollview.drawsBackground = YES;

		NSSize contentSize = [scrollview contentSize];

		scrollview.borderType = NSBezelBorder;

		scrollview.hasVerticalScroller = YES;
		scrollview.hasHorizontalScroller = NO;

		scrollview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

		self.textView = [[NSTextView alloc] initWithFrame:scrollview.bounds];
		self.textView.drawsBackground = NO;

		self.textView.minSize = NSMakeSize(0.0, contentSize.height);
		self.textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);

		self.textView.verticallyResizable = YES;
		self.textView.horizontallyResizable = NO;

		self.textView.autoresizingMask = NSViewWidthSizable;

		self.textView.textContainer.containerSize = NSMakeSize(contentSize.width, CGFLOAT_MAX);
		self.textView.textContainer.widthTracksTextView = YES;

		scrollview.documentView = self.textView;

		[self.contentView addSubview:scrollview];


		//self.textView.autoresizesSubviews = YES;
		//self.textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		self.textView.delegate = self;
		self.textView.continuousSpellCheckingEnabled = NO;
		self.textView.automaticQuoteSubstitutionEnabled = NO;
		self.textView.enabledTextCheckingTypes = 0;
		_font = [NSFont fontWithName:@"Menlo" size:11];
		self.textView.typingAttributes = @{NSFontAttributeName: _font};

		_interpreter = new cling::Interpreter(sizeof(argv) / sizeof(*argv), argv, llvmdir);

		_interpreter->loadFile("iostream");
		_interpreter->loadFile("cocos2d.h");
		_interpreter->loadFile("cocostudio/CocoStudio.h");

		_interpreter->process("using namespace std;");
		_interpreter->process("using namespace cocos2d;");

		__block NSString *expression =
		@"auto rootNode = CSLoader::createNode(\"MainScene.csb\");\n"
		@"auto layer = Layer::create();\n"
		@"layer->addChild(rootNode);\n"
		@"auto scene = Scene::create();\n"
		@"scene->addChild(layer);\n"
		@"auto director = Director::getInstance();\n"
		@"director->runWithScene(scene);\n";

		[self processExpression:expression];

#if 1
		expression =
		@"auto sprite = Sprite::create(\"icon.png\");\n"
		@"sprite->setPosition(director->getWinSize()/2);\n"
		@"layer->addChild(sprite);\n";

		[self processExpression:expression];
#elif 0
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			expression = @"auto sprite = Sprite::create(\"icon.png\");\n";
			[self processExpression:expression];

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
				expression = @"sprite->setPosition(director->getWinSize()/2);\n";
				[self processExpression:expression];

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
					expression = @"layer->addChild(sprite);\n";
					[self processExpression:expression];
				});
			});
		});
#elif 0
		sleep(1);
		expression = @"auto sprite = Sprite::create(\"icon.png\");\n";
		[self processExpression:expression];

		sleep(1);
		expression = @"sprite->setPosition(director->getWinSize()/2);\n";
		[self processExpression:expression];

		sleep(1);
		expression = @"layer->addChild(sprite);\n";
		[self processExpression:expression];
#endif
		//self.textView.string = [NSString stringWithFormat:@"%s", expression.c_str()];

		_redirectedOutput = [[NSMutableString alloc] init];

		if( pipe( _redirectionPipe ) != -1 ) {
			_oldStandardOutput = dup( fileno(stdout) );
			_oldStandardError = dup( fileno(stderr) );
		}

		setbuf( stdout, NULL );
		setbuf( stderr, NULL );
	}

	return self;
}

- (void) dealloc {
	if( _redirecting  ) {
		[self stopRedirecting];
	}

	if( _oldStandardOutput > 0 ) {
		close( _oldStandardOutput );
	}
	if( _oldStandardError > 0 ) {
		close( _oldStandardError );
	}
	if( _redirectionPipe[READ] > 0 ) {
		close( _redirectionPipe[READ] );
	}
	if( _redirectionPipe[WRITE] > 0 ) {
		close( _redirectionPipe[WRITE] );
	}

	[super dealloc];
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

				[self textView:self.textView shouldChangeTextInRange:self.textView.selectedRange replacementString:string.string];
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
	if (!_textQueue) {
		self.textQueue = [NSMutableArray array];

		//*
		self.textQueueTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60
															   target:self
															 selector:@selector(processQueue)
															 userInfo:nil
															  repeats:YES];
		//*/

		auto scheduler = cocos2d::Director::getInstance()->getScheduler();
		scheduler->schedule([](float dt) {
			//printf(".");
		}, self, 0.0f, CC_REPEAT_FOREVER, 0.0f, false, "ProcessQueue");
	}

	id range = [NSValue valueWithRange:affectedCharRange];
	id replacement = [replacementString copy];
	[self.textQueue addObject:@[range, replacement]];
	//[self processQueue];
	return NO;
}

- (void)processQueue {
	for (NSInteger i = 0; i < self.textQueue.count; i++) {
		NSArray *element = [self.textQueue objectAtIndex:i];
		NSRange affectedCharRange = [element.firstObject rangeValue];
		NSString *replacementString = element.lastObject;

		NSString *text = self.textView.string;
		NSInteger commandLinePosition = [text rangeOfString:@"\n" options:NSBackwardsSearch].location;
		if (commandLinePosition == NSNotFound) {
			commandLinePosition = 0;
		} else {
			commandLinePosition += 1;
		}
		NSString *replacement = replacementString.copy;
		NSRange selectedRange = self.textView.selectedRange;

		//BOOL isMultiline = range.location != NSNotFound;
		BOOL inCommandLine = commandLinePosition <= affectedCharRange.location;
		BOOL hasNewline = [replacementString rangeOfString:@"\n"].location != NSNotFound;
		BOOL hasSelection = selectedRange.length > 0;
		BOOL isSingleCharacter = replacement.length <= 1;

		enum {APPEND_CHAR, APPEND_SELECTION, REPLACE_SELECTION, PASS_THROUGH} state;

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
			state = APPEND_CHAR;
		} else if (inCommandLine && !hasNewline && hasSelection) {
			state = PASS_THROUGH;
		} else if (inCommandLine && hasNewline && hasSelection) {
			state = REPLACE_SELECTION;
		}

		NSDictionary *attributes = @{NSFontAttributeName: _font};

		switch (state) {
			case APPEND_CHAR:
				[self appendString:replacement attributes:attributes];
				break;

			case APPEND_SELECTION:
				[self appendString:[self stringByRemovingLastNewline:[text substringWithRange:selectedRange]] attributes:attributes];
				break;

			case REPLACE_SELECTION:
				[self.textView.textStorage replaceCharactersInRange:selectedRange withString:replacement];
				break;

			default: //PASS_THROUGH
				if (hasSelection) {
					if (inCommandLine) {
						[self.textView.textStorage replaceCharactersInRange:selectedRange withString:replacement];
					} else {
						[self appendString:[self stringByRemovingLastNewline:replacement] attributes:attributes];
					}
				} else {
					if (isSingleCharacter) {
						[self.textView.textStorage replaceCharactersInRange:affectedCharRange withString:replacement];
					} else {
						[self.textView.textStorage replaceCharactersInRange:selectedRange withString:replacement];
					}
				}
				continue;
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
				[self startRedirecting];

				_interpreter->process(expression.UTF8String);

				[self stopRedirecting];

				NSString *result = [self output];
				if (result.length > 0 && ![result isEqualToString:@"(null)"]) {
					result = [NSString stringWithFormat:@"\n%@", [self stringByRemovingLastNewline:result]];
					[self appendString:result attributes:resultAttributes];
				}

				[self clearOutput];

				[self appendString:@"\n" attributes:attributes];
			}
		}

		// Scroll to the bottom
		self.textView.selectedRange = NSMakeRange(self.textView.string.length, 0);
		[self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
		[self.textView setNeedsDisplay:YES];
	}
	[self.textQueue removeAllObjects];
}

- (void)processExpression:(NSString *)expression {
	[self textView:self.textView shouldChangeTextInRange:NSMakeRange(self.textView.string.length, 0) replacementString:expression];
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
	if( _redirecting ) return;

	dup2( _redirectionPipe[WRITE], fileno(stdout) );
	dup2( _redirectionPipe[WRITE], fileno(stderr) );
	_redirecting = true;
}

- (void) stopRedirecting {
	if( !_redirecting ) return;

	dup2( _oldStandardOutput, fileno(stdout) );
	dup2( _oldStandardError, fileno(stderr) );
	_redirecting = false;
}

- (NSString*) output {
	const size_t bufferSize = 4096;
	char buffer[bufferSize];
	fcntl( _redirectionPipe[READ], F_SETFL, O_NONBLOCK );
	ssize_t bytesRead = read( _redirectionPipe[READ], buffer, bufferSize - 1 );
	while( bytesRead > 0 ) {
		buffer[bytesRead] = 0;
		NSString* tempString = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
		[_redirectedOutput appendString:tempString];
		bytesRead = read( _redirectionPipe[READ], buffer, bufferSize );
	}

	return [NSString stringWithFormat:@"%@", _redirectedOutput];
}

- (void) clearOutput {
	[_redirectedOutput setString:@""];
}

@end
