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
// to the nearest clickable ancestor, then fires the full event sequence. Some
// H5 pages bind touch handlers, others bind click; both are covered.
static NSString *TSWebTapScript(CGFloat x, CGFloat y) {
    static NSString *const kTemplate =
        @"(function(){"
        "try{"
        "var x=%.2f,y=%.2f;"
        "var list=[];"
        "if(document.elementsFromPoint){list=document.elementsFromPoint(x,y)||[];}"
        "else{var one=document.elementFromPoint(x,y);if(one){list=[one];}}"
        "if(!list.length){return 'NO_EL';}"
        "var el=null;"
        "for(var i=0;i<list.length;i++){"
        "var node=list[i];"
        "if(!node||node.tagName==='HTML'){continue;}"
        "var cs=null;"
        "try{cs=getComputedStyle(node);}catch(e){}"
        "if(cs&&cs.pointerEvents==='none'){continue;}"
        "el=node;break;"
        "}"
        "if(!el){el=list[0];}"
        "var target=el;"
        "for(var j=0;j<8&&target&&target!==document.body&&target!==document.documentElement;j++){"
        "var tag=target.tagName;"
        "var attr=target.getAttribute&&(target.getAttribute('onclick')||target.getAttribute('data-url')||target.getAttribute('data-href'));"
        "if(tag==='A'||tag==='BUTTON'||tag==='INPUT'||tag==='LABEL'||target.onclick||attr){break;}"
        "target=target.parentElement;"
        "}"
        "if(!target){target=el;}"
        "function mk(type,Ctor,extra){"
        "var o={bubbles:true,cancelable:true,composed:true,view:window,"
        "clientX:x,clientY:y,pageX:x,pageY:y,screenX:x,screenY:y,button:0,buttons:1};"
        "if(extra){for(var k in extra){o[k]=extra[k];}}"
        "return new Ctor(type,o);"
        "}"
        "var touchOk=false;"
        "try{"
        "if(typeof Touch==='function'&&typeof TouchEvent==='function'){"
        "var t=new Touch({identifier:1,target:target,clientX:x,clientY:y,pageX:x,pageY:y,"
        "screenX:x,screenY:y,radiusX:2,radiusY:2,force:1});"
        "target.dispatchEvent(mk('touchstart',TouchEvent,{touches:[t],targetTouches:[t],changedTouches:[t]}));"
        "target.dispatchEvent(mk('touchend',TouchEvent,{touches:[],targetTouches:[],changedTouches:[t]}));"
        "touchOk=true;"
        "}"
        "}catch(te){}"
        "target.dispatchEvent(mk('mousedown',MouseEvent,{buttons:1}));"
        "target.dispatchEvent(mk('mouseup',MouseEvent,{buttons:0}));"
        "target.dispatchEvent(mk('click',MouseEvent,{buttons:0}));"
        "var name=(target.className&&target.className.toString)?target.className.toString():'';"
        "return 'OK'+(touchOk?'+T':'')+':'+target.tagName+':'+name;"
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
