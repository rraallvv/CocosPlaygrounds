//
//  InterpreterWindow.h
//  CocosPlaygrounds
//
//  Created by Rhody Lugo on 3/9/16.
//
//

#import <Cocoa/Cocoa.h>
#include "cling/Interpreter/Interpreter.h"

@interface InterpreterWindow : NSWindow <NSTextViewDelegate> {
@private
	cling::Interpreter *_interpreter;
	NSFont *_font;
	int redirectionPipe[2];
	int oldStandardOutput;
	int oldStandardError;
	BOOL redirecting;
	NSMutableString* redirectedOutput;
}

@property (nonatomic, strong) IBOutlet NSTextView *textView;

- (void)exportToInterpreter:(const std::string)typeName name:(std::string)name object:(void *)object;

- (void) startRedirecting;
- (void) stopRedirecting;
- (NSString*) output;
- (void) clearOutput;

@end
