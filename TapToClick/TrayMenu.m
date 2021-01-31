#import "TrayMenu.h"
#import "Controller.h"
#import <Cocoa/Cocoa.h>

@implementation TrayMenu

- (id)initWithController:(Controller*)ctrl
{
  [super init];
  myController = ctrl;
  return self;
}

- (void)openWebsite:(id)sender
{
  NSURL* url = [NSURL
                URLWithString:@"https://github.com/larabr/TapToClick"];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)actionQuit:(id)sender
{
  [NSApp terminate:sender];
}

- (NSMenu*)createMenu
{
  NSMenu* menu = [NSMenu new];
  NSMenuItem* menuItem;
  
  
  // Add About
  menuItem = [menu addItemWithTitle:@"About TapToClick"
                             action:@selector(openWebsite:)
                      keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  [tapItem setTarget:self];
  
  // Add Separator
  [menu addItem:[NSMenuItem separatorItem]];
  
  // Add Quit Action
  menuItem = [menu addItemWithTitle:@"Quit"
                             action:@selector(actionQuit:)
                      keyEquivalent:@"q"];
  [menuItem setTarget:self];
  
  return menu;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
  NSMenu* menu = [self createMenu];
  
  NSImage* icon = [NSImage imageNamed:(@"StatusIcon")];
  [icon setSize:CGSizeMake(24, 24)];
  
  // Check if Darkmode menubar is supported and enable templating of the icon in
  // that case.
  
  BOOL oldBusted = (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_9);
  if (!oldBusted) {
    // 10.10 or higher, so setTemplate: is safe
    [icon setTemplate:YES];
  }
  
  _statusItem = [[[NSStatusBar systemStatusBar]
                  statusItemWithLength:24] retain];
  _statusItem.behavior = NSStatusItemBehaviorRemovalAllowed;
  _statusItem.menu = menu;
  _statusItem.button.toolTip = @"TapToClick";
  _statusItem.button.image = icon;
  
  [menu release];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)flag
{
  _statusItem.visible = true;
  return 1;
}

@end
