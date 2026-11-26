// TSWebTap: DOM-level clicking for WKWebView / UIWebView pages.
//
// UIKit touch synthesis does not reach WebKit's gesture recognizers reliably:
// a synthetic UITouchesEvent goes through UIWindow sendEvent:, while WebKit's
// click detection depends on the system touch pipeline. For H5 pages the
// dependable route is to resolve the element under the point and dispatch a
// click script inside the page.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// YES when the screen point lands on a visible WKWebView / UIWebView.
// Does not run any script.
BOOL TSWebTapHasTargetAtScreenPoint(CGPoint screenPoint);

// Resolves the element at the point and dispatches touchstart/touchend plus
// mousedown/mouseup/click on it. Returns YES when a web view was found and the
// script was handed off (the DOM result arrives asynchronously).
BOOL TSWebTapAtScreenPoint(CGPoint screenPoint);

// Mirrors TSTouchSynthesizer.verboseLogging so the JS result can be logged.
void TSWebTapSetVerbose(BOOL verbose);

NS_ASSUME_NONNULL_END
