#import "MBAAppDelegate.h"
int fnToggle();

@implementation MBAAppDelegate

- (void)awakeFromNib {
  _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  
  NSImage *menuIcon       = [NSImage imageNamed:@"Menu Icon"];
  NSImage *highlightIcon  = [NSImage imageNamed:@"Menu Icon"]; // Yes, we're using the exact same image asset.
  [highlightIcon setTemplate:YES]; // Allows the correct highlighting of the icon when the menu is clicked.
  
  [[self statusItem] setImage:menuIcon];
  [[self statusItem] setAlternateImage:highlightIcon];
  [[self statusItem] setMenu:[self menu]];
  [[self statusItem] setHighlightMode:YES];
  [[self statusItem] setAction:@selector(sender)];
}


- (IBAction)menuAction:(id)sender {
    
   printf("menuAction\n");
}

@end