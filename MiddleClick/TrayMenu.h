#import "Controller.h"
#import <Foundation/Foundation.h>

@interface TrayMenu : NSObject <NSFileManagerDelegate> {
@private
  NSStatusItem* _statusItem;
  Controller* myController;
  NSMenuItem* tapItem;
  NSMenuItem* clickItem;
}
- (id)initWithController:(Controller*)ctrl;
@end
