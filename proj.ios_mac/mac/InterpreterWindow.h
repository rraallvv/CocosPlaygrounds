//
//  InterpreterWindow.h
//  CocosPlaygrounds
//
//  Created by Rhody Lugo on 3/9/16.
//
//

#import <Cocoa/Cocoa.h>

@interface InterpreterWindow : NSWindow <NSTextViewDelegate>

@property (nonatomic, strong) IBOutlet NSTextView *textView;

@end
