#import "Controller.h"
#include "TrayMenu.h"
#import <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <unistd.h>

#pragma mark Multitouch API

typedef struct {
  float x, y;
} mtPoint;
typedef struct {
  mtPoint pos, vel;
} mtReadout;

typedef struct {
  int frame;
  double timestamp;
  int identifier, state, foo3, foo4;
  mtReadout normalized;
  float size;
  int zero1;
  float angle, majorAxis, minorAxis; // ellipsoid
  mtReadout mm;
  int zero2[2];
  float unk2;
} Finger;

typedef void* MTDeviceRef;
typedef int (*MTContactCallbackFunction)(int, Finger*, int, double, int);
MTDeviceRef MTDeviceCreateDefault(void);
CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int); // thanks comex
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);

#pragma mark Globals

double touchStartTime;


BOOL needToClick;
typedef NS_ENUM (NSInteger, TouchType) {
   zero,
   one,
   multi
};
TouchType state = zero;
float touchStartX, touchEndX;
float touchStartY, touchEndY;
double lastClickTime = 0;

#pragma mark Implementation

@implementation Controller {
  NSTimer* _restartTimer;
}

- (void)start
{
  NSLog(@"starting");
  [NSApplication sharedApplication];
  
  // Get list of all multi touch devices
  NSMutableArray* deviceList = (NSMutableArray*)MTDeviceCreateList(); // grab our device list
  MTDeviceRef magicMouse = NULL;
  for (int i = 0; i < [deviceList count]; i++) { // iterate available devices
      MTDeviceRef device = (MTDeviceRef)[deviceList objectAtIndex:i];
      if  (!MTDeviceIsBuiltIn(device)) {
          magicMouse = device;
      }
  }
  if (magicMouse == NULL) return;
  MTRegisterContactFrameCallback(magicMouse, touchCallback); // assign callback for device
  MTDeviceStart(magicMouse, 0); // start sending events
  
  // register a callback to know when osx come back from sleep
  [[[NSWorkspace sharedWorkspace] notificationCenter]
   addObserver:self
   selector:@selector(receiveWakeNote:)
   name:NSWorkspaceDidWakeNotification
   object:NULL];
  
  // Register IOService notifications for added devices.
  IONotificationPortRef port = IONotificationPortCreate(kIOMasterPortDefault);
  CFRunLoopAddSource(CFRunLoopGetMain(),
                     IONotificationPortGetRunLoopSource(port),
                     kCFRunLoopDefaultMode);
  io_iterator_t handle;
  kern_return_t err = IOServiceAddMatchingNotification(
                                                       port, kIOFirstMatchNotification,
                                                       IOServiceMatching("AppleMultitouchDevice"), multitouchDeviceAddedCallback,
                                                       self, &handle);
  if (err) {
    NSLog(@"Failed to register notification for touchpad attach: %xd, will not "
          @"handle newly "
          @"attached devices",
          err);
    IONotificationPortDestroy(port);
  } else {
    /// Iterate through all the existing entries to arm the notification.
    io_object_t item;
    while ((item = IOIteratorNext(handle))) {
      CFRelease(item);
    }
  }
  
  // when displays are reconfigured restart of the app is needed, so add a calback to the
  // reconifguration of Core Graphics
//  CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallBack, self);
}

/// Schedule app to be restarted, if a restart is pending, delay it.
- (void)scheduleRestart:(NSTimeInterval)delay
{
  [_restartTimer invalidate]; // Invalidate any existing timer.
  
  _restartTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                  repeats:NO
                                                    block:^(NSTimer* timer) {
                                                      [self start];
                                                    }];
}

// Callback for system wake up. This restarts the app to initialize callbacks.
- (void)receiveWakeNote:(NSNotification*)note
{
  [self scheduleRestart:10];
}

// mulittouch callback, see what is touched. If 3 are on the mouse set
// threedowns, else unset threedowns.
int touchCallback(int device, Finger* data, int nFingers, double timestamp,
                  int frame)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  switch (state) {
    case zero:
      if (nFingers == 1) {
        state = one;
        touchStartTime = timestamp;
        Finger* f = &data[0];
        touchStartX = f->normalized.pos.x;
        touchStartY = f->normalized.pos.y;
      } else if (nFingers > 1) {
        state = multi;
      }
      break;
    case multi:
      if (nFingers == 0) {
        state = zero;
        touchStartTime = 0;
      }
      // if nFingers == 1, we stay here waiting for nFingers == 0
      break;
    case one:
      if (nFingers == 0) {
        state = zero;
        double deltaTime = timestamp - touchStartTime;
        touchStartTime = 0;
        
        // confirm it's a tap event, rather than long click or swipe
        if (deltaTime > 0.3f) break;
        
        float deltaSwipe = ABS(touchStartX - touchEndX) + ABS(touchStartY - touchEndY);
        if (deltaSwipe > 0.1f) break;
    
        // trigger click event
        CGPoint pointerLocation = CGEventGetLocation(CGEventCreate(NULL));
        if (touchEndX < 0.4f) { // left click
          bool isDoubleClick = (timestamp - lastClickTime) < 0.3f;
          lastClickTime = timestamp;
          CGEventRef clickEvent = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, pointerLocation, kCGMouseButtonLeft);
          CGEventSetIntegerValueField(clickEvent, kCGMouseEventClickState, isDoubleClick ? 2 : 1);
          CGEventPost(kCGHIDEventTap, clickEvent);
          CGEventSetType(clickEvent, kCGEventLeftMouseUp);
          CGEventPost(kCGHIDEventTap, clickEvent);
          CFRelease(clickEvent);
        } else if (touchEndX > 0.5f) { // right click
          CGEventRef clickEvent = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, pointerLocation, kCGMouseButtonRight);
          CGEventPost(kCGHIDEventTap, clickEvent);
          CGEventSetType(clickEvent, kCGEventRightMouseUp);
          CGEventPost(kCGHIDEventTap, clickEvent);
          CFRelease(clickEvent);
        }
      } else if (nFingers > 1) {
        state = multi;
      } else {
        Finger* f = &data[0];
        touchEndX = f->normalized.pos.x;
        touchEndY = f->normalized.pos.y;
      }
      break;
    default:
      break;
  }
  
  [pool release];
  return 0;
}

/// Callback when a multitouch device is added.
void multitouchDeviceAddedCallback(void* _controller,
                                   io_iterator_t iterator)
{
  /// Loop through all the returned items.
  io_object_t item;
  while ((item = IOIteratorNext(iterator))) {
    CFRelease(item);
  }
  
  NSLog(@"Multitouch device added, restarting...");
  Controller* controller = (Controller*)_controller;
  [controller scheduleRestart:2];
}

void displayReconfigurationCallBack(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void* _controller)
{
  if(flags & kCGDisplaySetModeFlag || flags & kCGDisplayAddFlag || flags & kCGDisplayRemoveFlag || flags & kCGDisplayDisabledFlag)
  {
    NSLog(@"Display reconfigured, restarting...");
    Controller* controller = (Controller*)_controller;
    [controller scheduleRestart:2];
  }
}



@end
