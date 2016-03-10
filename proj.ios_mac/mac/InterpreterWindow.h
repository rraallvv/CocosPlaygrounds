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
	cling::Interpreter *_interpreter;
}

@property (nonatomic, strong) IBOutlet NSTextView *textView;

- (void)exportToInterpreter:(const std::string)typeName name:(std::string)name object:(void *)object;

@end
