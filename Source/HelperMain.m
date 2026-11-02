#import "Core.h"
// Separate command-line target. It cannot accidentally enter the GUI.
int main(int argc,const char **argv) { @autoreleasepool {
    AFPInstallExceptionHandler();
    @try {
        AFPAssertObjectLayout();
        if(argc==3 && strcmp(argv[1],"--admin")==0)
            return AdminMain([NSString stringWithUTF8String:argv[2]]);
        if(argc==2 && strcmp(argv[1],"--metadata-worker")==0) return WorkerMain();
        if(argc==2 && strcmp(argv[1],"--self-test")==0) {
            NSDictionary *r=CoreSelfTest(); puts([JSON(r) UTF8String]);
            return [r[@"ok"] boolValue]?0:1;
        }
        if(argc==2 && strcmp(argv[1],"--version")==0) {
            puts("AFP Server Helper 1.4.1 (Apple SDK)"); return 0;
        }
        fputs("AFPServerHelper: expected --admin request.json, --metadata-worker, --self-test or --version.\n",stderr);
        return 64;
    } @catch(NSException *e) {
        AFPRecordException(e); fprintf(stderr,"%s\n",[[e reason] UTF8String]); return 1;
    }
}}
