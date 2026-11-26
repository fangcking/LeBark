#import "TSWebTap.h"

#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const CGFloat TSWebTapMinAlpha = 0.01;
static BOOL gTSWebTapVerbose = NO;

void TSWebTapSetVerbose(BOOL verbose) {
    gTSWebTapVerbose = verbose;
}

static BOOL TSWebViewIsVisible(UIView *view) {
    return !view.hidden && view.alpha > TSWebTapMinAlpha && view.userInteractionEnabled;
}

// Walks subviews front to back (the last subview draws on top) and returns the
// first web view whose bounds contain the point, expressed in `root` coordinates.
static UIView *TSWebViewInSubtree(UIView *root, CGPoint pointInRoot) {
    Class webViewClass = (Class)objc_getClass("WKWebView");
    Class legacyClass = (Class)objc_getClass("UIWebView");
    NSArray<UIView *> *subviews = root.subviews;
    for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
        UIView *subview = subviews[i];
        if (!TSWebViewIsVisible(subview)) {
            continue;
        }
        CGPoint point = [subview convertPoint:pointInRoot fromView:root];
        if (!CGRectContainsPoint(subview.bounds, point)) {
            continue;
        }
        if ((webViewClass && [subview isKindOfClass:webViewClass]) ||
            (legacyClass && [subview isKindOfClass:legacyClass])) {
            return subview;
        }
        UIView *found = TSWebViewInSubtree(subview, point);
        if (found) {
            return found;
        }
    }
    return nil;
}

static UIView *TSFindWebViewAtScreenPoint(CGPoint screenPoint) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
    NSArray<UIWindow *> *sorted = [windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel) {
            return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    for (UIWindow *window in sorted) {
        if (window.hidden || window.alpha <= TSWebTapMinAlpha) {
            continue;
        }
        CGPoint point = [window.screen.coordinateSpace convertPoint:screenPoint toCoordinateSpace:window.coordinateSpace];
        if (!CGRectContainsPoint(window.bounds, point)) {
            continue;
        }
        UIView *found = TSWebViewInSubtree(window, point);
        if (found) {
            return found;
        }
    }
    return nil;
}

static UIView *TSWebViewAncestor(UIView *view) {
    Class webViewClass = (Class)objc_getClass("WKWebView");
    Class legacyClass = (Class)objc_getClass("UIWebView");
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        if ((webViewClass && [candidate isKindOfClass:webViewClass]) ||
            (legacyClass && [candidate isKindOfClass:legacyClass])) {
            return candidate;
        }
    }
    return nil;
}

BOOL TSViewHasWebViewAncestor(UIView *view) {
    return TSWebViewAncestor(view) != nil;
}

// Screen point -> page CSS coordinates. A web view's own bounds are in points,
// while the DOM works in unzoomed layout units, so undo scrolling and zoom.
static CGPoint TSCSSPointInWebView(UIView *webView, CGPoint screenPoint) {
    UIWindow *window = webView.window;
    if (!window) {
        return screenPoint;
    }
    CGPoint windowPoint = [window.screen.coordinateSpace convertPoint:screenPoint toCoordinateSpace:window.coordinateSpace];
    CGPoint local = [webView convertPoint:windowPoint fromView:window];

    UIScrollView *scrollView = nil;
    Class webViewClass = (Class)objc_getClass("WKWebView");
    if (webViewClass && [webView isKindOfClass:webViewClass]) {
        scrollView = ((WKWebView *)webView).scrollView;
    } else if ([webView respondsToSelector:@selector(scrollView)]) {
        scrollView = ((id (*)(id, SEL))objc_msgSend)(webView, @selector(scrollView));
    }
    if (!scrollView) {
        return local;
    }
    CGFloat zoom = scrollView.zoomScale > 0 ? scrollView.zoomScale : 1.0;
    CGPoint offset = scrollView.contentOffset;
    return CGPointMake((local.x + offset.x) / zoom, (local.y + offset.y) / zoom);
}

// Resolves the topmost element that actually accepts pointer events, nudges up
// to the nearest clickable ancestor, then fires every event family a page may
// listen on: touch, pointer, mouse and click. Same-origin iframes are entered
// because payment pages often host the actionable part in one.
static NSString *TSWebTapScript(CGFloat x, CGFloat y) {
    static NSString *const kTemplate =
        @"(function(){"
        "try{"
        "var X=%.2f,Y=%.2f;"
        "function pick(doc,x,y){"
        "var list=[];"
        "if(doc.elementsFromPoint){list=doc.elementsFromPoint(x,y)||[];}"
        "else{var one=doc.elementFromPoint(x,y);if(one){list=[one];}}"
        "for(var i=0;i<list.length;i++){"
        "var n=list[i];"
        "if(!n||n.tagName==='HTML'){continue;}"
        "var cs=null;"
        "try{cs=(doc.defaultView||window).getComputedStyle(n);}catch(e){}"
        "if(cs&&cs.pointerEvents==='none'){continue;}"
        "return n;"
        "}"
        "return list.length?list[0]:null;"
        "}"
        "function clickable(el){"
        "var t=el;"
        "var body=el.ownerDocument?el.ownerDocument.body:null;"
        "for(var i=0;i<8&&t&&t!==body&&t!==(el.ownerDocument?el.ownerDocument.documentElement:null);i++){"
        "var tag=t.tagName;"
        "var attr=t.getAttribute&&(t.getAttribute('onclick')||t.getAttribute('data-url')||t.getAttribute('data-href'));"
        "if(tag==='A'||tag==='BUTTON'||tag==='INPUT'||tag==='LABEL'||t.onclick||attr){return t;}"
        "t=t.parentElement;"
        "}"
        "return el;"
        "}"
        "function fire(el,doc,x,y){"
        "var target=clickable(el);"
        "var win=doc.defaultView||window;"
        "function mk(type,Ctor,extra){"
        "var o={bubbles:true,cancelable:true,composed:true,view:win,"
        "clientX:x,clientY:y,pageX:x,pageY:y,screenX:x,screenY:y,button:0,buttons:1};"
        "if(extra){for(var k in extra){o[k]=extra[k];}}"
        "return new Ctor(type,o);"
        "}"
        "var touchOk=false;"
        "try{"
        "if(typeof win.Touch==='function'&&typeof win.TouchEvent==='function'){"
        "var t=new win.Touch({identifier:1,target:target,clientX:x,clientY:y,pageX:x,pageY:y,"
        "screenX:x,screenY:y,radiusX:2,radiusY:2,force:1});"
        "target.dispatchEvent(mk('touchstart',win.TouchEvent,{touches:[t],targetTouches:[t],changedTouches:[t]}));"
        "target.dispatchEvent(mk('touchend',win.TouchEvent,{touches:[],targetTouches:[],changedTouches:[t]}));"
        "touchOk=true;"
        "}"
        "}catch(te){}"
        "try{"
        "if(typeof win.PointerEvent==='function'){"
        "target.dispatchEvent(mk('pointerdown',win.PointerEvent,{pointerType:'touch',isPrimary:true,pointerId:1}));"
        "target.dispatchEvent(mk('pointerup',win.PointerEvent,{pointerType:'touch',isPrimary:true,pointerId:1,buttons:0}));"
        "}"
        "}catch(pe){}"
        "target.dispatchEvent(mk('mousedown',win.MouseEvent,{buttons:1}));"
        "target.dispatchEvent(mk('mouseup',win.MouseEvent,{buttons:0}));"
        "target.dispatchEvent(mk('click',win.MouseEvent,{buttons:0}));"
        "var name=(target.className&&target.className.toString)?target.className.toString():'';"
        "return 'OK'+(touchOk?'+T':'')+':'+target.tagName+':'+name;"
        "}"
        "function go(doc,x,y,depth){"
        "if(depth>3){return 'DEPTH';}"
        "var el=pick(doc,x,y);"
        "if(!el){return 'NO_EL';}"
        "if(el.tagName==='IFRAME'){"
        "var cd=null;"
        "try{cd=el.contentDocument;}catch(e){}"
        "if(cd){var r=el.getBoundingClientRect();return go(cd,x-r.left,y-r.top,depth+1);}"
        "}"
        "return fire(el,doc,x,y);"
        "}"
        "return go(document,X,Y,0);"
        "}catch(e){return 'ERR:'+e;}"
        "})()";
    return [NSString stringWithFormat:kTemplate, (double)x, (double)y];
}

BOOL TSWebTapHasTargetAtScreenPoint(CGPoint screenPoint) {
    return TSFindWebViewAtScreenPoint(screenPoint) != nil;
}

static BOOL TSWebTapInWebView(UIView *webView, CGPoint screenPoint) {
    CGPoint point = TSCSSPointInWebView(webView, screenPoint);
    NSString *script = TSWebTapScript(point.x, point.y);

    Class webViewClass = (Class)objc_getClass("WKWebView");
    if (webViewClass && [webView isKindOfClass:webViewClass]) {
        [(WKWebView *)webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (gTSWebTapVerbose) {
                NSLog(@"[TSWebTap] wk css(%.0f, %.0f) -> %@%@", point.x, point.y,
                      result ?: @"", error ? [@" error=" stringByAppendingString:error.localizedDescription] : @"");
            }
        }];
        return YES;
    }

    SEL selector = NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:");
    if ([webView respondsToSelector:selector]) {
        NSString *result = ((id (*)(id, SEL, id))objc_msgSend)(webView, selector, script);
        if (gTSWebTapVerbose) {
            NSLog(@"[TSWebTap] legacy css(%.0f, %.0f) -> %@", point.x, point.y, result);
        }
        return YES;
    }
    return NO;
}

BOOL TSWebTapFromHitView(UIView *hitView, CGPoint screenPoint) {
    UIView *webView = TSWebViewAncestor(hitView) ?: TSFindWebViewAtScreenPoint(screenPoint);
    if (!webView) {
        return NO;
    }
    return TSWebTapInWebView(webView, screenPoint);
}

BOOL TSWebTapAtScreenPoint(CGPoint screenPoint) {
    UIView *webView = TSFindWebViewAtScreenPoint(screenPoint);
    if (!webView) {
        return NO;
    }
    return TSWebTapInWebView(webView, screenPoint);
}
