//  Copyright (c) 2007 Dorian Johnson <arcadiclife@gmail.com>
//  Permission is hereby granted, free of charge, to any person obtaining a 
//  copy of this software and associated documentation files (the "Software"), 
//  to deal in the Software without restriction, including without limitation 
//  the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//  and/or sell copies of the Software, and to permit persons to whom the 
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in 
//  all copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN 
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

/*	Notes:
		- I could have used CoreGraphics for the gradients. Drawing my own was easier.
			It's the same exact result: a calculated gradient.
*/

#import "CRDServerList.h"
#import "miscellany.h"
#import "CRDServerCell.h"
#import "RDInstance.h"

// For mainWindowIsFocused
#import "AppController.h"


// Start is top, end is bottom
#define HIGHLIGHT_START [NSColor colorWithDeviceRed:(66/255.0) green:(154/255.0) blue:(227/255.0) alpha:1.0]
#define HIGHLIGHT_END [NSColor colorWithDeviceRed:(25/255.0) green:(85/255.0) blue:(205/255.0) alpha:1.0]

#define UNFOCUSED_START [NSColor colorWithDeviceRed:(150/255.0) green:(150/255.0) blue:(150/255.0) alpha:1.0]
#define UNFOCUSED_END [NSColor colorWithDeviceRed:(100/255.0) green:(100/255.0) blue:(100/255.0) alpha:1.0]

#define ANIMATION_DURATION 0.15

#pragma mark -

@interface CRDServerList (Private)
	- (NSString *)pasteboardDataType:(NSPasteboard *)draggingPasteboard;
	- (BOOL)pasteboardHasValidData:(NSPasteboard *)draggingPasteboard;
	- (void)createNewRowOriginsAboveRow:(int)rowIndex;
	- (void)startAnimation;
	- (void)concludeDrag;
@end


#pragma mark -
@implementation CRDServerList

#pragma mark -
#pragma mark NSTableView

- (void)awakeFromNib
{
	emptyRowIndex = -1;
}

// If this isn't overridden, it won't use the hightlightSelectionInClipRect method
- (id)_highlightColorForCell:(NSCell *)cell
{
	return nil;
}

- (void)highlightSelectionInClipRect:(NSRect)clipRect
{	
	int selectedRow = [self selectedRow];
	if (selectedRow == -1)
		return;
	
	RDInstance *inst = [g_appController serverInstanceForRow:selectedRow];
	NSRect drawRect = [self rectOfRow:selectedRow];
	
	NSColor *topColor, *bottomColor;
	if ([g_appController mainWindowIsFocused])
	{
		topColor = HIGHLIGHT_START;
		bottomColor = HIGHLIGHT_END;
	} else {
		topColor = UNFOCUSED_START;
		bottomColor = UNFOCUSED_END;	
	}
	
	[self lockFocus];	
	NSRectClip(drawRect);
	draw_vertical_gradient(topColor, bottomColor, drawRect);
	draw_line([bottomColor blendedColorWithFraction:0.6 ofColor:topColor], 
			NSMakePoint(drawRect.origin.x, drawRect.origin.y),
			NSMakePoint(drawRect.origin.x + drawRect.size.width, drawRect.origin.y ));
	[self unlockFocus];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	int selectedRow, i, count;
	
	selectedRow = (indexes != nil) ? [indexes firstIndex] : -1;

	for (i = 0, count = [self numberOfRows]; i < count; i++)
		[[[[self tableColumns] objectAtIndex:0] dataCellForRow:i] setHighlighted:(i == selectedRow)];

	[super selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
	[self setNeedsDisplay:YES];
}

- (void)selectRow:(int)index
{
	if (index > -1 && [[self delegate] tableView:self shouldSelectRow:index])
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(unsigned)index] byExtendingSelection:NO];
	else
		[self deselectAll:self];
}

- (void)deselectRow:(int)rowIndex
{
	if (rowIndex != -1)
		[[[[self tableColumns] objectAtIndex:0] dataCellForRow:rowIndex] setHighlighted:NO];
}

- (void)deselectAll:(id)sender
{
	[self selectRowIndexes:nil byExtendingSelection:NO];
	[super deselectAll:sender];
}


#pragma mark -
#pragma mark NSResponder

- (void)keyDown:(NSEvent *)ev
{
	NSString *str = [ev charactersIgnoringModifiers];
	
	if ([str length] == 1)
	{
		switch ([str characterAtIndex:0])
		{
			case NSDeleteFunctionKey:
			case 0x007f: /* backward delete */
				[g_appController removeSelectedSavedServer:self];
				return;
				break;
			
			case 0x0003: // return
			case 0x000d: // numpad enter
				[g_appController connect:self];
				return;
				break;
				
			default:
				break;
		}
	}
	
	[super keyDown:ev];
}

- (void)mouseDown:(NSEvent *)ev
{
	int row = [self rowAtPoint:[self convertPoint:[ev locationInWindow] fromView:nil]];
	if ([ev clickCount] == 2 && row == [self selectedRow])
	{
		[g_appController connect:self];
		return;
	}
	else
	{
		[self selectRow:row];
	}

	// Don't call super so that it performs click-through selection
}

// Assure that the row the right click is over is selected so that the context menu is correct
- (void)rightMouseDown:(NSEvent *)ev
{
	int row = [self rowAtPoint:[self convertPoint:[ev locationInWindow] fromView:nil]];
	if (row != -1)
		[self selectRow:row];
		
	[super rightMouseDown:ev];
}

- (NSRect)rectOfRow:(int)rowIndex
{
	
	NSRect realRect = [super rectOfRow:rowIndex];
	

	
	if ((rowIndex != -1) && (autoexpansionCurrentRowOrigins != nil))
	{
		signed q = (rowIndex >= emptyRowIndex) ? 1 : -1;
		realRect.origin = [[autoexpansionCurrentRowOrigins objectAtIndex:rowIndex] pointValue];
		/*
		if ( (q == -1) && (rowIndex < emptyRowIndex) && (rowIndex >= oldEmptyRowIndex) )
		{
			realRect.origin = [[autoexpansionCurrentRowOrigins objectAtIndex:rowIndex-oldEmptyRowIndex] pointValue];
		//	NSLog(@"rectOfRow for %d, q=%d, old=%d, new=%d, used=%d", rowIndex, q, oldEmptyRowIndex, emptyRowIndex, rowIndex-oldEmptyRowIndex);
		}
		else if ( (q == 1) && (rowIndex >= emptyRowIndex) && (rowIndex < oldEmptyRowIndex) )
		{
			realRect.origin = [[autoexpansionCurrentRowOrigins objectAtIndex:oldEmptyRowIndex-rowIndex] pointValue];
			//NSLog(@"rectOfRow for %d, q=%d, old=%d, new=%d, used=%d", rowIndex, q, oldEmptyRowIndex, emptyRowIndex, oldEmptyRowIndex-rowIndex);
		}	*/
	}
	
	return realRect;
}


#pragma mark -
#pragma mark NSDraggingDestination

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	return [self draggingUpdated:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	// todo: if the destination is one of the labels, return NSDragOperationNone
	
	int row = [self rowAtPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
	NSDragOperation retOperation;
		
	if ([sender draggingSource] == self)
		retOperation = NSDragOperationMove;
	else if ([[[[self tableColumns] objectAtIndex:0] dataCellForRow:row] isKindOfClass:[CRDLabelCell class]])
		return retOperation = NSDragOperationNone;
	else
		retOperation = NSDragOperationCopy;
	
	if (row != emptyRowIndex || (row >= [self numberOfRows] && oldEmptyRowIndex != [self numberOfRows] && oldEmptyRowIndex != -1) )
	{
		[self createNewRowOriginsAboveRow:row];
		[self startAnimation];
	}

	return retOperation;
}


- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	[self concludeDrag];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	[self concludeDrag];
	return NO;//[self pasteboardHasValidData:[sender draggingPasteboard]];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	
	return NO;//[self pasteboardHasValidData:[sender draggingPasteboard]];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	[self concludeDrag];
}


- (BOOL)wantsPeriodicDraggingUpdates
{
	return YES;
}




#pragma mark -
#pragma mark Dragging internal use

- (NSString *)pasteboardDataType:(NSPasteboard *)draggingPasteboard
{
	NSArray *supportedTypes = [NSArray arrayWithObjects:SAVED_SERVER_DRAG_TYPE,
			NSFilenamesPboardType, NSFilesPromisePboardType, nil];
			
	return [draggingPasteboard availableTypeFromArray:supportedTypes];
}

- (BOOL)pasteboardHasValidData:(NSPasteboard *)draggingPasteboard
{
	return [self pasteboardDataType:draggingPasteboard] != nil;
}

- (void)startAnimation
{
	if (autoexpansionAnimation != nil)
	{
		[autoexpansionAnimation stopAnimation];
		[autoexpansionAnimation release];
	}

	float frameRate = 30.0;
	
	autoexpansionAnimation = [[NSAnimation alloc] initWithDuration:ANIMATION_DURATION
			animationCurve:NSAnimationLinear];
			
	[autoexpansionAnimation setFrameRate:frameRate];
	[autoexpansionAnimation setAnimationBlockingMode:NSAnimationNonblocking];
	[autoexpansionAnimation setDelegate:self];
	
	// Make sure animation:didReachProgressMark: gets called on each frame	
	for (int i = 0; i < (int)frameRate; i++)
		[autoexpansionAnimation addProgressMark:(i / frameRate)];
		
	[autoexpansionAnimation startAnimation];
}

- (void)createNewRowOriginsAboveRow:(int)rowIndex
{
	if (emptyRowIndex == rowIndex || rowIndex == -1) 
		return;
		
	oldEmptyRowIndex = (emptyRowIndex == -1) ? [self numberOfRows] : emptyRowIndex;
	emptyRowIndex = rowIndex;
	
	int numRows = [self numberOfRows], i;
	float delta = [super rectOfRow:rowIndex].size.height;

	NSRect realRowRect;
	NSPoint realRowOrigin, startRowOrigin, endRowOrigin;
	NSMutableArray *endBuilder = [NSMutableArray arrayWithCapacity:numRows-emptyRowIndex];
	NSMutableArray *startBuilder = [NSMutableArray arrayWithCapacity:numRows-emptyRowIndex];

	// If the new empty is lower, start at the current empty and move down. Otherwise,
	//	start at the current empty and move up
	signed q = (emptyRowIndex >= oldEmptyRowIndex) ? 1 : -1;
	
	NSLog(@"Starting for %d, q=%d, old=%d, delta=%f", rowIndex, q, oldEmptyRowIndex, delta);
	
	for (i = 0; i < numRows; i++)
	{
		realRowOrigin = [super rectOfRow:i].origin;
		[startBuilder addObject:[NSValue valueWithPoint:realRowOrigin]];
		[endBuilder addObject:[NSValue valueWithPoint:realRowOrigin]];
	}
	
	for (i = MIN(oldEmptyRowIndex, numRows-1); i != emptyRowIndex+q; i += q)
	{
		// Find the end origin by adding the delta to the original row origin
		realRowOrigin = [super rectOfRow:i].origin;
		
		if (autoexpansionCurrentRowOrigins != nil)
			startRowOrigin = [self rectOfRow:i].origin;
		else
			startRowOrigin = realRowOrigin;
			
		endRowOrigin = realRowOrigin;
		endRowOrigin.y += delta *  -q;
		
		[startBuilder replaceObjectAtIndex:i withObject:[NSValue valueWithPoint:startRowOrigin]];
		[endBuilder replaceObjectAtIndex:i withObject:[NSValue valueWithPoint:endRowOrigin]];
		
		NSLog(@"Adding... %d", i);
		PRINT_POINT(@"start", startRowOrigin);
		PRINT_POINT(@"end", endRowOrigin);
	}
	
	NSLog(@"---");
	
	[autoexpansionStartRowOrigins release];
	[autoexpansionEndRowOrigins release];
	
	autoexpansionStartRowOrigins = [startBuilder retain];
	autoexpansionEndRowOrigins = [endBuilder retain];
}

- (void)concludeDrag
{
	[autoexpansionCurrentRowOrigins release];
	[autoexpansionEndRowOrigins release];
	[autoexpansionCurrentRowOrigins release];
	autoexpansionCurrentRowOrigins = autoexpansionEndRowOrigins = autoexpansionStartRowOrigins = nil;
	
	[autoexpansionAnimation stopAnimation];
	[autoexpansionAnimation release];
	autoexpansionAnimation = nil;
	
	emptyRowIndex = oldEmptyRowIndex = -1;
	inLiveDrag = NO;
	
	// todo: animate items moving back to original place
	[self setNeedsDisplay];
}


#pragma mark -
#pragma mark NSAnimation delegate

- (void)animation:(NSAnimation*)animation didReachProgressMark:(NSAnimationProgress)progress
{
	// Create new autoexpansionCurrentRowOrigins by convolving the start origins to the end
	float fraction = [animation currentValue];

	NSMutableArray *currentPointsBuilder = [[NSMutableArray alloc] init];
	
	NSEnumerator *startEnum = [autoexpansionStartRowOrigins objectEnumerator],
			*endEnum = [autoexpansionEndRowOrigins objectEnumerator];
	id startValue, endValue;
	NSPoint convolvedPoint, startOrigin, endOrigin;
		
	while ( (startValue = [startEnum nextObject]) && (endValue = [endEnum nextObject]))
	{
		startOrigin = [startValue pointValue];
		endOrigin = [endValue pointValue];
		convolvedPoint = NSMakePoint(startOrigin.x * (1.0 - fraction) + endOrigin.x * fraction,
									 startOrigin.y * (1.0 - fraction) + endOrigin.y * fraction);
		
		//NSLog(@"Convolving %f,%f to %f,%f with fraction %f", startOrigin.x, startOrigin.y, endOrigin.x, endOrigin.y, fraction);
		
		[currentPointsBuilder addObject:[NSValue valueWithPoint:convolvedPoint]];
	}
	
	[autoexpansionCurrentRowOrigins release];
	autoexpansionCurrentRowOrigins = [currentPointsBuilder retain];
	
	[self setNeedsDisplay:YES];
}


- (void)animationDidEnd:(NSAnimation*)animation
{
	oldEmptyRowIndex = -1;
}


@end



