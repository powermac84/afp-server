#pragma once
#import "ApplePlatform.h"
#import "AD.h"
#define AFP_VERSION @"1.4.1"
#define AFP_AGENT @"org.local.afpserver.metadata"
NSString *S(id x);
NSString *Trim(NSString *s);
NSArray *Lines(NSString *s);
NSArray *Match(NSString *pattern,NSString *s);
void Fail(NSString *s) __attribute__((noreturn));
NSString *Stamp(void);
NSString *Tool(NSString *name);
NSDictionary *Run(NSString *executable,NSArray *args,NSTimeInterval timeout,NSData *input);
NSString *Checked(NSString *executable,NSArray *args,NSTimeInterval timeout);
NSString *ReadText(NSString *path);
NSString *Quote(NSString *s);
NSString *SupportDir(void);
NSMutableDictionary *Prefs(void);
void SavePrefs(NSDictionary *prefs);
void Log(NSString *text);
NSString *LogTail(void);
NSDictionary *JSONFile(NSString *p);
BOOL SaveJSON(id obj,NSString *path);
NSString *JSON(id obj);
BOOL IsDir(NSString *p);
NSString *SafeRoot(NSString *p);
NSDictionary *Installation(NSString *override);
BOOL Running(NSString *process);
NSArray *SocketRows(NSString *raw);
NSArray *SessionRows(NSString *raw);
NSDictionary *Snapshot(NSString *config);
NSArray *Accounts(void);
NSString *BundleRoot(void);
NSString *HelperPath(void);
NSDictionary *AdminCall(NSDictionary *request,NSString *secret);
NSDictionary *AdminExecute(NSDictionary *request);
int AdminMain(NSString *requestPath);
NSDictionary *MetadataRun(NSDictionary *prefs,BOOL repair,BOOL background);
NSDictionary *MetadataTest(NSDictionary *prefs);
NSDictionary *MetadataCopy(NSDictionary *prefs,NSString *source,NSString *target);
int WorkerMain(void);
void OldAgentsRemove(void);
NSDictionary *CoreSelfTest(void);
// Netatalk packages are managed as the logged-in user. These never enable services.
NSDictionary *PackageCheck(void);
NSDictionary *PackageInstallLatest(void);
@interface AFPConfig : NSObject
@property(nonatomic,strong) NSString *original;
@property(nonatomic,strong) NSMutableArray *lines;
@property(nonatomic,strong) NSString *newline;
- (instancetype)initWithText:(NSString *)text;
- (NSArray *)sections;
- (NSArray *)shares;
- (NSDictionary *)global;
- (NSDictionary *)section:(NSString *)name;
- (void)patchSection:(NSString *)name options:(NSDictionary *)options create:(BOOL)create;
- (void)removeSection:(NSString *)name;
- (NSString *)text;
- (void)validate;
@end

// Startup diagnostics never contain passwords or the contents of shared files.
extern NSString *AFPSmokeReportPath;
void AFPStartupLog(NSString *event);
void AFPRecordException(NSException *exception);
void AFPInstallExceptionHandler(void);
@interface AFPApplication : NSApplication
@end

void AFPAssertObjectLayout(void);
