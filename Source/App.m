#import "Core.h"
@interface AFPFlippedView : NSView
@end
@implementation AFPFlippedView
- (instancetype)initWithFrame:(NSRect)frame{
    if((self=[super initWithFrame:frame]))[self setClipsToBounds:YES];
    return self;
}
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)r{[[NSColor windowBackgroundColor]setFill];NSRectFill(NSIntersectionRect(r,[self bounds]));}
@end
static NSTextField *Label(NSView *v,NSString *text,NSRect frame,CGFloat size,BOOL bold){NSTextField *x=[NSTextField labelWithString:text?:@""];[x setFrame:frame];[x setFont:bold?[NSFont boldSystemFontOfSize:size]:[NSFont systemFontOfSize:size]];[x setSelectable:YES];[x setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];[v addSubview:x];return x;}
static NSTextField *Note(NSView *v,NSString *text,NSRect frame){NSTextField *x=[NSTextField wrappingLabelWithString:text];[x setFrame:frame];[x setFont:[NSFont systemFontOfSize:12]];[x setTextColor:[NSColor secondaryLabelColor]];[x setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];[v addSubview:x];return x;}
static NSButton *Button(NSView *v,NSString *title,NSRect r,id target,SEL action){NSButton *b=[NSButton buttonWithTitle:title target:target action:action];[b setFrame:r];[b setBezelStyle:NSBezelStyleRounded];[b setAutoresizingMask:NSViewMaxYMargin];[v addSubview:b];return b;}
static NSButton *Check(NSView *v,NSString *title,NSRect r,BOOL on,id target,SEL action){NSButton *b=[NSButton checkboxWithTitle:title target:target action:action];[b setFrame:r];[b setState:on?NSControlStateValueOn:NSControlStateValueOff];[b setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];[v addSubview:b];return b;}
static NSTextField *Field(NSView *v,NSString *text,NSRect r,BOOL secure){NSTextField *x=secure?[[NSSecureTextField alloc]initWithFrame:r]:[[NSTextField alloc]initWithFrame:r];[x setStringValue:S(text)];[x setFont:[NSFont systemFontOfSize:13]];[x setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];[v addSubview:x];return x;}
static NSTextView *TextBox(NSView *v,NSRect r,NSString *text){NSScrollView *sc=[[NSScrollView alloc]initWithFrame:r];[sc setHasVerticalScroller:YES];[sc setAutohidesScrollers:YES];[sc setBorderType:1];[sc setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];NSTextView *tv=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,r.size.width,r.size.height)];[tv setEditable:NO];[tv setSelectable:YES];[tv setFont:[NSFont monospacedSystemFontOfSize:11 weight:0]];[tv setTextColor:[NSColor textColor]];[tv setBackgroundColor:[NSColor textBackgroundColor]];[tv setTextContainerInset:NSMakeSize(10,10)];[tv setMinSize:NSMakeSize(0,r.size.height)];[tv setMaxSize:NSMakeSize(100000,100000)];[tv setVerticallyResizable:YES];[tv setHorizontallyResizable:NO];[tv setAutoresizingMask:NSViewWidthSizable];[tv setString:S(text)];[sc setDocumentView:tv];[v addSubview:sc];return tv;}
static NSInteger Alert(NSString *title,NSString *body,NSArray *buttons){NSAlert *a=[NSAlert new];[a setMessageText:title];[a setInformativeText:body?:@""];[a setAlertStyle:NSAlertStyleInformational];for(NSString *s in buttons)[a addButtonWithTitle:s];return [a runModal];}
static NSString *Choose(BOOL directory,NSString *prompt,NSString *initial){NSOpenPanel *p=[NSOpenPanel openPanel];[p setCanChooseDirectories:directory];[p setCanChooseFiles:!directory];[p setAllowsMultipleSelection:NO];[p setCanCreateDirectories:directory];[p setMessage:prompt];if([initial length])[p setDirectoryURL:[NSURL fileURLWithPath:initial]];return [p runModal]==NSModalResponseOK?[[p URL]path]:nil;}
static BOOL YesValue(id s){return [@[@"yes",@"true",@"on",@"1"]containsObject:[S(s)lowercaseString]];}
static NSInteger ServiceState(SMAppService *service) {
    @try { return [service status]; }
    @catch(NSException *e) { AFPRecordException(e); return -1; }
}
static NSString *ServiceStatus(SMAppService *s) {
    switch(ServiceState(s)) {
        case 0:return @"Not registered"; case 1:return @"Enabled";
        case 2:return @"Needs approval in System Settings";
        case 3:return @"Not found"; default:return @"Unavailable (see diagnostics)";
    }
}
@interface AFPController : NSObject <NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) AFPFlippedView *root,*content;
@property(nonatomic,strong) NSTextField *headerStatus,*footerShare,*footerConfig,*lastRefresh,*overviewStatus,*overviewIP,*overviewDetails,*overviewWarnings,*connectionNote;
@property(nonatomic,strong) NSButton *startButton,*stopButton,*restartButton,*appLogin,*serverBoot,*autoMetadata,*statsToggle,*shellToggle;
@property(nonatomic,strong) NSProgressIndicator *spinner;
@property(nonatomic,strong) NSStatusItem *statusItem;
@property(nonatomic,strong) NSMutableArray *navButtons;
@property(nonatomic,strong) NSTableView *sharesTable,*sessionsTable,*socketsTable,*accountsTable;
@property(nonatomic,strong) NSTextView *activityText,*metadataText,*sessionRaw;
@property(nonatomic,strong) NSTextField *configField,*nameField,*portField,*statsGroup,*uamField,*dialogPath;
@property(nonatomic,strong) NSTimer *timer,*updateTimer;
@property(nonatomic,strong) NSDictionary *packageStatus;
@property(nonatomic,strong) NSTextField *updateInstalled,*updateLatest,*updateManager,*updateStatus,*updateChecked;
@property(nonatomic,strong) NSTextView *updateText;
@property(nonatomic,strong) NSButton *updateCheckButton,*updateInstallButton,*updateReleaseButton;
@property(nonatomic,strong) NSProgressIndicator *updateSpinner;
@property(nonatomic,assign) BOOL updateChecking,packageInstalling,packageSetupOnly;
@property(nonatomic,assign) NSTimeInterval updateLastAttempt;
@property(nonatomic,strong) NSDictionary *snapshot,*adminSnapshot;
@property(nonatomic,strong) NSArray *users;
@property(nonatomic,strong) NSMutableDictionary *prefs;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) BOOL busy,refreshing,editing,rebuildAfterRefresh;
- (void)buildWindow;
- (void)drawPage;
- (void)refresh:(id)sender;
- (void)beginJob:(NSDictionary *)job;
@end
@implementation AFPController
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    @try {
        AFPStartupLog(@"AppKit finished launching; creating the main window.");
        self.prefs=Prefs(); self.packageStatus=JSONFile([SupportDir()stringByAppendingPathComponent:@"package-status.json"])?:@{}; self.snapshot=[NSDictionary dictionary]; self.users=[NSArray array]; self.page=0;
        [self buildWindow]; [self drawPage];
        if (AFPSmokeReportPath) {
            [self performSelector:@selector(finishSmokeTest:) withObject:nil afterDelay:0.2];
            return;
        }
        [self.window makeKeyAndOrderFront:nil];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        AFPStartupLog(@"Main window created. Monitoring starts on the next run-loop turn.");
        [self performSelector:@selector(beginMonitoring:) withObject:nil afterDelay:0.1];
    } @catch(NSException *e) {
        AFPRecordException(e);
        if (AFPSmokeReportPath) {
            SaveJSON(@{@"ok":@NO,@"error":[e reason]?:@"Startup exception"},AFPSmokeReportPath);
            [[NSApplication sharedApplication] terminate:nil];
        } else {
            Alert(@"AFP Server could not finish starting", [NSString stringWithFormat:@"%@\n\nThe startup log was saved. Use Activity & Diagnostics after reopening the app, or inspect the startup log in ~/Library/Logs/AFPServer.",[e reason]], @[@"Close"]);
            [[NSApplication sharedApplication] terminate:nil];
        }
    }
}
- (void)beginMonitoring:(id)sender {
    @try {
        [self refresh:nil];
        self.timer=[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
        self.updateTimer=[NSTimer scheduledTimerWithTimeInterval:900 target:self selector:@selector(scheduledUpdateCheck:) userInfo:nil repeats:YES];
        [self performSelector:@selector(scheduledUpdateCheck:) withObject:nil afterDelay:2];
        NSString *legacy=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.netatalk.classic-metadata.plist"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:legacy])
            Alert(@"An older metadata agent is still installed",@"The old scripts may still call dot_clean -m. Use Settings > Remove old agent before enabling the new worker. Nothing was changed automatically.",@[@"OK"]);
    } @catch(NSException *e) { AFPRecordException(e); Alert(@"Monitoring could not start",[e reason],@[@"OK"]); }
}
- (void)finishSmokeTest:(id)sender {
    NSMutableArray *passed=[NSMutableArray array];
    @try {
        // Read-only discovery also exercises the real local Netatalk/config environment.
        self.snapshot=Snapshot(S(self.prefs[@"configPath"]));
        self.users=Accounts();
        NSString *renderDir=[AFPSmokeReportPath stringByAppendingString:@".pages"];
        NSError *renderError=nil;
        if(![[NSFileManager defaultManager]createDirectoryAtPath:renderDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&renderError])
            Fail([@"Cannot create page-render directory: " stringByAppendingString:S([renderError localizedDescription])]);
        if (![S(self.prefs[@"selectedSection"]) length] && [self.snapshot[@"shares"] count])
            self.prefs[@"selectedSection"]=self.snapshot[@"shares"][0][@"section"];
        [self.window setIgnoresMouseEvents:YES];
        [self.window orderFront:nil]; // Let AppKit prepare its backing views during this UI-only test.
        for (NSInteger page=0; page<8; page++) {
            self.page=page; [self drawPage]; [self updateDisplay];
            [self.root layoutSubtreeIfNeeded];
            [self validateSmokeControls:self.root];
            [self.window display];
            [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]];
            NSBitmapImageRep *rep=[self.root bitmapImageRepForCachingDisplayInRect:[self.root bounds]];
            if(!rep)Fail(@"AppKit could not allocate a page image.");
            [self.root displayRectIgnoringOpacity:[self.root bounds] inContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *imagePath=[renderDir stringByAppendingPathComponent:[NSString stringWithFormat:@"page-%ld.png",(long)page]];
            if(![png writeToFile:imagePath atomically:YES])Fail(@"Cannot save a rendered UI page.");
            [passed addObject:@(page)];
        }
        // Exercise an actual child process with stdin redirected, but no server operation.
        NSDictionary *task=Run(@"/usr/bin/true",@[],5,nil);
        if (![task[@"ok"] boolValue]) Fail([@"Native process smoke test failed: " stringByAppendingString:S(task[@"out"])]);
        NSDictionary *helper=Run(HelperPath(),@[@"--self-test"],15,nil);
        if(![helper[@"ok"]boolValue])Fail([@"Embedded helper self-test failed: "stringByAppendingString:S(helper[@"out"])]);
        if (!SaveJSON(@{@"ok":@YES,@"version":AFP_VERSION,@"pagesBuilt":passed,@"processLaunch":@YES,@"embeddedHelperSelfTest":@YES,@"readOnlyDiscovery":@YES,@"pageImages":renderDir,@"accountRows":@([self.users count]),
                       @"serverModified":@NO,@"accountsModified":@NO},AFPSmokeReportPath))
            Fail(@"Cannot write the smoke-test result.");
    } @catch(NSException *e) {
        AFPRecordException(e);
        SaveJSON(@{@"ok":@NO,@"pagesBuilt":passed,@"error":[e reason]?:@"UI smoke test failed"},AFPSmokeReportPath);
    }
    [[NSApplication sharedApplication] terminate:nil];
}
- (void)validateSmokeControls:(NSView *)view {
    [view setNeedsDisplay:YES]; // Include persistent header/navigation views in offscreen renders.
    if([view isKindOfClass:[NSButton class]]){
        NSButton *button=(NSButton *)view;
        if([button action]&&[button target]&&![[button target]respondsToSelector:[button action]])
            Fail([@"A UI action is unavailable: "stringByAppendingString:[button title]]);
    }
    if([view isKindOfClass:[NSTableView class]]){
        NSTableView *table=(NSTableView *)view;
        NSInteger count=[self numberOfRowsInTableView:table];
        for(NSInteger row=0;row<count;row++)for(NSTableColumn *column in [table tableColumns])
            (void)[self tableView:table objectValueForTableColumn:column row:row];
    }
    for(NSView *child in [view subviews])[self validateSmokeControls:child];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app{return NO;}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible{[self.window makeKeyAndOrderFront:nil];return YES;}
- (void)buildWindow{
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1160,820)styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];[self.window setTitle:@"AFP Server"];[self.window setMinSize:NSMakeSize(1100,840)];[self.window setReleasedWhenClosed:NO];[self.window setDelegate:self];[self.window setFrameAutosaveName:@"AFPServerMainWindow"];[self.window center];
    self.root=[[AFPFlippedView alloc]initWithFrame:NSMakeRect(0,0,1160,820)];[self.root setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];[self.window setContentView:self.root];
    Label(self.root,@"AFP Server",NSMakeRect(22,15,280,32),25,YES);self.headerStatus=Label(self.root,@"Discovering Netatalk...",NSMakeRect(23,52,670,22),12,NO);
    self.startButton=Button(self.root,@"Start",NSMakeRect(752,22,82,32),self,@selector(serverAction:));[self.startButton setTag:1];self.stopButton=Button(self.root,@"Stop",NSMakeRect(838,22,82,32),self,@selector(serverAction:));[self.stopButton setTag:2];self.restartButton=Button(self.root,@"Restart",NSMakeRect(924,22,100,32),self,@selector(serverAction:));[self.restartButton setTag:3];NSButton *refresh=Button(self.root,@"Refresh",NSMakeRect(1028,22,106,32),self,@selector(refresh:));
    for(NSButton *b in @[self.startButton,self.stopButton,self.restartButton,refresh])[b setAutoresizingMask:NSViewMinXMargin|NSViewMaxYMargin];
    self.spinner=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(1125,59,16,16)];[self.spinner setStyle:NSProgressIndicatorStyleSpinning];[self.spinner setControlSize:NSControlSizeSmall];[self.spinner setDisplayedWhenStopped:NO];[self.spinner setAutoresizingMask:NSViewMinXMargin|NSViewMaxYMargin];[self.root addSubview:self.spinner];
    self.lastRefresh=Label(self.root,@"",NSMakeRect(780,57,335,20),11,NO);[self.lastRefresh setAlignment:NSTextAlignmentRight];[self.lastRefresh setAutoresizingMask:NSViewMinXMargin|NSViewMaxYMargin];[self.lastRefresh setTextColor:[NSColor secondaryLabelColor]];
    self.navButtons=[NSMutableArray array];NSArray *names=@[@"Overview",@"Shares",@"Connections",@"Accounts",@"Classic Metadata",@"Settings",@"Activity & Diagnostics",@"Updates"];
    for(NSUInteger n=0;n<[names count];n++){NSButton *b=Button(self.root,names[n],NSMakeRect(14,98+44*n,180,34),self,@selector(navigate:));[b setTag:n];[self.navButtons addObject:b];}
    Note(self.root,@"Closing this window does not stop Netatalk.\n\nServer administration requires your approval in macOS.",NSMakeRect(22,495,166,125));
    self.content=[[AFPFlippedView alloc]initWithFrame:NSMakeRect(215,98,922,656)];[self.content setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];[self.root addSubview:self.content];
    self.footerShare=Label(self.root,@"Share: detecting...",NSMakeRect(22,771,1114,20),12,YES);[self.footerShare setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];[self.footerShare setLineBreakMode:NSLineBreakByTruncatingMiddle];self.footerConfig=Label(self.root,@"",NSMakeRect(22,793,1114,18),10,NO);[self.footerConfig setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];[self.footerConfig setTextColor:[NSColor secondaryLabelColor]];[self.footerConfig setLineBreakMode:NSLineBreakByTruncatingMiddle];
    NSMenu *bar=[[NSMenu alloc]initWithTitle:@""];NSMenuItem *app=[bar addItemWithTitle:@"AFP Server"action:NULL keyEquivalent:@""];NSMenu *menu=[[NSMenu alloc]initWithTitle:@"AFP Server"];[menu addItemWithTitle:@"About AFP Server"action:@selector(orderFrontStandardAboutPanel:)keyEquivalent:@""];[menu addItem:[NSMenuItem separatorItem]];NSMenuItem *show=[menu addItemWithTitle:@"Show AFP Server"action:@selector(showWindow:)keyEquivalent:@"0"];[show setTarget:self];[menu addItem:[NSMenuItem separatorItem]];NSMenuItem *uninstall=[menu addItemWithTitle:@"Uninstall AFP Server…" action:@selector(uninstallApp:) keyEquivalent:@""];[uninstall setTarget:self];[menu addItem:[NSMenuItem separatorItem]];[menu addItemWithTitle:@"Quit AFP Server"action:@selector(terminate:)keyEquivalent:@"q"];[app setSubmenu:menu];
    NSMenuItem *edit=[bar addItemWithTitle:@"Edit"action:NULL keyEquivalent:@""];NSMenu *em=[[NSMenu alloc]initWithTitle:@"Edit"];[em addItemWithTitle:@"Undo"action:@selector(undo:)keyEquivalent:@"z"];[em addItemWithTitle:@"Cut"action:@selector(cut:)keyEquivalent:@"x"];[em addItemWithTitle:@"Copy"action:@selector(copy:)keyEquivalent:@"c"];[em addItemWithTitle:@"Paste"action:@selector(paste:)keyEquivalent:@"v"];[em addItemWithTitle:@"Select All"action:@selector(selectAll:)keyEquivalent:@"a"];[edit setSubmenu:em];[[NSApplication sharedApplication]setMainMenu:bar];
    self.statusItem=[[NSStatusBar systemStatusBar]statusItemWithLength:NSVariableStatusItemLength];[[self.statusItem button]setTitle:@"AFP"];NSMenu *sm=[[NSMenu alloc]initWithTitle:@"AFP Server"];NSMenuItem *open=[sm addItemWithTitle:@"Open AFP Server"action:@selector(showWindow:)keyEquivalent:@""];[open setTarget:self];[sm addItem:[NSMenuItem separatorItem]];for(NSUInteger k=0;k<3;k++){NSMenuItem *item=[sm addItemWithTitle:@[@"Start server",@"Stop server",@"Restart server"][k]action:@selector(serverAction:)keyEquivalent:@""];[item setTarget:self];[item setTag:k+1];}[sm addItem:[NSMenuItem separatorItem]];[sm addItemWithTitle:@"Quit app (server stays running)"action:@selector(terminate:)keyEquivalent:@""];[self.statusItem setMenu:sm];
}
- (void)showWindow:(id)sender{[self.window makeKeyAndOrderFront:nil];[[NSApplication sharedApplication]activateIgnoringOtherApps:YES];}
- (void)navigate:(id)sender{self.page=[sender tag];[self drawPage];if(self.page==7&&![self.packageStatus count])[self checkUpdates:nil];if(self.page==3&&!self.busy)[self beginJob:@{@"kind":@"users"}];}
- (NSDictionary *)selectedShare{NSString *sel=S(self.prefs[@"selectedSection"]);for(NSDictionary *s in self.snapshot[@"shares"])if([[S(s[@"section"])lowercaseString]isEqualToString:[sel lowercaseString]])return s;return nil;}
- (NSDictionary *)connectionSnapshot{if(self.adminSnapshot&&(![self.snapshot[@"sessionsReadable"]boolValue]||![(NSArray *)self.snapshot[@"sockets"] count]))return self.adminSnapshot;return self.snapshot;}
- (NSTableView *)table:(NSRect)r columns:(NSArray *)spec tag:(NSInteger)tag{
    NSScrollView *sc=[[NSScrollView alloc]initWithFrame:r];[sc setHasVerticalScroller:YES];[sc setHasHorizontalScroller:YES];[sc setAutohidesScrollers:YES];[sc setBorderType:1];[sc setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];NSTableView *t=[[NSTableView alloc]initWithFrame:NSMakeRect(0,0,r.size.width,r.size.height)];[t setTag:tag];[t setDataSource:self];[t setDelegate:self];[t setAllowsMultipleSelection:NO];[t setUsesAlternatingRowBackgroundColors:YES];[t setRowHeight:27];[t setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];for(NSArray *s in spec){NSTableColumn *c=[[NSTableColumn alloc]initWithIdentifier:s[0]];[c setTitle:s[1]];[c setWidth:[s[2]doubleValue]];[c setMinWidth:70];[c setResizingMask:3];[c setEditable:NO];[t addTableColumn:c];}[sc setDocumentView:t];[self.content addSubview:sc];return t;
}
- (NSArray *)rows:(NSInteger)tag{if(tag==11)return self.snapshot[@"shares"]?:[NSArray array];if(tag==12)return [self connectionSnapshot][@"sessions"]?:[NSArray array];if(tag==13)return [self connectionSnapshot][@"sockets"]?:[NSArray array];if(tag==14)return self.users?:[NSArray array];return [NSArray array];}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t{return [[self rows:[t tag]]count];}
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row{NSArray *a=[self rows:[t tag]];if(row<0||(NSUInteger)row>=[a count])return @"";NSDictionary *r=a[row];NSString *key=[c identifier];if([t tag]==11&&[key isEqualToString:@"access"])return YesValue(r[@"options"][@"read only"])?@"Read only":@"Read / write";if([t tag]==14&&[key isEqualToString:@"managed"])return [r[@"managed"]boolValue]?@"App-managed":@"Existing account";return S(r[key]);}
- (void)drawPage{
    for(NSView *v in [[self.content subviews]copy])[v removeFromSuperview];self.sharesTable=nil;self.sessionsTable=nil;self.socketsTable=nil;self.accountsTable=nil;self.activityText=nil;self.metadataText=nil;self.sessionRaw=nil;self.overviewStatus=nil;self.overviewIP=nil;self.overviewDetails=nil;self.overviewWarnings=nil;self.connectionNote=nil;self.updateInstalled=nil;self.updateLatest=nil;self.updateManager=nil;self.updateStatus=nil;self.updateChecked=nil;self.updateText=nil;self.updateCheckButton=nil;self.updateInstallButton=nil;self.updateReleaseButton=nil;self.updateSpinner=nil;
    for(NSButton *b in self.navButtons)[b setState:[b tag]==self.page?NSControlStateValueOn:NSControlStateValueOff];CGFloat w=[self.content bounds].size.width,h=[self.content bounds].size.height;
    if(self.page==0){Label(self.content,@"Server overview",NSMakeRect(0,0,w,34),24,YES);self.overviewStatus=Label(self.content,@"Discovering...",NSMakeRect(0,55,w,34),24,YES);self.overviewIP=Label(self.content,@"",NSMakeRect(0,104,w,64),16,NO);[self.overviewIP setMaximumNumberOfLines:3];Button(self.content,@"Copy AFP address",NSMakeRect(0,177,170,30),self,@selector(copyAddress:));Button(self.content,@"Administrator snapshot",NSMakeRect(182,177,210,30),self,@selector(adminRefresh:));Label(self.content,@"Your server",NSMakeRect(0,235,w,28),17,YES);self.overviewDetails=Note(self.content,@"",NSMakeRect(0,275,w,155));self.overviewWarnings=Note(self.content,@"",NSMakeRect(0,451,w,h-455));[self updateDisplay];}
    else if(self.page==1){Label(self.content,@"Shares",NSMakeRect(0,0,w,34),24,YES);Note(self.content,@"Read directly from afp.conf. Folder changes update the selected section; they do not move or delete your files.",NSMakeRect(0,43,w,38));self.sharesTable=[self table:NSMakeRect(0,94,w,h-174)columns:@[@[@"name",@"AFP name",@150],@[@"section",@"Config section",@140],@[@"path",@"Folder",@440],@[@"access",@"Access",@130]]tag:11];[self.sharesTable setTarget:self];[self.sharesTable setDoubleAction:@selector(editShare:)];CGFloat y=h-66;NSArray *buttons=@[@"Add share",@"Edit",@"Use selected",@"Remove",@"Show folder"];SEL sels[]={@selector(addShare:),@selector(editShare:),@selector(useShare:),@selector(removeShare:),@selector(openShare:)};for(int i=0;i<5;i++){NSButton *b=Button(self.content,buttons[i],NSMakeRect(i*148,y,138,32),self,sels[i]);[b setAutoresizingMask:NSViewMinYMargin];}}
    else if(self.page==2){Label(self.content,@"Connections",NSMakeRect(0,0,w,34),24,YES);self.connectionNote=Note(self.content,@"",NSMakeRect(0,43,w,38));Button(self.content,@"Administrator snapshot",NSMakeRect(0,85,210,30),self,@selector(adminRefresh:));Button(self.content,@"Disconnect selected TCP session",NSMakeRect(222,85,260,30),self,@selector(disconnect:));Label(self.content,@"Authenticated AFP sessions",NSMakeRect(0,132,w,22),15,YES);
        self.sessionsTable=[self table:NSMakeRect(0,162,w,168)columns:@[@[@"user",@"AFP user",@125],@[@"pid",@"PID",@70],@[@"client",@"Client",@165],@[@"login",@"Login time",@150],@[@"state",@"State",@95],@[@"volumes",@"Mounted volumes",@260]]tag:12];[[self.sessionsTable enclosingScrollView]setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];
        Label(self.content,@"TCP sockets - local address:port -> remote address:port",NSMakeRect(0,350,w,22),15,YES);self.socketsTable=[self table:NSMakeRect(0,380,w,150)columns:@[@[@"pid",@"PID",@70],@[@"uid",@"OS UID",@75],@[@"local",@"Local IP : port",@280],@[@"remote",@"Client IP : port",@280],@[@"state",@"TCP state",@140]]tag:13];[[self.socketsTable enclosingScrollView]setAutoresizingMask:NSViewWidthSizable|NSViewMaxYMargin];self.sessionRaw=TextBox(self.content,NSMakeRect(0,548,w,MAX(75,h-548)),@"");[self updateDisplay];}
    else if(self.page==3){Label(self.content,@"Accounts",NSMakeRect(0,0,w,34),24,YES);Note(self.content,@"Use existing local macOS users or create hidden, non-administrator sharing accounts. AFP access rules and folder permissions are separate.",NSMakeRect(0,43,w,44));self.accountsTable=[self table:NSMakeRect(0,100,w,h-230)columns:@[@[@"name",@"Account",@185],@[@"display",@"Display name",@300],@[@"uid",@"UID",@85],@[@"managed",@"Management",@230]]tag:14];CGFloat y=h-112;NSArray *titles=@[@"Add account",@"Change password",@"Remove managed",@"Grant folder access"];SEL selectors[]={@selector(addAccount:),@selector(changePassword:),@selector(deleteAccount:),@selector(grantACL:)};for(int i=0;i<4;i++){NSButton *b=Button(self.content,titles[i],NSMakeRect(i*184,y,174,32),self,selectors[i]);[b setAutoresizingMask:NSViewMinYMargin];}NSTextField *n=Note(self.content,@"To use a new sharing account: allow no-login-shell accounts in Settings, add its name under Shares > Edit > Allowed users, and grant folder access. Personal account passwords are never changed here.",NSMakeRect(0,h-64,w,58));[n setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];}
    else if(self.page==4){Label(self.content,@"Classic Mac metadata",NSMakeRect(0,0,w,34),24,YES);Note(self.content,@"Only the selected AFP share is inspected. Missing metadata is copied from existing AppleDouble data after backup and verification. Existing resource forks are never overwritten; sidecars are retained.",NSMakeRect(0,44,w,54));NSArray *titles=@[@"Inspect metadata",@"Restore missing metadata",@"Create Classic test file",@"Import file / folder",@"Check CNID (offline)",@"Repair CNID (offline)"];SEL sels[]={@selector(inspectMetadata:),@selector(repairMetadata:),@selector(testMetadata:),@selector(importFiles:),@selector(checkCNID:),@selector(repairCNID:)};for(int n=0;n<6;n++)Button(self.content,titles[n],NSMakeRect((n%3)*(w/3),114+(n/3)*43,w/3-12,32),self,sels[n]);Note(self.content,@"Restoration pauses while clients are connected or their status is unknown. Recent files are deferred for 10 seconds. Lost resource-fork contents cannot be invented. Automatic care is optional in Settings.",NSMakeRect(0,212,w,50));NSDictionary *last=JSONFile([SupportDir()stringByAppendingPathComponent:@"metadata-last-run.json"]);self.metadataText=TextBox(self.content,NSMakeRect(0,277,w,h-277),last?JSON(last):@"Choose Inspect metadata to see what is actually present.");}
    else if(self.page==5){[self drawSettings];}
    else if(self.page==7){[self drawUpdates];}
    else {Label(self.content,@"Activity & diagnostics",NSMakeRect(0,0,w,34),24,YES);Button(self.content,@"Refresh log",NSMakeRect(0,48,125,30),self,@selector(refreshLog:));Button(self.content,@"Run diagnostics",NSMakeRect(138,48,155,30),self,@selector(diagnostics:));Button(self.content,@"Open logs & backups",NSMakeRect(306,48,180,30),self,@selector(openLogs:));Button(self.content,@"Show afp.conf",NSMakeRect(500,48,150,30),self,@selector(showConfig:));Note(self.content,@"The app records actions and errors, not file contents or passwords. Session activity is not an invented transfer-speed measurement.",NSMakeRect(0,90,w,37));self.activityText=TextBox(self.content,NSMakeRect(0,140,w,h-140),LogTail());}
}
- (BOOL)dailyUpdatesEnabled {
    id value=self.prefs[@"checkNetatalkUpdates"];
    return [value isKindOfClass:[NSNumber class]]?[value boolValue]:YES;
}
- (void)drawUpdates {
    CGFloat w=[self.content bounds].size.width,h=[self.content bounds].size.height;
    Label(self.content,@"Netatalk updates",NSMakeRect(0,0,w,34),24,YES);
    Note(self.content,@"Check and install the latest stable Netatalk release. Installation and updates start only when you click below. Netatalk stays independent of the AFP Server app.",NSMakeRect(0,44,w,50));
    self.updateInstalled=Label(self.content,@"",NSMakeRect(0,112,w,28),17,YES);
    self.updateLatest=Label(self.content,@"",NSMakeRect(0,151,w,26),16,NO);
    self.updateManager=Note(self.content,@"",NSMakeRect(0,190,w,50));
    self.updateStatus=Note(self.content,@"",NSMakeRect(0,248,w,51));
    self.updateCheckButton=Button(self.content,@"Check now",NSMakeRect(0,307,150,32),self,@selector(checkUpdates:));
    self.updateInstallButton=Button(self.content,@"Install Netatalk",NSMakeRect(164,307,220,32),self,@selector(installPackage:));
    self.updateReleaseButton=Button(self.content,@"Release notes",NSMakeRect(398,307,150,32),self,@selector(openPackageRelease:));
    self.updateSpinner=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(562,315,16,16)];[self.updateSpinner setStyle:NSProgressIndicatorStyleSpinning];[self.updateSpinner setControlSize:NSControlSizeSmall];[self.updateSpinner setDisplayedWhenStopped:NO];[self.content addSubview:self.updateSpinner];
    Check(self.content,@"Check daily while AFP Server is open",NSMakeRect(0,365,w,24),[self dailyUpdatesEnabled],self,@selector(toggleDailyUpdates:));
    self.updateChecked=Note(self.content,@"",NSMakeRect(0,399,w,40));
    Note(self.content,@"Updating requires a stopped server. No clients are disconnected automatically; stop Netatalk in Overview first. Installing or updating does not enable server boot startup or start the daemon.",NSMakeRect(0,449,w,57));
    self.updateText=TextBox(self.content,NSMakeRect(0,526,w,MAX(90,h-526)),@"");
    [self updatePackageDisplay];
}
- (void)updatePackageDisplay {
    NSDictionary *status=self.packageStatus?:@{};
    NSString *installed=S(status[@"installedVersion"]),*latest=S(status[@"latestVersion"]),*action=S(status[@"action"]);
    [self.updateInstalled setStringValue:[installed length]?[@"Installed: Netatalk "stringByAppendingString:installed]:([status[@"installed"]isKindOfClass:[NSNumber class]]?@"Installed: Netatalk not found":@"Installed version: not checked yet")];
    [self.updateLatest setStringValue:[latest length]?[[status[@"ok"]boolValue]?@"Latest stable: Netatalk ":@"Latest stable (last known): Netatalk " stringByAppendingString:latest]:@"Latest stable version: not checked yet"];
    NSString *manager=S(status[@"manager"]);
    NSString *managerInfo=[manager isEqualToString:@"homebrew"]?@"Installation managed by Homebrew.":([manager isEqualToString:@"source"]?@"Existing installation detected outside Homebrew. See the check result before making changes.":@"The check determines whether this Mac has a supported installation route.");
    NSString *pam=S(status[@"pamMessage"]);
    [self.updateManager setStringValue:[pam length]?[NSString stringWithFormat:@"%@\n%@",managerInfo,pam]:managerInfo];
    BOOL installing=self.packageInstalling;
    NSString *message=self.updateChecking?@"Checking installed tools and the latest stable release…":(installing?(self.packageSetupOnly?@"Completing AFP authentication setup. Approve the normal macOS administrator dialog when requested.":@"Installing Netatalk. This can take several minutes; wait for the result."):(self.busy?@"Another operation is in progress.":([S(status[@"message"])length]?S(status[@"message"]):@"Choose Check now to find the latest stable release.")));
    [self.updateStatus setStringValue:message];
    BOOL finishSetup=[action isEqualToString:@"current"]&&[status[@"installed"]boolValue]&&[status[@"pamReady"]isKindOfClass:[NSNumber class]]&&![status[@"pamReady"]boolValue];
    BOOL actionable=[status[@"ok"]boolValue]&&[status[@"canInstall"]boolValue]&&([action isEqualToString:@"install"]||[action isEqualToString:@"update"]||finishSetup);
    NSString *title=finishSetup?@"Finish AFP setup":([action isEqualToString:@"update"]?@"Update Netatalk":([action isEqualToString:@"current"]?@"Netatalk is up to date":@"Install Netatalk"));
    [self.updateInstallButton setTitle:title];[self.updateInstallButton setEnabled:actionable&&!self.busy&&!self.updateChecking];
    [self.updateCheckButton setEnabled:!self.busy&&!self.updateChecking];[self.updateReleaseButton setEnabled:[S(status[@"latestURL"])length]>0];
    if(self.updateChecking||self.packageInstalling)[self.updateSpinner startAnimation:nil];else [self.updateSpinner stopAnimation:nil];
    NSTimeInterval checked=[status[@"checkedAtEpoch"]doubleValue];
    NSString *when=checked>0?[NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:checked] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]:@"not checked yet";
    [self.updateChecked setStringValue:[NSString stringWithFormat:@"Last check: %@. %@",when,[self dailyUpdatesEnabled]?@"Checks run about once every 24 hours while this app is open.":@"Automatic checks are off."]];
    [self.updateText setString:[S(status[@"output"])length]?S(status[@"output"]):@"Check results and installation errors appear here. Full operation output is also kept in Activity & Diagnostics."];
    NSButton *navigation=[self.navButtons count]>7?self.navButtons[7]:nil;
    [navigation setTitle:[status[@"updateAvailable"]boolValue]?@"Updates available":@"Updates"];
}
- (void)scheduledUpdateCheck:(id)sender {
    if(AFPSmokeReportPath||self.busy||self.updateChecking||![self dailyUpdatesEnabled])return;
    NSTimeInterval last=MAX([self.packageStatus[@"checkedAtEpoch"]doubleValue],self.updateLastAttempt);
    if(last<=0||[[NSDate date]timeIntervalSince1970]-last>=24*60*60)[self checkUpdates:nil];
}
- (void)checkUpdates:(id)sender {
    if(self.busy||self.updateChecking)return;
    self.updateChecking=YES;self.updateLastAttempt=[[NSDate date]timeIntervalSince1970];[self updatePackageDisplay];
    [self performSelectorInBackground:@selector(packageCheckThread:) withObject:[self.packageStatus copy]?:@{}];
}
- (void)packageCheckThread:(NSDictionary *)cached {@autoreleasepool{
    NSDictionary *result;
    @try{result=PackageCheck();}
    @catch(NSException *error){NSMutableDictionary *failed=[cached mutableCopy]?:[NSMutableDictionary dictionary];failed[@"ok"]=@NO;failed[@"message"]=[error reason]?:@"Update check failed.";failed[@"output"]=failed[@"message"];failed[@"checkedAtEpoch"]=@([[NSDate date]timeIntervalSince1970]);result=failed;}
    [self performSelectorOnMainThread:@selector(packageCheckDone:) withObject:result waitUntilDone:NO];
}}
- (void)packageCheckDone:(NSDictionary *)result {
    self.updateChecking=NO;self.packageStatus=result?:@{};[self updatePackageDisplay];
    if(![result[@"ok"]boolValue])Log([@"Netatalk update check failed: "stringByAppendingString:S(result[@"message"])]);
}
- (void)toggleDailyUpdates:(id)sender {
    NSMutableDictionary *changed=[self.prefs mutableCopy];changed[@"checkNetatalkUpdates"]=@([sender state]==NSControlStateValueOn);
    @try{SavePrefs(changed);self.prefs=changed;[self updatePackageDisplay];if([sender state]==NSControlStateValueOn)[self scheduledUpdateCheck:nil];}
    @catch(NSException *error){Alert(@"Update-check preference was not saved",[error reason],@[@"OK"]);[self drawPage];}
}
- (void)installPackage:(id)sender {
    if(self.busy||self.updateChecking)return;
    NSDictionary *status=self.packageStatus;
    if(![status[@"ok"]boolValue]||![status[@"canInstall"]boolValue]){[self checkUpdates:nil];return;}
    if(![self.snapshot[@"processStatusKnown"]boolValue]){Alert(@"Server status unavailable",@"Refresh server status in Overview before installing or updating Netatalk.",@[@"OK"]);return;}
    if([self.snapshot[@"running"]boolValue]){if(Alert(@"Stop Netatalk before updating",@"Clients must be disconnected and the server stopped before package changes. Use Overview to stop the server when it is safe to interrupt connected clients.",@[@"Show Overview",@"Cancel"])==NSAlertFirstButtonReturn){self.page=0;[self drawPage];}return;}
    BOOL updating=[S(status[@"action"])isEqualToString:@"update"];
    BOOL finishSetup=[S(status[@"action"])isEqualToString:@"current"]&&[status[@"installed"]boolValue]&&[status[@"pamReady"]isKindOfClass:[NSNumber class]]&&![status[@"pamReady"]boolValue];
    NSString *body=finishSetup?@"Netatalk is already current. Complete AFP account-authentication setup through the normal macOS administrator dialog? Netatalk will not be reinstalled. Existing configuration and shared files are preserved. The server stays stopped and no boot service is enabled.":[NSString stringWithFormat:@"%@ Netatalk %@ using Homebrew? This can take several minutes. Existing afp.conf and shared files are preserved. The daemon stays stopped and no boot service is enabled. AFP authentication setup may request approval in the normal macOS administrator dialog. Review the result before starting the server.",updating?@"Update to":@"Install",S(status[@"latestVersion"])];
    if(Alert(finishSetup?@"Finish AFP setup?":(updating?@"Update Netatalk?":@"Install Netatalk?"),body,@[finishSetup?@"Finish setup":(updating?@"Update":@"Install"),@"Cancel"])!=NSAlertFirstButtonReturn)return;
    [self beginJob:@{@"kind":@"packageInstall",@"setupOnly":@(finishSetup)}];
}
- (void)openPackageRelease:(id)sender {
    NSString *address=S(self.packageStatus[@"latestURL"]);NSURL *url=[NSURL URLWithString:address];
    if([[url scheme]isEqualToString:@"https"]&&[[url host]isEqualToString:@"github.com"]&&[[url path]hasPrefix:@"/Netatalk/netatalk/releases/"])[[NSWorkspace sharedWorkspace]openURL:url];
}
- (void)drawSettings{CGFloat w=[self.content bounds].size.width;NSDictionary *g=self.snapshot[@"global"]?:[NSDictionary dictionary];
    Label(self.content,@"Settings",NSMakeRect(0,0,w,34),24,YES);Label(self.content,@"Netatalk configuration",NSMakeRect(0,48,w,23),14,YES);self.configField=Field(self.content,S(self.snapshot[@"config"]),NSMakeRect(0,78,w-140,26),NO);[self.configField setEditable:NO];Button(self.content,@"Choose...",NSMakeRect(w-130,75,125,32),self,@selector(chooseConfig:));
    Label(self.content,@"Startup - independent choices",NSMakeRect(0,124,w,25),16,YES);
    self.appLogin=Check(self.content,@"Open AFP Server when I log in",NSMakeRect(0,159,w,24),ServiceState([SMAppService mainAppService])==1,self,@selector(toggleLogin:));
    self.serverBoot=Check(self.content,@"Start the AFP server at system boot (before login)",NSMakeRect(0,191,w,24),[self.snapshot[@"boot"]boolValue],self,@selector(toggleBoot:));
    SMAppService *agent=[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]];self.autoMetadata=Check(self.content,@"Run automatic metadata care for the selected share",NSMakeRect(0,223,w,24),[self.prefs[@"automaticImport"]boolValue]&&ServiceState(agent)==1,self,@selector(toggleMetadata:));
    Note(self.content,[NSString stringWithFormat:@"App: %@  |  Metadata agent: %@. The worker checks every 60 seconds and pauses when clients are connected.",ServiceStatus([SMAppService mainAppService]),ServiceStatus(agent)],NSMakeRect(0,253,w-190,40));Button(self.content,@"Login Items settings",NSMakeRect(w-183,252,180,30),self,@selector(openLoginSettings:));
    Label(self.content,@"AFP configuration",NSMakeRect(0,307,w,24),16,YES);Label(self.content,@"Server name",NSMakeRect(0,347,132,22),12,NO);self.nameField=Field(self.content,S(g[@"server name"]),NSMakeRect(145,343,MAX(220,w-480),26),NO);Label(self.content,@"TCP port",NSMakeRect(w-280,347,90,22),12,NO);self.portField=Field(self.content,[S(g[@"afp port"])length]?g[@"afp port"]:@"548",NSMakeRect(w-180,343,174,26),NO);
    self.statsToggle=Check(self.content,@"Enable authenticated session statistics",NSMakeRect(0,383,w/2,24),YesValue(g[@"afpstats"]),nil,NULL);Label(self.content,@"Statistics group",NSMakeRect(w/2+20,385,120,22),12,NO);self.statsGroup=Field(self.content,[S(g[@"afpstats group"])length]?g[@"afpstats group"]:@"admin",NSMakeRect(w/2+150,381,w/2-157,26),NO);
    self.shellToggle=Check(self.content,@"Allow sharing accounts without a login shell",NSMakeRect(0,420,w,24),[S(g[@"valid shellcheck"])length]>0 && !YesValue(g[@"valid shellcheck"]),nil,NULL);
    Label(self.content,@"Login methods",NSMakeRect(0,460,132,22),12,NO);self.uamField=Field(self.content,[S(g[@"uam list"])length]?g[@"uam list"]:@"uams_dhx2.so",NSMakeRect(145,456,w-151,26),NO);
    Note(self.content,@"DHX2 is the safe default. Legacy DHX, clear-text and guest methods are not enabled automatically. Use old clients only on a trusted LAN; do not expose AFP to the public Internet.",NSMakeRect(0,493,w,43));Button(self.content,@"Preview & apply server settings",NSMakeRect(0,550,255,32),self,@selector(applySettings:));Button(self.content,@"Worker status",NSMakeRect(269,550,140,32),self,@selector(workerStatus:));Button(self.content,@"Remove old v1-v6 agent",NSMakeRect(423,550,202,32),self,@selector(removeOldAgent:));Button(self.content,@"Uninstall app…",NSMakeRect(639,550,170,32),self,@selector(uninstallApp:));
    Note(self.content,@"The server daemon is your existing Netatalk installation. The app never installs a second copy or changes the macOS firewall. Folder access may also require macOS Privacy permissions.",NSMakeRect(0,601,w,48));
}
- (void)updateDisplay{
    BOOL known=[self.snapshot[@"processStatusKnown"]boolValue],running=[self.snapshot[@"running"]boolValue],listening=[self.snapshot[@"listening"]boolValue];NSString *state=listening?@"AFP listening":(!known?@"Server status unavailable":(running?@"Process present - listener not verified":@"Server stopped"));[self.headerStatus setStringValue:[NSString stringWithFormat:@"%@  |  %@",state,S(self.snapshot[@"version"])]];[self.headerStatus setTextColor:listening?[NSColor systemGreenColor]:(running?[NSColor systemOrangeColor]:[NSColor secondaryLabelColor])];
    [self.startButton setEnabled:known&&!self.busy&&!running];[self.stopButton setEnabled:known&&!self.busy&&running];[self.restartButton setEnabled:known&&!self.busy&&running];[self.lastRefresh setStringValue:self.busy?@"Operation in progress...":([S(self.snapshot[@"timestamp"])length]?[@"Updated "stringByAppendingString:self.snapshot[@"timestamp"]]:@"Discovering...")];
    NSDictionary *share=[self selectedShare];[self.footerShare setStringValue:share?[NSString stringWithFormat:@"Selected share: %@  -  %@",share[@"name"],share[@"path"]]:@"Selected share: unavailable - choose a share explicitly"];[self.footerConfig setStringValue:[NSString stringWithFormat:@"Configuration: %@",[S(self.snapshot[@"config"])length]?self.snapshot[@"config"]:@"not found"]];[[self.statusItem button]setTitle:listening?@"AFP On":@"AFP"];
    if(self.overviewStatus){[self.overviewStatus setStringValue:state];[self.overviewStatus setTextColor:listening?[NSColor systemGreenColor]:(running?[NSColor systemOrangeColor]:[NSColor labelColor])];NSMutableArray *addresses=[NSMutableArray array];for(NSDictionary *a in self.snapshot[@"addresses"])[addresses addObject:[NSString stringWithFormat:@"%@ (%@)",a[@"address"],a[@"interface"]]];[self.overviewIP setStringValue:[addresses count]?[addresses componentsJoinedByString:@"\n"]:@"No non-loopback IPv4 address found."];NSMutableArray *listeners=[NSMutableArray array];for(NSDictionary *r in self.snapshot[@"sockets"])if([r[@"state"]isEqualToString:@"LISTEN"])[listeners addObject:S(r[@"local"])];NSString *sessions=[self.snapshot[@"sessionsReadable"]boolValue]?[NSString stringWithFormat:@"%lu authenticated session(s)",(unsigned long)[self.snapshot[@"sessions"]count]]:@"Session access unavailable";[self.overviewDetails setStringValue:[NSString stringWithFormat:@"Listeners: %@\n%@\nConfigured shares: %lu\nServer at system boot: %@\nApp login item: %@\nClosing or quitting this app does not stop Netatalk.",[listeners count]?[listeners componentsJoinedByString:@", "]:@"none verified",sessions,(unsigned long)[self.snapshot[@"shares"]count],[self.snapshot[@"boot"]boolValue]?@"enabled":@"disabled",ServiceStatus([SMAppService mainAppService])]];[self.overviewWarnings setStringValue:[self.snapshot[@"warnings"]count]?[self.snapshot[@"warnings"]componentsJoinedByString:@"\n\n"]:@"Use Shares to choose directories and Accounts to manage access. The addresses shown are local interface addresses; firewall and network routing still determine reachability."];}
    if(self.connectionNote){NSDictionary *s=[self connectionSnapshot];BOOL stale=s==self.adminSnapshot;[self.connectionNote setStringValue:stale?[NSString stringWithFormat:@"Administrator snapshot from %@ - not a live privileged feed. Refresh this snapshot for current data.",s[@"timestamp"]]:([s[@"sessionsReadable"]boolValue]?@"Automatically refreshed every 5 seconds. OS process UIDs are shown separately from authenticated AFP usernames.":@"Authenticated session data is unavailable, not zero. Enable session statistics in Settings or request an administrator snapshot.")];[self.sessionRaw setString:S(s[@"sessionRaw"])];}
    [self updatePackageDisplay];
    [self.sharesTable reloadData];[self.sessionsTable reloadData];[self.socketsTable reloadData];[self.accountsTable reloadData];
}
- (void)refresh:(id)sender{if(self.busy||self.refreshing||self.editing)return;self.refreshing=YES;NSString *cfg=S(self.prefs[@"configPath"]);[self performSelectorInBackground:@selector(refreshThread:)withObject:cfg];}
- (void)refreshThread:(NSString *)cfg{@autoreleasepool{NSDictionary *result;@try{result=Snapshot(cfg);}@catch(NSException *e){result=@{@"warnings":@[[e reason]],@"timestamp":Stamp()};}[self performSelectorOnMainThread:@selector(refreshDone:)withObject:result waitUntilDone:NO];}}
- (void)refreshDone:(NSDictionary *)s{self.refreshing=NO;self.snapshot=s;if(![S(self.prefs[@"selectedSection"])length]&&[s[@"shares"]count]){self.prefs[@"selectedSection"]=s[@"shares"][0][@"section"];@try{SavePrefs(self.prefs);}@catch(NSException *e){Log([e reason]);}}if(self.rebuildAfterRefresh&&!self.editing){self.rebuildAfterRefresh=NO;[self drawPage];}[self updateDisplay];}
- (void)beginJob:(NSDictionary *)job{if(self.busy){NSBeep();return;}self.busy=YES;self.packageInstalling=[S(job[@"kind"])isEqualToString:@"packageInstall"];self.packageSetupOnly=self.packageInstalling&&[job[@"setupOnly"]boolValue];[self.spinner startAnimation:nil];[self updateDisplay];[self performSelectorInBackground:@selector(jobThread:)withObject:job];}
- (void)jobThread:(NSDictionary *)job{@autoreleasepool{NSDictionary *result;@try{NSString *kind=S(job[@"kind"]);if([kind isEqualToString:@"admin"])result=AdminCall(job[@"request"],job[@"secret"]);else if([kind isEqualToString:@"packageInstall"])result=PackageInstallLatest();else if([kind isEqualToString:@"users"])result=@{@"ok":@YES,@"users":Accounts(),@"silent":@YES};else if([kind isEqualToString:@"metadata"])result=MetadataRun(job[@"prefs"],[job[@"repair"]boolValue],NO);else if([kind isEqualToString:@"test"])result=MetadataTest(job[@"prefs"]);else if([kind isEqualToString:@"copy"])result=MetadataCopy(job[@"prefs"],job[@"source"],job[@"target"]);else if([kind isEqualToString:@"diagnostics"]){NSMutableString *out=[NSMutableString stringWithFormat:@"AFP Server %@\n%@\n\n",AFP_VERSION,Stamp()];NSDictionary *i=Installation(S(job[@"prefs"][@"configPath"]));[out appendFormat:@"%@\n\n",JSON(i)];for(NSString *tool in @[@"netatalk",@"netatalkd",@"afpd",@"afpstats",@"nad",@"dbd",@"asip-status"])[out appendFormat:@"%@: %@\n",tool,Tool(tool)?:@"not found"];[out appendFormat:@"\nSTATISTICS\n%@\nTCP SOCKETS (current user)\n%@\n",Run(@"afpstats",[NSArray array],5,nil)[@"out"],Run(@"lsof",@[@"-nP",@"-a",@"-c",@"afpd",@"-iTCP"],5,nil)[@"out"]];NSString *cfg=S(i[@"config"]);if([cfg length]){AFPConfig *c=[[AFPConfig alloc]initWithText:ReadText(cfg)];NSString *ext=S([c global][@"extmap file"]);if(![ext length])ext=[[cfg stringByDeletingLastPathComponent]stringByAppendingPathComponent:@"extmap.conf"];if([[NSFileManager defaultManager]isReadableFileAtPath:ext])[out appendFormat:@"\nEXTENSION MAPPINGS (%@)\n%@\n",ext,ReadText(ext)];NSString *log=S([c global][@"log file"]);if([log hasPrefix:@"/"])[out appendFormat:@"\nSERVER LOG (last 80 lines)\n%@\n",Run(@"/usr/bin/tail",@[@"-n",@"80",log],5,nil)[@"out"]];NSArray *ports=[Match(@"^[0-9]+$",S([c global][@"afp port"])) count]?@[[c global][@"afp port"]]:@[@"548"];if(Tool(@"asip-status"))[out appendFormat:@"\nAFP CAPABILITIES\n%@\n",Run(@"asip-status",@[@"127.0.0.1",ports[0]],6,nil)[@"out"]];}result=@{@"ok":@YES,@"message":@"Diagnostics completed.",@"output":out};}else if([kind isEqualToString:@"oldAgent"]){OldAgentsRemove();result=@{@"ok":@YES,@"message":@"Old agent removed. Netatalk and shared files were not changed."};}else Fail(@"Unknown operation.");}
        @catch(NSException *e){result=@{@"ok":@NO,@"message":[e reason]?:@"Operation failed."};}
        NSMutableDictionary *reply=[result mutableCopy];reply[@"kind"]=job[@"kind"]?:@"";if([job[@"kind"]isEqualToString:@"admin"])reply[@"adminAction"]=S(job[@"request"][@"action"]);[self performSelectorOnMainThread:@selector(jobDone:)withObject:reply waitUntilDone:NO];}}
- (void)jobDone:(NSDictionary *)r{if([S(r[@"kind"])isEqualToString:@"packageInstall"]){NSMutableDictionary *merged=[self.packageStatus mutableCopy]?:[NSMutableDictionary dictionary];[merged addEntriesFromDictionary:r];self.packageStatus=merged;self.adminSnapshot=nil;}self.packageInstalling=NO;self.packageSetupOnly=NO;if([S(r[@"kind"])isEqualToString:@"admin"]&&![S(r[@"adminAction"])isEqualToString:@"snapshot"])self.adminSnapshot=nil;self.busy=NO;[self.spinner stopAnimation:nil];if(r[@"users"])self.users=r[@"users"];if(r[@"snapshot"]){self.adminSnapshot=r[@"snapshot"];self.snapshot=r[@"snapshot"];}if([S(r[@"message"])length])Log([NSString stringWithFormat:@"%@ %@\n%@",[r[@"ok"]boolValue]?@"OK":@"ERROR",r[@"message"],S(r[@"output"])]);if(self.metadataText){[self.metadataText setString:JSON(r)];}if(self.activityText)[self.activityText setString:LogTail()];[self updateDisplay];
    if(![r[@"silent"]boolValue]){NSString *body=S(r[@"output"]);if([body length]>1400)body=[[body substringToIndex:1400]stringByAppendingString:@"\n\nFull output is available in Activity & Diagnostics."];if(r[@"counts"])body=[NSString stringWithFormat:@"Share: %@\n\n%@\n\nBackup: %@",S(r[@"share"]),JSON(r[@"counts"]),[S(r[@"backup"])length]?r[@"backup"]:@"No changes required a backup."];if([r[@"path"]length])body=[NSString stringWithFormat:@"%@\n\n%@",r[@"path"],body];Alert(S(r[@"message"]),body,@[@"OK"]);}
    if([S(r[@"kind"])isEqualToString:@"packageInstall"]){self.rebuildAfterRefresh=YES;[self checkUpdates:nil];}if([S(r[@"kind"])isEqualToString:@"admin"]){self.rebuildAfterRefresh=YES;if(self.page==3){[self beginJob:@{@"kind":@"users"}];}}[self refresh:nil];}
- (NSMutableDictionary *)request:(NSString *)action{return [@{@"action":action,@"config":S(self.snapshot[@"config"]),@"section":S(self.prefs[@"selectedSection"])}mutableCopy];}
- (void)admin:(NSDictionary *)req secret:(NSString *)secret{NSMutableDictionary *j=[@{@"kind":@"admin",@"request":req}mutableCopy];if(secret)j[@"secret"]=secret;[self beginJob:j];}
- (void)serverAction:(id)sender{if(self.busy)return;if(![self.snapshot[@"processStatusKnown"]boolValue]){Alert(@"Server status unavailable",@"Refresh server status or request an administrator snapshot before changing the server state.",@[@"OK"]);return;}NSInteger tag=[sender tag];NSString *action=tag==1?@"start":(tag==2?@"stop":@"restart");if(tag!=1&&Alert(tag==2?@"Stop AFP server?":@"Restart AFP server?",@"All connected AFP clients will be disconnected. Ongoing copies or writes may be interrupted. Save files and disconnect clients first.",@[@"Continue",@"Cancel"])!=NSAlertFirstButtonReturn)return;[self admin:[self request:action]secret:nil];}
- (void)adminRefresh:(id)s{[self admin:[self request:@"snapshot"]secret:nil];}
- (void)copyAddress:(id)s{NSDictionary *a=[self.snapshot[@"addresses"]firstObject];if(!a){NSBeep();return;}NSString *port=S(self.snapshot[@"global"][@"afp port"]);if(![port length])port=@"548";NSString *url=[NSString stringWithFormat:@"afp://%@:%@",a[@"address"],port];[[NSPasteboard generalPasteboard]clearContents];[[NSPasteboard generalPasteboard]setString:url forType:@"public.utf8-plain-text"];[self.lastRefresh setStringValue:@"AFP address copied"];
}
- (NSDictionary *)selectedRow:(NSTableView *)t{NSInteger n=[t selectedRow];NSArray *a=[self rows:[t tag]];if(n<0||(NSUInteger)n>=[a count]){Alert(@"Select a row first",@"Click the entry you want to manage.",@[@"OK"]);return nil;}return a[n];}
- (void)useShare:(id)sender{NSDictionary *s=[self selectedRow:self.sharesTable];if(!s)return;@try{if([self.prefs[@"automaticImport"]boolValue]&&![S(self.prefs[@"selectedSection"])isEqualToString:s[@"section"]]){if(Alert(@"Switch the maintenance share?",@"Automatic care will be disabled until you explicitly enable it for the new share. The old share and its files are not changed.",@[@"Switch share",@"Cancel"])!=NSAlertFirstButtonReturn)return;self.prefs[@"automaticImport"]=@NO;[[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]]unregisterAndReturnError:NULL];}self.prefs[@"selectedSection"]=s[@"section"];SavePrefs(self.prefs);[self updateDisplay];}@catch(NSException *e){Alert(@"Share selection failed",[e reason],@[@"OK"]);}}
- (void)openShare:(id)sender{NSDictionary *s=[self selectedRow:self.sharesTable]?:[self selectedShare];if(s)[[NSWorkspace sharedWorkspace]openURL:[NSURL fileURLWithPath:s[@"path"]]];}
- (void)chooseDialogFolder:(id)sender{NSString *p=Choose(YES,@"Choose the folder to export over AFP",[self.dialogPath stringValue]);if(p)[self.dialogPath setStringValue:p];}
- (void)addShare:(id)sender{[self editShareRecord:nil];}
- (void)editShare:(id)sender{NSDictionary *s=[self selectedRow:self.sharesTable];if(s)[self editShareRecord:s];}
- (void)editShareRecord:(NSDictionary *)share{
    if(self.busy)return;self.editing=YES;@try{NSString *cfg=S(self.snapshot[@"config"]);if(![cfg length])Fail(@"Select an existing afp.conf in Settings first.");AFPConfig *c=[[AFPConfig alloc]initWithText:ReadText(cfg)];NSDictionary *opts=share[@"options"]?:[NSDictionary dictionary];NSAlert *a=[NSAlert new];[a setMessageText:share?@"Edit AFP share":@"Add AFP share"];[a setInformativeText:@"The folder path is written to afp.conf. Files are not moved. Access is also limited by macOS filesystem permissions."];[a addButtonWithTitle:@"Review changes"];[a addButtonWithTitle:@"Cancel"];
        AFPFlippedView *v=[[AFPFlippedView alloc]initWithFrame:NSMakeRect(0,0,620,325)];Label(v,@"Config section",NSMakeRect(0,6,125,23),12,NO);NSTextField *section=Field(v,share?share[@"section"]:@"Classic",NSMakeRect(140,2,475,26),NO);[section setEditable:!share];Label(v,@"AFP volume name",NSMakeRect(0,43,130,23),12,NO);NSTextField *name=Field(v,share?share[@"name"]:@"Classic Files",NSMakeRect(140,39,475,26),NO);Label(v,@"Shared folder",NSMakeRect(0,80,125,23),12,NO);self.dialogPath=Field(v,share?share[@"path"]:@"",NSMakeRect(140,76,365,26),NO);Button(v,@"Choose...",NSMakeRect(512,73,106,32),self,@selector(chooseDialogFolder:));Label(v,@"Allowed users",NSMakeRect(0,117,125,23),12,NO);NSTextField *users=Field(v,S(opts[@"valid users"]),NSMakeRect(140,113,475,26),NO);[users setPlaceholderString:@"alice afp_user @group (blank: server default)"];Label(v,@"Allowed networks",NSMakeRect(0,154,130,23),12,NO);NSTextField *hosts=Field(v,S(opts[@"hosts allow"]),NSMakeRect(140,150,475,26),NO);[hosts setPlaceholderString:@"Optional, e.g. 192.0.2.0/24"];
        NSButton *ro=Check(v,@"Read-only share",NSMakeRect(140,190,450,24),YesValue(opts[@"read only"]),nil,NULL);NSButton *classic=Check(v,@"Apply native Mac metadata options (Netatalk 4.1 or newer)",NSMakeRect(140,224,470,24),[S(opts[@"ea"])isEqualToString:@"sys"]||!share,nil,NULL);Note(v,@"Leave unchecked to preserve current storage options. Changing an AppleDouble backend does not recreate lost data. Back up your archive first; inspect and restore metadata separately.",NSMakeRect(0,270,620,50));[a setAccessoryView:v];if([a runModal]!=NSAlertFirstButtonReturn)return;
        NSString *sec=Trim([section stringValue]),*path=SafeRoot(Trim([self.dialogPath stringValue]));NSString *volume=Trim([name stringValue]);if(![volume length]||[volume containsString:@":"]||[volume containsString:@"\n"])Fail(@"The AFP volume name is empty or invalid.");if(!share&&[c section:sec])Fail(@"That config section already exists.");NSMutableDictionary *o=[@{@"path":path,@"volume name":volume,@"read only":[ro state]==NSControlStateValueOn?@"yes":@"no",@"valid users":Trim([users stringValue]),@"hosts allow":Trim([hosts stringValue])}mutableCopy];if([classic state]==NSControlStateValueOn){NSArray *ver=Match(@"(?:Netatalk|netatalk)[^0-9]*(\\d+)\\.(\\d+)",S(self.snapshot[@"version"]));if(!ver||[ver[1]intValue]<4||([ver[1]intValue]==4&&[ver[2]intValue]<1))Fail(@"Native macOS FinderInfo integration requires Netatalk 4.1 or newer. The installed version was not verified as compatible.");o[@"ea"]=@"sys";o[@"mac charset"]=@"MAC_ROMAN";o[@"convert appledouble"]=@"yes";}
        [c patchSection:sec options:o create:!share];[c validate];[self previewConfig:c path:cfg];
    }@catch(NSException *e){Alert(@"Share not changed",[e reason],@[@"OK"]);}@finally{self.dialogPath=nil;self.editing=NO;}}
- (void)previewConfig:(AFPConfig *)c path:(NSString *)path{NSAlert *a=[NSAlert new];[a setMessageText:@"Apply this configuration?"];[a setInformativeText:@"A backup is created before writing. A running server is restarted, disconnecting clients. Failed restart verification triggers a rollback. A stopped server stays stopped."];[a addButtonWithTitle:@"Apply"];[a addButtonWithTitle:@"Cancel"];AFPFlippedView *v=[[AFPFlippedView alloc]initWithFrame:NSMakeRect(0,0,680,300)];TextBox(v,NSMakeRect(0,0,680,300),[c text]);[a setAccessoryView:v];if([a runModal]!=NSAlertFirstButtonReturn)return;NSMutableDictionary *r=[self request:@"applyConfig"];r[@"config"]=path;r[@"expected"]=c.original;r[@"text"]=[c text];[self admin:r secret:nil];}
- (void)removeShare:(id)sender{NSDictionary *s=[self selectedRow:self.sharesTable];if(!s||self.busy)return;if(Alert(@"Remove this AFP share?",[NSString stringWithFormat:@"Remove [%@] from afp.conf? Its folder and all files stay on disk. Connected clients will be disconnected if the running server is restarted.",s[@"section"]],@[@"Review removal",@"Cancel"])!=NSAlertFirstButtonReturn)return;@try{NSString *p=S(self.snapshot[@"config"]);AFPConfig *c=[[AFPConfig alloc]initWithText:ReadText(p)];[c removeSection:s[@"section"]];[self previewConfig:c path:p];}@catch(NSException *e){Alert(@"Share not removed",[e reason],@[@"OK"]);}}
- (void)disconnect:(id)sender{NSDictionary *s=[self selectedRow:self.socketsTable];if(!s)return;if(![s[@"state"]isEqualToString:@"ESTABLISHED"]){Alert(@"Choose an established connection",@"Listening sockets cannot be disconnected as client sessions.",@[@"OK"]);return;}if(Alert(@"Disconnect this AFP client?",[NSString stringWithFormat:@"%@ -> %@\nPID %@. Ongoing file writes may be interrupted. The process is rechecked before the signal is sent.",s[@"local"],s[@"remote"],s[@"pid"]],@[@"Disconnect",@"Cancel"])!=NSAlertFirstButtonReturn)return;NSMutableDictionary *r=[self request:@"disconnect"];r[@"pid"]=s[@"pid"];[self admin:r secret:nil];}
- (void)addAccount:(id)sender{[self accountDialog:nil];}
- (void)changePassword:(id)sender{NSDictionary *u=[self selectedRow:self.accountsTable];if(!u)return;if(![u[@"managed"]boolValue]){Alert(@"Existing account",@"Personal macOS account passwords are not changed here. Use System Settings for that account.",@[@"OK"]);return;}[self accountDialog:u];}
- (void)accountDialog:(NSDictionary *)user{if(self.busy)return;self.editing=YES;@try{NSAlert *a=[NSAlert new];[a setMessageText:user?@"Change sharing-account password":@"Create sharing account"];[a setInformativeText:@"New accounts are local, hidden, and non-administrator, with no interactive login shell. The password is transferred to the helper through an in-memory pipe, not command arguments or a file."];[a addButtonWithTitle:user?@"Change password":@"Create account"];[a addButtonWithTitle:@"Cancel"];AFPFlippedView *v=[[AFPFlippedView alloc]initWithFrame:NSMakeRect(0,0,540,185)];Label(v,@"Account name",NSMakeRect(0,6,150,23),12,NO);NSTextField *name=Field(v,user?user[@"name"]:@"afp_mac",NSMakeRect(165,2,370,26),NO);[name setEditable:!user];Label(v,@"Display name",NSMakeRect(0,47,150,23),12,NO);NSTextField *display=Field(v,user?user[@"display"]:@"Classic Mac",NSMakeRect(165,43,370,26),NO);[display setEditable:!user];Label(v,@"New password",NSMakeRect(0,88,150,23),12,NO);NSTextField *pw=Field(v,@"",NSMakeRect(165,84,370,26),YES);Label(v,@"Repeat password",NSMakeRect(0,129,150,23),12,NO);NSTextField *again=Field(v,@"",NSMakeRect(165,125,370,26),YES);[a setAccessoryView:v];if([a runModal]!=NSAlertFirstButtonReturn)return;NSString *password=[pw stringValue];if(![password isEqualToString:[again stringValue]])Fail(@"Passwords do not match.");if([password lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<8)Fail(@"Use a password of at least 8 bytes. For very old clients, check their password/UAM limits.");NSMutableDictionary *r=[self request:user?@"resetPassword":@"createUser"];r[@"user"]=Trim([name stringValue]);r[@"display"]=Trim([display stringValue]);[pw setStringValue:@""];[again setStringValue:@""];[self admin:r secret:password];}@catch(NSException *e){Alert(@"Account not changed",[e reason],@[@"OK"]);}@finally{self.editing=NO;}}
- (void)deleteAccount:(id)sender{NSDictionary *u=[self selectedRow:self.accountsTable];if(!u)return;if(![u[@"managed"]boolValue]){Alert(@"Existing account protected",@"Only sharing accounts created by this app can be deleted here.",@[@"OK"]);return;}if(Alert(@"Remove sharing account?",[NSString stringWithFormat:@"Remove %@ from macOS? No shared files are deleted. Existing ACLs or allowlists referring to the account are not automatically rewritten.",u[@"name"]],@[@"Remove account",@"Cancel"])!=NSAlertFirstButtonReturn)return;NSMutableDictionary *r=[self request:@"deleteUser"];r[@"user"]=u[@"name"];[self admin:r secret:nil];}
- (void)grantACL:(id)sender{NSDictionary *u=[self selectedRow:self.accountsTable],*s=[self selectedShare];if(!u)return;if(!s){Alert(@"Choose a share first",@"Use Shares > Use selected.",@[@"OK"]);return;}NSInteger answer=Alert(@"Grant folder access?",[NSString stringWithFormat:@"Account: %@\nFolder: %@\n\nAdd inheritable permissions on this folder only. Existing files are not rewritten recursively. Read-only ACLs do not remove permissions the user already has. Also configure AFP Allowed users / Read only separately.",u[@"name"],s[@"path"]],@[@"Read / write",@"Read only",@"Cancel"]);if(answer!=1000&&answer!=1001)return;NSMutableDictionary *r=[self request:@"grantACL"];r[@"user"]=u[@"name"];r[@"readOnly"]=@(answer==1001);[self admin:r secret:nil];}
- (void)inspectMetadata:(id)s{[self beginJob:@{@"kind":@"metadata",@"prefs":[self.prefs copy],@"repair":@NO}];}
- (void)repairMetadata:(id)s{if(Alert(@"Restore missing Classic metadata?",@"Only the selected share is touched. Sources are backed up and retained. Existing native metadata is never replaced. Restoration pauses when AFP clients are connected or their status is unknown. This cannot recreate resource-fork data that no longer exists.",@[@"Restore missing metadata",@"Cancel"])!=1000)return;[self beginJob:@{@"kind":@"metadata",@"prefs":[self.prefs copy],@"repair":@YES}];}
- (void)testMetadata:(id)s{
    if(self.busy)return;NSDictionary *share=[self selectedShare];
    if(!share){Alert(@"Choose a share first",@"Use Shares > Use selected.",@[@"OK"]);return;}
    if(Alert(@"Create a Classic Mac test file?",[NSString stringWithFormat:@"Create a new uniquely named file in %@ with a resource fork, Type TEXT and Creator ttxt? Existing files remain unchanged. The new file remains available for testing from your Classic Mac.",share[@"path"]],@[@"Create test file",@"Cancel"])!=NSAlertFirstButtonReturn)return;
    [self beginJob:@{@"kind":@"test",@"prefs":[self.prefs copy]}];
}
- (void)importFiles:(id)s{if(self.busy)return;NSInteger kind=Alert(@"Import into the AFP share",@"Requires Netatalk's nad 4.6 or newer to preserve Mac metadata and coordinate CNID records. Existing destinations are not overwritten. Source symlinks and nested mounted volumes are rejected; copying is verified before the final item is published.",@[@"Choose file",@"Choose folder",@"Cancel"]);if(kind!=1000&&kind!=1001)return;NSString *source=Choose(kind==1001,@"Choose the source to copy",nil);if(!source)return;NSDictionary *share=[self selectedShare];if(!share)return;NSString *dest=Choose(YES,@"Choose a destination inside the selected AFP share",share[@"path"]);if(!dest)return;if(Alert(@"Import this item?",[NSString stringWithFormat:@"Copy %@ into %@? The destination must be inside the selected share. An existing destination with the same name is rejected.",source,dest],@[@"Import",@"Cancel"])!=NSAlertFirstButtonReturn)return;[self beginJob:@{@"kind":@"copy",@"prefs":[self.prefs copy],@"source":source,@"target":dest}];}
- (void)checkCNID:(id)s{[self cnid:NO];}
- (void)repairCNID:(id)s{[self cnid:YES];}
- (void)cnid:(BOOL)repair{if(Alert(repair?@"Reconcile CNID database?":@"Check CNID database?",repair?@"Netatalk will be stopped and clients disconnected. A recognised database location must be backed up first. Only the selected share is reconciled; no forced -f rebuild. The previous running state is restored afterward.":@"Netatalk will be stopped for this read-only check, disconnecting clients, then restarted if it was running. No CNID records are intentionally changed.",@[@"Continue",@"Cancel"])!=1000)return;NSMutableDictionary *r=[self request:@"cnid"];r[@"repair"]=@(repair);[self admin:r secret:nil];}
- (void)chooseConfig:(id)s{NSString *p=Choose(NO,@"Select the existing Netatalk afp.conf",[S(self.snapshot[@"config"])stringByDeletingLastPathComponent]);if(!p)return;if(![[p lastPathComponent]isEqualToString:@"afp.conf"]){Alert(@"Select afp.conf",@"The server's real configuration file is required.",@[@"OK"]);return;}@try{self.prefs[@"configPath"]=p;self.prefs[@"selectedSection"]=@"";self.prefs[@"automaticImport"]=@NO;SavePrefs(self.prefs);[[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]]unregisterAndReturnError:NULL];self.rebuildAfterRefresh=YES;[self refresh:nil];}@catch(NSException *e){Alert(@"Could not change config selection",[e reason],@[@"OK"]);}}
- (void)applySettings:(id)s{if(self.busy)return;self.editing=YES;@try{NSString *p=S(self.snapshot[@"config"]);AFPConfig *c=[[AFPConfig alloc]initWithText:ReadText(p)];NSString *uam=Trim([self.uamField stringValue]);BOOL weak=[uam containsString:@"clrtxt"]||[uam containsString:@"guest"]||[uam containsString:@"uams_dhx.so"]||[uam containsString:@"randnum"];if(weak&&Alert(@"Legacy authentication selected",@"Guest or legacy authentication weakens protection; clear-text passwords can be observed on the network. Use only on an isolated/trusted LAN. These methods may require separately installed modules or password stores.",@[@"Use these methods",@"Cancel"])!=1000)return;
        NSString *group=Trim([self.statsGroup stringValue]);if([self.statsToggle state]==NSControlStateValueOn&&!Match(@"^[A-Za-z0-9_.-]+$",group))Fail(@"Enter a valid existing statistics group name, such as admin.");NSMutableDictionary *o=[@{@"server name":Trim([self.nameField stringValue]),@"afp port":Trim([self.portField stringValue]),@"afpstats":[self.statsToggle state]==NSControlStateValueOn?@"yes":@"no",@"afpstats group":group,@"valid shellcheck":[self.shellToggle state]==NSControlStateValueOn?@"no":@"yes",@"uam list":uam}mutableCopy];if(![uam length])Fail(@"At least one login method is required.");[c patchSection:@"Global"options:o create:YES];[c validate];[self previewConfig:c path:p];}@catch(NSException *e){Alert(@"Settings not applied",[e reason],@[@"OK"]);}@finally{self.editing=NO;}}
- (BOOL)stableAppLocation{
    NSString *b=[BundleRoot()stringByStandardizingPath];
    NSString *userApps=[[NSHomeDirectory()stringByAppendingPathComponent:@"Applications"]stringByAppendingString:@"/"];
    if([b containsString:@"AppTranslocation"]||(![b hasPrefix:@"/Applications/"]&&![b hasPrefix:userApps])){
        Alert(@"Move the app to Applications first",@"Quit the app, move AFP Server.app to /Applications or ~/Applications, reopen it, then enable startup services. You can use the app normally from Downloads.",@[@"OK"]);
        return NO;
    }
    return YES;
}
- (void)toggleLogin:(id)sender{if(self.busy||([sender state]==NSControlStateValueOn&&![self stableAppLocation])){[self drawPage];return;}NSError *e=nil;SMAppService *s=[SMAppService mainAppService];BOOL on=[sender state]==NSControlStateValueOn;BOOL ok=on?[s registerAndReturnError:&e]:[s unregisterAndReturnError:&e];if(!ok)Alert(@"Login item could not be changed",S([e localizedDescription]),@[@"OK"]);else if([s status]==2)Alert(@"Approval required",@"Enable AFP Server in System Settings > General > Login Items & Extensions.",@[@"OK"]);Log([NSString stringWithFormat:@"App login item: %@",ServiceStatus(s)]);[self drawPage];}
- (void)toggleBoot:(id)sender{if(self.busy){[self drawPage];return;}BOOL on=[sender state]==NSControlStateValueOn;if(Alert(on?@"Start Netatalk at system boot?":@"Disable Netatalk boot startup?",on?@"The existing Netatalk LaunchDaemon will be registered/enabled and the server started. A running server may restart and disconnect clients. This runs independently of the app and may run before login.":@"The boot registration will be disabled. A running Homebrew server is restarted as a one-time service, which briefly disconnects clients.",@[@"Apply",@"Cancel"])!=1000){[sender setState:!on];return;}NSMutableDictionary *r=[self request:@"boot"];r[@"enabled"]=@(on);[self admin:r secret:nil];}
- (void)toggleMetadata:(id)sender{BOOL on=[sender state]==NSControlStateValueOn;@try{if(self.busy||(on&&![self stableAppLocation])){[self drawPage];return;}SMAppService *svc=[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]];NSError *e=nil;
        if(on){NSDictionary *s=[self selectedShare];if(!s)Fail(@"Choose an existing share first.");NSString *root=SafeRoot(s[@"path"]);NSDictionary *a=[[NSFileManager defaultManager]attributesOfItemAtPath:root error:NULL];if(Alert(@"Enable automatic metadata care?",[NSString stringWithFormat:@"Only %@ is maintained. Every 60 seconds the native worker checks for stable AppleDouble files. It pauses while AFP users are connected or session status is unavailable. Sources are backed up and retained. Existing metadata is not overwritten.",root],@[@"Enable",@"Cancel"])!=1000){[self drawPage];return;}self.prefs[@"maintenanceIdentity"]=[NSString stringWithFormat:@"%@:%@:%@",root,S(a[NSFileSystemNumber]),S(a[NSFileSystemFileNumber])];self.prefs[@"automaticImport"]=@YES;SavePrefs(self.prefs);if(![svc registerAndReturnError:&e]){self.prefs[@"automaticImport"]=@NO;SavePrefs(self.prefs);Fail(S([e localizedDescription]));}if([svc status]==2)Alert(@"Background item needs approval",@"Approve AFP Server in System Settings > General > Login Items & Extensions. Care is not active until approved.",@[@"OK"]);
        }else{self.prefs[@"automaticImport"]=@NO;SavePrefs(self.prefs);if(![svc unregisterAndReturnError:&e]&&[svc status]!=0)Fail(S([e localizedDescription]));}
        Log([NSString stringWithFormat:@"Metadata care: %@",ServiceStatus(svc)]);[self drawPage];
    }@catch(NSException *e){Alert(@"Metadata service not changed",[e reason],@[@"OK"]);[self drawPage];}}
- (void)openLoginSettings:(id)s{[SMAppService openSystemSettingsLoginItems];}
- (void)workerStatus:(id)s{NSDictionary *last=JSONFile([SupportDir()stringByAppendingPathComponent:@"metadata-worker-status.json"]);NSString *service=[NSString stringWithFormat:@"gui/%d/%@",getuid(),AFP_AGENT];NSDictionary *r=Run(@"/bin/launchctl",@[@"print",service],4,nil);NSString *state=@"Not loaded";if([r[@"ok"]boolValue]){NSArray *m=Match(@"state = ([^\\r\\n]+)",r[@"out"]);state=m?Trim(m[1]):@"Loaded";}NSString *details=[NSString stringWithFormat:@"Registration: %@\nlaunchd: %@\n\nA timer-based agent normally exits between checks; loaded does not mean a process is currently running.\n\nLast result:\n%@",ServiceStatus([SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]]),state,last?JSON(last):@"No worker run recorded yet."];Alert(@"Metadata worker status",details,@[@"OK"]);}
- (void)removeOldAgent:(id)s{if(Alert(@"Remove the old script agent?",@"Only the known v1-v6 metadata agent and its dot_clean worker scripts are removed. This does not remove Netatalk, the new worker, shared files, or afp.conf.",@[@"Remove old agent",@"Cancel"])==1000)[self beginJob:@{@"kind":@"oldAgent"}];}
- (void)uninstallApp:(id)sender {
    if(self.busy||self.editing){NSBeep();return;}
    NSString *bundle=BundleRoot();
    if(![bundle hasSuffix:@".app"]){Alert(@"Cannot locate the app",@"The current application bundle could not be located.",@[@"OK"]);return;}
    NSString *body=[NSString stringWithFormat:@"Move this copy to the Trash?\n%@\n\nThe app's login item and metadata worker will be unregistered first. Netatalk, its startup daemon, sharing accounts, afp.conf and shared files are preserved. Logs, backups and preferences remain in your Library.",bundle];
    if(Alert(@"Uninstall AFP Server?",body,@[@"Move app to Trash",@"Cancel"])!=NSAlertFirstButtonReturn)return;
    @try{
        NSMutableDictionary *prefs=[self.prefs mutableCopy];prefs[@"automaticImport"]=@NO;SavePrefs(prefs);self.prefs=prefs;
        for(SMAppService *service in @[[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]],[SMAppService mainAppService]]){
            NSInteger state=ServiceState(service);
            if(state==SMAppServiceStatusNotRegistered||state==SMAppServiceStatusNotFound)continue;
            NSError *error=nil;
            if(![service unregisterAndReturnError:&error])Fail([NSString stringWithFormat:@"The app was retained because its startup registration could not be removed. %@",S([error localizedDescription])]);
        }
        self.busy=YES;[self.timer invalidate];self.timer=nil;[self.updateTimer invalidate];self.updateTimer=nil;[self updateDisplay];
        [[NSWorkspace sharedWorkspace]recycleURLs:@[[NSURL fileURLWithPath:bundle]] completionHandler:^(NSDictionary<NSURL *,NSURL *> *moved,NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(error){self.busy=NO;Alert(@"App could not be moved to Trash",S([error localizedDescription]),@[@"OK"]);[self beginMonitoring:nil];[self drawPage];}
                else [[NSApplication sharedApplication]terminate:nil];
            });
        }];
    }@catch(NSException *e){Alert(@"App was retained",[e reason],@[@"OK"]);[self drawPage];}
}
- (void)refreshLog:(id)s{[self.activityText setString:LogTail()];}
- (void)openLogs:(id)s{[[NSWorkspace sharedWorkspace]openURL:[NSURL fileURLWithPath:SupportDir()]];}
- (void)showConfig:(id)s{NSString *p=S(self.snapshot[@"config"]);if([p length])[[NSWorkspace sharedWorkspace]activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:p]]];}
- (void)diagnostics:(id)s{[self beginJob:@{@"kind":@"diagnostics",@"prefs":[self.prefs copy]}];}
@end
int AFPAppMain(void){NSApplication *app=[AFPApplication sharedApplication];[app setActivationPolicy:AFPSmokeReportPath?NSApplicationActivationPolicyAccessory:NSApplicationActivationPolicyRegular];__attribute__((objc_precise_lifetime)) AFPController *controller=[AFPController new];[app setDelegate:controller];[app run];(void)controller;return 0;}
