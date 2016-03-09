//
//  InterpreterWindow.m
//  CocosPlaygrounds
//
//  Created by Rhody Lugo on 3/9/16.
//
//

#import "InterpreterWindow.h"

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

@end
