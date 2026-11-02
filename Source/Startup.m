#import "Core.h"

NSString *AFPSmokeReportPath = nil;

static NSString *StartupLogPath(void) {
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AFPServer"];
    NSFileManager *fm=[NSFileManager defaultManager];
    NSError *err=nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&err] || ![fm isWritableFileAtPath:dir])
        dir=NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"AFPServer-startup.log"];
}
void AFPStartupLog(NSString *event) {
    @try {
        @synchronized([NSProcessInfo class]) {
            NSString *path=StartupLogPath();
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attr=[fm attributesOfItemAtPath:path error:NULL];
            if ([attr[NSFileSize] unsignedLongLongValue] > 1024*1024) {
                NSString *old=[path stringByAppendingString:@".previous"];
                [fm removeItemAtPath:old error:NULL]; [fm moveItemAtPath:path toPath:old error:NULL];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];
            if (!h) return;
            @try { [h seekToEndOfFile]; [h writeData:[[NSString stringWithFormat:@"%@  %@\n",Stamp(),S(event)] dataUsingEncoding:NSUTF8StringEncoding]]; }
            @finally { [h closeFile]; }
        }
    } @catch(NSException *ignored) { /* Diagnostics must never trigger a second exception. */ }
}
void AFPRecordException(NSException *exception) {
    @try {
        AFPStartupLog([NSString stringWithFormat:@"%@\n%@\n%@",[exception name],[exception reason],[[exception callStackSymbols] componentsJoinedByString:@"\n"]]);
    } @catch(NSException *ignored) {}
}
void AFPInstallExceptionHandler(void) { NSSetUncaughtExceptionHandler(&AFPRecordException); }

@implementation AFPApplication
- (void)reportException:(NSException *)exception {
    AFPRecordException(exception);
    if (AFPSmokeReportPath) {
        SaveJSON(@{@"ok":@NO,@"error":[exception reason]?:@"AppKit exception"},AFPSmokeReportPath);
        [self terminate:nil];
        return;
    }
    @try {
        NSAlert *alert=[NSAlert new];
        alert.messageText=@"AFP Server encountered an error";
        alert.informativeText=[NSString stringWithFormat:@"%@\n\nNo success was reported for this operation. Use Activity & diagnostics after reopening the app. Startup details are saved in ~/Library/Logs/AFPServer/AFPServer-startup.log.",[exception reason]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    } @catch(NSException *nested) { AFPRecordException(nested); }
}
@end
