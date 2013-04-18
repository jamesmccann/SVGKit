#import "SVGTextElement.h"

#import <CoreText/CoreText.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "CALayerWithChildHitTest.h"
#import "SVGElement_ForParser.h" // to resolve Xcode circular dependencies; in long term, parsing SHOULD NOT HAPPEN inside any class whose name starts "SVG" (because those are reserved classes for the SVG Spec)
#import "SVGTSpanElement.h"
#import "SVGHelperUtilities.h"

@implementation SVGTextElement
{
    CGPoint _currentTextPosition;
}

@synthesize transform; // each SVGElement subclass that conforms to protocol "SVGTransformable" has to re-synthesize this to work around bugs in Apple's Objective-C 2.0 design that don't allow @properties to be extended by categories / protocols

- (void)dealloc {
    [super dealloc];
}

- (CALayer *) newLayer
{
	/**
	 BY DESIGN: we work out the positions of all text in ABSOLUTE space, and then construct the Apple CALayers and CATextLayers around
	 them, as required.
	 
	 And: SVGKit works by pre-baking everything into position (its faster, and avoids Apple's broken CALayer.transform property)
	 */
	NSString* actualSize = [self cascadedValueForStylableProperty:@"font-size"];
	NSString* actualFamily = [self cascadedValueForStylableProperty:@"font-family"];
	
	CGFloat effectiveFontSize = (actualSize.length > 0) ? [actualSize floatValue] : 12; // I chose 12. I couldn't find an official "default" value in the SVG spec.

    UIFont *font = nil;
    if (actualFamily) {
        font = [UIFont fontWithName:actualFamily size:effectiveFontSize];
    }
    if (!font) {
        font = [UIFont systemFontOfSize:effectiveFontSize];
    }
	
	CGAffineTransform textTransformAbsolute = [SVGHelperUtilities transformAbsoluteIncludingViewportForTransformableOrViewportEstablishingElement:self];

    _currentTextPosition = CGPointMake(self.x.pixelsValue, self.y.pixelsValue);

    CALayer *layer = [CALayer layer];
    [SVGHelperUtilities configureCALayer:layer usingElement:self];
    layer.bounds = CGRectMake(0, 0, 100, font.ascender); // TODO[pdr] Fix bounds when all text has been layed out
    // layer.backgroundColor = [UIColor colorWithRed:0 green:0 blue:1 alpha:0.5].CGColor;
    layer.affineTransform = textTransformAbsolute;
    CGSize ap = CGSizeMake(0, font.ascender/font.lineHeight);
    layer.anchorPoint = CGPointMake(ap.width, ap.height);
    layer.position = CGPointMake(0, 0);
    
    int nodeIndex = 0;
    int nodeCount = self.childNodes.length;
    BOOL didAddTrailingSpace = NO;
    
    for (Node *node in self.childNodes) {
        BOOL hasPreviousNode = (nodeIndex!=0);
        nodeIndex++;
        BOOL hasNextNode = (nodeIndex!=nodeCount);
        
        NSLog(@"currentTextPosition : %@", NSStringFromCGPoint(_currentTextPosition));
        NSLog(@"node.nextSibling : %@", node.nextSibling);
        switch (node.nodeType) {
            case DOMNodeType_TEXT_NODE: {
                BOOL hadLeadingSpace;
                BOOL hadTrailingSpace;
                NSString *text = [self stripText:node.textContent hadLeadingSpace:&hadLeadingSpace hadTrailingSpace:&hadTrailingSpace];
                if (hasPreviousNode && hadLeadingSpace && !didAddTrailingSpace) {
                    text = [@" " stringByAppendingString:text];
                }
                if (hasNextNode && hadTrailingSpace) {
                    text = [text stringByAppendingString:@" "];
                    didAddTrailingSpace = YES;
                } else {
                    didAddTrailingSpace = NO;
                }
                CAShapeLayer *label = [self layerWithText:text font:font];
                [SVGHelperUtilities configureCALayer:label usingElement:self];
                [SVGHelperUtilities applyStyleToShapeLayer:label withElement:self];
                [layer addSublayer:label];
                break;
            }

            case DOMNodeType_ELEMENT_NODE: {
                if ([node isKindOfClass:[SVGTSpanElement class]]) {
                    SVGTSpanElement *tspanElement = (SVGTSpanElement *)node;
                    if (tspanElement.x.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.x = tspanElement.x.pixelsValue;
                    }
                    if (tspanElement.y.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.y = tspanElement.y.pixelsValue;
                    }
                    NSString* actualSize = [tspanElement cascadedValueForStylableProperty:@"font-size"];
                    NSString* actualFamily = [tspanElement cascadedValueForStylableProperty:@"font-family"];
                    CGFloat tspanFontSize = (actualSize.length > 0) ? [actualSize floatValue] : 12; // I chose 12. I couldn't find an official "default" value in the SVG spec.
                    UIFont *tspanFont = nil;
                    if (actualFamily) {
                        tspanFont = [UIFont fontWithName:actualFamily size:tspanFontSize];
                    }
                    if (!tspanFont) {
                        tspanFont = [UIFont systemFontOfSize:tspanFontSize];
                    }
                    BOOL hadLeadingSpace;
                    BOOL hadTrailingSpace;
                    NSString *text = [self stripText:node.textContent hadLeadingSpace:&hadLeadingSpace hadTrailingSpace:&hadTrailingSpace];
                    if (hasPreviousNode && hadLeadingSpace && !didAddTrailingSpace) {
                        text = [@" " stringByAppendingString:text];
                    }
                    if (hasNextNode && hadTrailingSpace) {
                        text = [text stringByAppendingString:@" "];
                        didAddTrailingSpace = YES;
                    } else {
                        didAddTrailingSpace = NO;
                    }
                    CAShapeLayer *label = [self layerWithText:text font:tspanFont];
                    [SVGHelperUtilities configureCALayer:label usingElement:self];
                    [SVGHelperUtilities applyStyleToShapeLayer:label withElement:tspanElement];
                    // Use baseline of font to align vertically
                    CGRect b = label.bounds;
                    b.origin.y = -font.ascender-font.descender;
                    b.size.height = font.ascender;
                    label.bounds = b;
                    [layer addSublayer:label];
                    // TODO[pdr] Recurse in to child elements
                }
                break;
            }
                
            default: {
                NSLog(@"nodeType:%i", node.nodeType);
                break;
            }
        }
    }

    return [layer retain];
}

- (void)layoutLayer:(CALayer *)layer
{
    NSLog(@"layoutLayer:");
}

- (NSString *)stripText:(NSString *)text hadLeadingSpace:(BOOL *)hadLeadingSpace hadTrailingSpace:(BOOL *)hadTrailingSpace
{
    // Remove all newline characters
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    // Convert tabs into spaces
    text = [text stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    // Consolidate all contiguous space characters
    while ([text rangeOfString:@"  "].location != NSNotFound) {
        text = [text stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    if (hadLeadingSpace) {
        *hadLeadingSpace = (text.length==0 ? NO : [[text substringWithRange:NSMakeRange(0, 1)] isEqualToString:@" "]);
    }
    if (hadTrailingSpace) {
        *hadTrailingSpace = (text.length==0 ? NO : [[text substringFromIndex:text.length-1] isEqualToString:@" "]);
    }
    // Remove leading and trailing spaces
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return text;
}

#pragma mark -

- (CAShapeLayer *)layerWithText:(NSString *)text font:(UIFont *)font
{
    CAShapeLayer *label = [CAShapeLayer layer];
    label.anchorPoint = CGPointZero;
    label.position = _currentTextPosition;
    // Create path from the text
    UIBezierPath *textPath = [self bezierPathWithString:text font:font inRect:CGRectMake(0, 0, FLT_MAX, FLT_MAX)];
    label.path = textPath.CGPath;
    // Use font baseline for alignment
    CGRect b = textPath.bounds;
    b.origin.x = 0;
    b.origin.y = -font.ascender-font.descender;
    b.size.height = font.ascender;
    label.bounds = b;
    //label.borderColor = [UIColor redColor].CGColor;
    //label.borderWidth = 1;
    NSLog(@"text:'%@' => %@", text, NSStringFromCGRect(label.bounds));
    return label;
}


// Requires CoreText.framework
// This creates a graphical version of the input screen, line wrapped to the input rect.
// Core Text involves a whole hierarchy of objects, all requiring manual management.
- (UIBezierPath*) bezierPathWithString:(NSString*) string font:(UIFont*) font inRect:(CGRect) rect;
{
    UIBezierPath *combinedGlyphsPath = nil;
    CGMutablePathRef combinedGlyphsPathRef = CGPathCreateMutable();
    if (combinedGlyphsPathRef)
    {
        // It would be easy to wrap the text into a different shape, including arbitrary bezier paths, if needed.
        UIBezierPath *frameShape = [UIBezierPath bezierPathWithRect:rect];
        
        // If the font name wasn't found while creating the font object, the result is a crash.
        // Avoid this by falling back to the system font.
        CTFontRef fontRef;
        if ([font fontName])
            fontRef = CTFontCreateWithName((__bridge CFStringRef) [font fontName], [font pointSize], NULL);
        else if (font)
            fontRef = CTFontCreateUIFontForLanguage(kCTFontUserFontType, [font pointSize], NULL);
        else
            fontRef = CTFontCreateUIFontForLanguage(kCTFontUserFontType, [UIFont systemFontSize], NULL);
        
        if (fontRef)
        {
            CGPoint basePoint = CGPointMake(_currentTextPosition.x, CTFontGetAscent(fontRef));
            CFStringRef keys[] = { kCTFontAttributeName };
            CFTypeRef values[] = { fontRef };
            CFDictionaryRef attributesRef = CFDictionaryCreate(NULL, (const void **)&keys, (const void **)&values,
                                                               sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            
            if (attributesRef)
            {
                CFAttributedStringRef attributedStringRef = CFAttributedStringCreate(NULL, (__bridge CFStringRef) string, attributesRef);
                
                if (attributedStringRef)
                {
                    CTFramesetterRef frameSetterRef = CTFramesetterCreateWithAttributedString(attributedStringRef);
                    
                    if (frameSetterRef)
                    {
                        CTFrameRef frameRef = CTFramesetterCreateFrame(frameSetterRef, CFRangeMake(0,0), [frameShape CGPath], NULL);
                        
                        if (frameRef)
                        {
                            CFArrayRef lines = CTFrameGetLines(frameRef);
                            CFIndex lineCount = CFArrayGetCount(lines);
                            CGPoint lineOrigins[lineCount];
                            CTFrameGetLineOrigins(frameRef, CFRangeMake(0, lineCount), lineOrigins);
                            
                            for (CFIndex lineIndex = 0; lineIndex<lineCount; lineIndex++)
                            {
                                CTLineRef lineRef = CFArrayGetValueAtIndex(lines, lineIndex);
                                CGPoint lineOrigin = lineOrigins[lineIndex];
                                
                                CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
                                
                                CFIndex runCount = CFArrayGetCount(runs);
                                for (CFIndex runIndex = 0; runIndex<runCount; runIndex++)
                                {
                                    CTRunRef runRef = CFArrayGetValueAtIndex(runs, runIndex);
                                    
                                    CFIndex glyphCount = CTRunGetGlyphCount(runRef);
                                    CGGlyph glyphs[glyphCount];
                                    CGSize glyphAdvances[glyphCount];
                                    CGPoint glyphPositions[glyphCount];
                                    
                                    CFRange runRange = CFRangeMake(0, glyphCount);
                                    CTRunGetGlyphs(runRef, CFRangeMake(0, glyphCount), glyphs);
                                    CTRunGetPositions(runRef, runRange, glyphPositions);
                                    
                                    CTFontGetAdvancesForGlyphs(fontRef, kCTFontDefaultOrientation, glyphs, glyphAdvances, glyphCount);
                                    
                                    for (CFIndex glyphIndex = 0; glyphIndex<glyphCount; glyphIndex++)
                                    {
                                        CGGlyph glyph = glyphs[glyphIndex];
                                        
                                        // For regular UIBezierPath drawing, we need to invert around the y axis.
                                        CGAffineTransform glyphTransform = CGAffineTransformMakeTranslation(lineOrigin.x+glyphPositions[glyphIndex].x, rect.size.height-lineOrigin.y-glyphPositions[glyphIndex].y);
                                        glyphTransform = CGAffineTransformScale(glyphTransform, 1, -1);
                                        // TODO[pdr] Idea for handling rotate: glyphTransform = CGAffineTransformRotate(glyphTransform, M_PI/8);
                                        
                                        CGPathRef glyphPathRef = CTFontCreatePathForGlyph(fontRef, glyph, &glyphTransform);
                                        if (glyphPathRef)
                                        {
                                            // Finally carry out the appending.
                                            CGPathAddPath(combinedGlyphsPathRef, NULL, glyphPathRef);
                                            CFRelease(glyphPathRef);
                                        }
                                        
                                        basePoint.x += glyphAdvances[glyphIndex].width;
                                        basePoint.y += glyphAdvances[glyphIndex].height;
                                        NSLog(@"'%@' => %@", [string substringWithRange:NSMakeRange(glyphIndex, 1)], NSStringFromCGPoint(basePoint));
                                    }
                                }
                                _currentTextPosition.x = basePoint.x; // TODO[pdr]
                                // TODO[pdr] Only one line
                                basePoint.x = 0;
                                basePoint.y += CTFontGetAscent(fontRef) + CTFontGetDescent(fontRef) + CTFontGetLeading(fontRef);
                            }
                            
                            CFRelease(frameRef);
                        }
                        
                        CFRelease(frameSetterRef);
                    }
                    CFRelease(attributedStringRef);
                }
                CFRelease(attributesRef);
            }
            CFRelease(fontRef);
        }
        // Casting a CGMutablePathRef to a CGPathRef seems to be the only way to convert what was just built into a UIBezierPath.
        combinedGlyphsPath = [UIBezierPath bezierPathWithCGPath:(CGPathRef) combinedGlyphsPathRef];
        
        CGPathRelease(combinedGlyphsPathRef);
    }
    return combinedGlyphsPath;
}

@end
