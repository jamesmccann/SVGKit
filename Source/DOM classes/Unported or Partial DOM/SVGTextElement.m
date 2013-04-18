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
    CTFontRef _baseFont;
	CGFloat _baseFontAscent;
    CGFloat _baseFontDescent;
    CGFloat _baseFontLeading;
    CGFloat _baseFontLineHeight;
    BOOL _didAddTrailingSpace;
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
	CGAffineTransform textTransformAbsolute = [SVGHelperUtilities transformAbsoluteIncludingViewportForTransformableOrViewportEstablishingElement:self];

    // Set up the text elements base font
    _baseFont = [self newFontFromElement:self];
	_baseFontAscent = CTFontGetAscent(_baseFont);
    _baseFontDescent = CTFontGetDescent(_baseFont);
    _baseFontLeading = CTFontGetLeading(_baseFont);
    _baseFontLineHeight = _baseFontAscent + _baseFontDescent + _baseFontLeading;

    // Set up the main layer to put text in to
    CALayer *layer = [CALayer layer];
    [SVGHelperUtilities configureCALayer:layer usingElement:self];
    layer.bounds = CGRectMake(0, 0, 100, _baseFontAscent); // TODO[pdr] Fix bounds when all text has been layed out
    // layer.backgroundColor = [UIColor colorWithRed:0 green:0 blue:1 alpha:0.5].CGColor;
    layer.affineTransform = textTransformAbsolute;
    CGSize ap = CGSizeMake(0, _baseFontAscent/_baseFontLineHeight);
    layer.anchorPoint = CGPointMake(ap.width, ap.height);
    layer.position = CGPointMake(0, 0);

    // Add sublayers for the text elements
    _currentTextPosition = CGPointMake(self.x.pixelsValue, self.y.pixelsValue);
    _didAddTrailingSpace = NO;
    [self addLayersForElement:self toLayer:layer];
    
    CFRelease(_baseFont);
    _baseFont = NULL;

    return [layer retain];
}

- (void)layoutLayer:(CALayer *)layer
{
}

- (void)addLayersForElement:(SVGElement *)element toLayer:(CALayer *)layer
{
    int nodeIndex = 0;
    int nodeCount = self.childNodes.length;

    CTFontRef font = [self newFontFromElement:element];

    for (Node *node in element.childNodes) {
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
                if (hasPreviousNode && hadLeadingSpace && !_didAddTrailingSpace) {
                    text = [@" " stringByAppendingString:text];
                }
                if (hasNextNode && hadTrailingSpace) {
                    text = [text stringByAppendingString:@" "];
                    _didAddTrailingSpace = YES;
                } else {
                    _didAddTrailingSpace = NO;
                }
                CAShapeLayer *label = [self layerWithText:text font:font];
                [SVGHelperUtilities configureCALayer:label usingElement:element];
                [SVGHelperUtilities applyStyleToShapeLayer:label withElement:element];
                [layer addSublayer:label];
                break;
            }
                
            case DOMNodeType_ELEMENT_NODE: {
                if ([node isKindOfClass:[SVGTSpanElement class]]) {
                    SVGTSpanElement *tspanElement = (SVGTSpanElement *)node;
                    if (tspanElement.x.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.x = [self pixelValueForLength:tspanElement.x withFont:font];
                    }
                    if (tspanElement.y.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.y = [self pixelValueForLength:tspanElement.y withFont:font];
                    }
                    if (tspanElement.dx.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.x += [self pixelValueForLength:tspanElement.dx withFont:font];
                    }
                    if (tspanElement.dy.unitType!=SVG_LENGTHTYPE_UNKNOWN) {
                        _currentTextPosition.y += [self pixelValueForLength:tspanElement.dy withFont:font];
                    }
                    [self addLayersForElement:tspanElement toLayer:layer];
                }
                break;
            }
                
            default:
                break;
        }
    }
    CFRelease(font);
}

- (CGFloat)pixelValueForLength:(SVGLength *)length withFont:(CTFontRef)font
{
    if (length.unitType==SVG_LENGTHTYPE_EMS) {
        return length.value*CTFontGetSize(font);
    } else {
        return length.pixelsValue;
    }
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

- (CTFontRef)newFontFromElement:(SVGElement<SVGStylable> *)element
{
	NSString *fontSize = [element cascadedValueForStylableProperty:@"font-size"];
	NSString *fontFamily = [element cascadedValueForStylableProperty:@"font-family"];
    NSString *fontWeight = [element cascadedValueForStylableProperty:@"font-weight"];
	
	CGFloat effectiveFontSize = (fontSize.length > 0) ? [fontSize floatValue] : 12; // I chose 12. I couldn't find an official "default" value in the SVG spec.

    CTFontRef fontRef = NULL;
    if (fontFamily) {
        fontRef = CTFontCreateWithName((CFStringRef)fontFamily, effectiveFontSize, NULL);
    }
    if (!fontRef) {
        fontRef = CTFontCreateUIFontForLanguage(kCTFontUserFontType, effectiveFontSize, NULL);
    }
    if (fontWeight) {
        BOOL bold = [fontWeight isEqualToString:@"bold"];
        if (bold) {
            CTFontRef boldFontRef = CTFontCreateCopyWithSymbolicTraits(fontRef, effectiveFontSize, NULL, kCTFontBoldTrait, kCTFontBoldTrait);
            if (boldFontRef) {
                CFRelease(fontRef);
                fontRef = boldFontRef;
            }
        }
    }
    return fontRef;
}


#pragma mark -

- (CAShapeLayer *)layerWithText:(NSString *)text font:(CTFontRef)font
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
    b.origin.y = -_baseFontAscent+_baseFontDescent;
    b.size.height = _baseFontAscent;
    label.bounds = b;
    //label.borderColor = [UIColor redColor].CGColor;
    //label.borderWidth = 1;
    NSLog(@"text:'%@' => %@", text, NSStringFromCGRect(label.bounds));
    return label;
}


// Requires CoreText.framework
// This creates a graphical version of the input screen, line wrapped to the input rect.
// Core Text involves a whole hierarchy of objects, all requiring manual management.
- (UIBezierPath*)bezierPathWithString:(NSString*)string font:(CTFontRef)fontRef inRect:(CGRect)rect;
{
    UIBezierPath *combinedGlyphsPath = nil;
    CGMutablePathRef combinedGlyphsPathRef = CGPathCreateMutable();
    if (combinedGlyphsPathRef)
    {
        // It would be easy to wrap the text into a different shape, including arbitrary bezier paths, if needed.
        UIBezierPath *frameShape = [UIBezierPath bezierPathWithRect:rect];
        
        CGPoint basePoint = CGPointMake(_currentTextPosition.x, CTFontGetAscent(fontRef));
        CFStringRef keys[] = { kCTFontAttributeName };
        CFTypeRef values[] = { fontRef };
        CFDictionaryRef attributesRef = CFDictionaryCreate(NULL, (const void **)&keys, (const void **)&values,
                                                           sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        if (attributesRef)
        {
            CFAttributedStringRef attributedStringRef = CFAttributedStringCreate(NULL, (CFStringRef) string, attributesRef);
            
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

        // Casting a CGMutablePathRef to a CGPathRef seems to be the only way to convert what was just built into a UIBezierPath.
        combinedGlyphsPath = [UIBezierPath bezierPathWithCGPath:(CGPathRef) combinedGlyphsPathRef];
    
        CGPathRelease(combinedGlyphsPathRef);
    }
    return combinedGlyphsPath;
}

@end
