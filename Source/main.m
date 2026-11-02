#import "Core.h"
int AFPAppMain(void);
int main(int argc,const char **argv){@autoreleasepool{
    AFPInstallExceptionHandler();
    @try {
        AFPAssertObjectLayout();
        // Keep the configuration check on the actual launch path that crashed
        // in 1.1. These checks use memory only, never an existing share/config.
        NSDictionary *health=CoreSelfTest();
        if(![health[@"ok"] boolValue]) Fail(S(health[@"error"]));
    }
    @catch(NSException *e) { AFPRecordException(e); return 1; }
    if(argc==3&&strcmp(argv[1],"--ui-smoke-test")==0){
        AFPSmokeReportPath=[NSString stringWithUTF8String:argv[2]];
        return AFPAppMain();
    }

    if(argc==3&&strcmp(argv[1],"--admin")==0)return AdminMain([NSString stringWithUTF8String:argv[2]]);
    if(argc==2&&strcmp(argv[1],"--metadata-worker")==0)return WorkerMain();
    if(argc==2&&strcmp(argv[1],"--self-test")==0){NSDictionary *r=CoreSelfTest();puts([JSON(r)UTF8String]);return [r[@"ok"]boolValue]?0:1;}
    if(argc==2&&strcmp(argv[1],"--version")==0){puts("AFP Server 1.4.1 (native macOS)");return 0;}
    if(argc==2&&strcmp(argv[1],"--unregister-services")==0){NSError *e=nil;SMAppService *app=[SMAppService mainAppService],*agent=[SMAppService agentServiceWithPlistName:[AFP_AGENT stringByAppendingString:@".plist"]];BOOL a=[app status]==0||[app unregisterAndReturnError:&e];BOOL b=[agent status]==0||[agent unregisterAndReturnError:NULL];NSMutableDictionary *p=Prefs();p[@"automaticImport"]=@NO;SavePrefs(p);printf("Login item removed: %s\nMetadata agent removed: %s\nNetatalk and shared files were not changed.\n",a?"yes":"not registered or error",b?"yes":"not registered or error");return a&&b?0:1;}
    if(argc==2&&strcmp(argv[1],"--remove-old-agents")==0){@try{OldAgentsRemove();puts("Legacy metadata agent removed. Shared files and Netatalk unchanged.");return 0;}@catch(NSException *e){printf("%s\n",[[e reason]UTF8String]);return 1;}}
    if(geteuid()==0){puts("Do not run the GUI as root. Open AFP Server.app as your normal account.");return 1;}
    AFPStartupLog(@"Starting AFP Server 1.4.1, built with the local Apple SDK.");
    @try { return AFPAppMain(); }
    @catch(NSException *e) { AFPRecordException(e); return 1; }
}}
