#import <XCTest/XCTest.h>
// Compile the metadata implementation under private fixture names. Only the
// environment boundaries are replaced: no test ever reads real afp.conf, runs
// Netatalk, writes application preferences, or touches an existing share.
#define MetadataRun AFPFixtureMetadataRun
#define MetadataTest AFPFixtureMetadataTest
#define MetadataCopy AFPFixtureMetadataCopy
#define WorkerMain AFPFixtureWorkerMain
#define SupportDir AFPFixtureSupportDir
#define Installation AFPFixtureInstallation
#define Run AFPFixtureRun
#define Tool AFPFixtureTool
#define Checked AFPFixtureChecked
#define Log AFPFixtureLog
#define Prefs AFPFixturePrefs
#import "../Source/Metadata.m"
#undef MetadataRun
#undef MetadataTest
#undef MetadataCopy
#undef WorkerMain
#undef SupportDir
#undef Installation
#undef Run
#undef Tool
#undef Checked
#undef Log
#undef Prefs

static NSString *fixtureSupport;
static BOOL processUnknown;
static BOOL processActive;
static NSString *sessionOutput;
static BOOL mutateCopySource,createCopyCollision,dropNativeCopyMetadata,conflictingNativeCopyMetadata,unrecognizedCopyDestination;
static NSUInteger nadOperations;
NSString *AFPFixtureSupportDir(void) { return fixtureSupport; }
NSDictionary *AFPFixtureInstallation(NSString *path) { return @{@"config":path?:@""}; }
NSString *AFPFixtureTool(NSString *tool) { return [@"/fixture/"stringByAppendingString:tool]; }
NSDictionary *AFPFixtureRun(NSString *tool,NSArray *args,NSTimeInterval timeout,NSData *input) {
    (void)args;(void)timeout;(void)input;
    if([tool isEqualToString:@"/usr/bin/pgrep"]&&!processUnknown) return processActive?@{@"ok":@YES,@"code":@0,@"out":@"123"}:@{@"ok":@NO,@"code":@1,@"out":@""};
    if([tool isEqualToString:@"afpstats"]) return @{@"ok":@YES,@"code":@0,@"out":sessionOutput?:@""};
    if([tool isEqualToString:@"nad"]) {
        if([args containsObject:@"--version"])return @{@"ok":@YES,@"code":@0,@"out":@"nad (Netatalk 4.6.0)"};
        if([args containsObject:@"ls"]) {
            if(unrecognizedCopyDestination)return @{@"ok":@NO,@"code":@1,@"out":@"Fixture destination is not inside an AFP volume"};
            // Real nad initializes the directory's Netatalk metadata while
            // opening its CNID backend, which legitimately changes ctime.
            NSString *destination=[args lastObject];setxattr([destination fileSystemRepresentation],"org.netatalk.Metadata","fixture",7,0,0);
            return @{@"ok":@YES,@"code":@0,@"out":@"Fixture AFP destination"};
        }
        nadOperations++;
        NSString *source=args[[args count]-2],*destination=args[[args count]-1];
        NSString *published=[destination stringByAppendingPathComponent:[source lastPathComponent]];
        NSError *error=nil;NSFileManager *fm=[NSFileManager defaultManager];BOOL ok;
        if([args containsObject:@"cp"]) {
            ok=[fm copyItemAtPath:source toPath:published error:&error];
            if(ok&&(dropNativeCopyMetadata||conflictingNativeCopyMetadata)) {
                NSMutableArray *paths=[NSMutableArray arrayWithObject:published];
                if(IsDir(published)) { for(NSString *rel in [fm enumeratorAtPath:published])[paths addObject:[published stringByAppendingPathComponent:rel]]; }
                for(NSString *path in paths) {
                    removexattr([path fileSystemRepresentation],"com.apple.FinderInfo",XATTR_NOFOLLOW);
                    removexattr([path fileSystemRepresentation],"com.apple.ResourceFork",XATTR_NOFOLLOW);
                }
                if(conflictingNativeCopyMetadata) {
                    NSString *path=IsDir(published)?[published stringByAppendingPathComponent:@"file"]:published;
                    unsigned char finder[32]={0};memcpy(finder,"APPLDIFF",8);
                    setxattr([path fileSystemRepresentation],"com.apple.FinderInfo",finder,32,0,XATTR_CREATE);
                }
            }
            if(ok&&mutateCopySource) {
                NSString *file=IsDir(source)?[source stringByAppendingPathComponent:@"file"]:source;
                [@"changed during copy"writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
            }
            if(ok&&createCopyCollision) [@"racing destination"writeToFile:[[destination stringByDeletingLastPathComponent]stringByAppendingPathComponent:[source lastPathComponent]]atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        } else ok=[fm moveItemAtPath:source toPath:published error:&error];
        return @{@"ok":@(ok),@"code":@(ok?0:1),@"out":error?[error localizedDescription]:@"Fixture nad operation completed"};
    }
    return @{@"ok":@NO,@"code":@2,@"out":@"Fixture: process inspection unavailable"};
}
NSString *AFPFixtureChecked(NSString *tool,NSArray *args,NSTimeInterval timeout) {
    NSDictionary *r=AFPFixtureRun(tool,args,timeout,nil);if(![r[@"ok"]boolValue])Fail(r[@"out"]);return r[@"out"];
}
void AFPFixtureLog(NSString *message) { (void)message; }
NSMutableDictionary *AFPFixturePrefs(void) { return [NSMutableDictionary dictionary]; }

@interface MetadataSafetyTests : XCTestCase
@property(nonatomic,strong) NSString *base;
@property(nonatomic,strong) NSString *root;
@property(nonatomic,strong) NSDictionary *prefs;
@end
@implementation MetadataSafetyTests
- (void)setUp {
    [super setUp];
    self.base=[NSTemporaryDirectory()stringByAppendingPathComponent:[@"afp-metadata-fixture-"stringByAppendingString:[[NSUUID UUID]UUIDString]]];
    self.root=[self.base stringByAppendingPathComponent:@"share"];
    fixtureSupport=[self.base stringByAppendingPathComponent:@"support"];processUnknown=NO;processActive=NO;sessionOutput=nil;mutateCopySource=NO;createCopyCollision=NO;dropNativeCopyMetadata=NO;conflictingNativeCopyMetadata=NO;unrecognizedCopyDestination=NO;nadOperations=0;
    NSFileManager *fm=[NSFileManager defaultManager];
    XCTAssertTrue([fm createDirectoryAtPath:self.root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]);
    XCTAssertTrue([fm createDirectoryAtPath:fixtureSupport withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]);
    NSString *config=[self.base stringByAppendingPathComponent:@"afp.conf"];
    NSString *configText=[NSString stringWithFormat:@"[Global]\n[Test]\npath = %@\n",self.root];
    XCTAssertTrue([configText writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    self.prefs=@{@"configPath":config,@"selectedSection":@"Test"};
}
- (void)tearDown {
    [[NSFileManager defaultManager]removeItemAtPath:self.base error:NULL];fixtureSupport=nil;
    [super tearDown];
}
- (NSData *)sidecar {
    NSMutableData *data=[NSMutableData dataWithLength:90];unsigned char *b=[data mutableBytes];
    BE32(b,0x00051607);BE32(b+4,0x00020000);BE16(b+24,2);
    BE32(b+26,9);BE32(b+30,50);BE32(b+34,32);BE32(b+38,2);BE32(b+42,82);BE32(b+46,8);
    memcpy(b+50,"TEXTttxt",8);memcpy(b+82,"FORKDATA",8);return data;
}
- (void)age:(NSString *)path {
    XCTAssertTrue([[NSFileManager defaultManager]setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:-60]}ofItemAtPath:path error:NULL]);
}
- (NSString *)target:(NSString *)name {
    NSString *target=[self.root stringByAppendingPathComponent:name];
    XCTAssertTrue([[@"data fork"dataUsingEncoding:NSUTF8StringEncoding]writeToFile:target atomically:NO]);
    [self age:target];return target;
}
- (NSString *)sidecarFor:(NSString *)name {
    NSString *path=[self.root stringByAppendingPathComponent:[@"._"stringByAppendingString:name]];
    XCTAssertTrue([[self sidecar]writeToFile:path atomically:NO]);[self age:path];return path;
}
- (void)testRepairsAbsentMetadataAfterVerifiedBackupAndRetainsSource {
    NSString *target=[self target:@"classic"],*source=[self sidecarFor:@"classic"];
    NSDictionary *r=AFPFixtureMetadataRun(self.prefs,YES,NO);
    XCTAssertTrue([r[@"ok"]boolValue],@"%@",r);XCTAssertEqualObjects(r[@"counts"][@"finderAdded"],@1);XCTAssertEqualObjects(r[@"counts"][@"resourceAdded"],@1);
    XCTAssertEqual(getxattr([target fileSystemRepresentation],"com.apple.FinderInfo",NULL,0,0,XATTR_NOFOLLOW),(ssize_t)32);
    unsigned char fork[8];XCTAssertEqual(getxattr([target fileSystemRepresentation],"com.apple.ResourceFork",fork,sizeof fork,0,XATTR_NOFOLLOW),(ssize_t)8);XCTAssertEqual(memcmp(fork,"FORKDATA",8),0);
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:source],[self sidecar]);
    NSArray *backups=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:r[@"backup"]error:NULL];XCTAssertEqual([backups count],(NSUInteger)2);
    NSDictionary *again=AFPFixtureMetadataRun(self.prefs,YES,NO);XCTAssertEqualObjects(again[@"counts"][@"finderAdded"],@0);XCTAssertEqualObjects(again[@"counts"][@"resourceAdded"],@0);
}
- (void)testNativeConflictPreventsMixingMetadataFromDifferentSources {
    NSString *target=[self target:@"conflict"];[self sidecarFor:@"conflict"];
    unsigned char finder[32]={0};memcpy(finder,"APPLTEST",8);
    XCTAssertEqual(setxattr([target fileSystemRepresentation],"com.apple.FinderInfo",finder,32,0,XATTR_CREATE),0);[self age:target];
    NSDictionary *r=AFPFixtureMetadataRun(self.prefs,YES,NO);XCTAssertEqualObjects(r[@"counts"][@"conflicts"],@1);XCTAssertEqualObjects(r[@"counts"][@"resourceAdded"],@0);
    errno=0;XCTAssertEqual(getxattr([target fileSystemRepresentation],"com.apple.ResourceFork",NULL,0,0,XATTR_NOFOLLOW),(ssize_t)-1);XCTAssertEqual(errno,ENOATTR);
    unsigned char actual[32];XCTAssertEqual(getxattr([target fileSystemRepresentation],"com.apple.FinderInfo",actual,32,0,XATTR_NOFOLLOW),(ssize_t)32);XCTAssertEqual(memcmp(actual,finder,32),0);
}
- (void)testSymlinkAndHardLinkTargetsRemainUnchanged {
    NSString *outside=[self.base stringByAppendingPathComponent:@"outside"];
    XCTAssertTrue([[@"outside"dataUsingEncoding:NSUTF8StringEncoding]writeToFile:outside atomically:NO]);[self age:outside];
    NSString *symlinkPath=[self.root stringByAppendingPathComponent:@"symlink"];
    XCTAssertEqual(symlink([outside fileSystemRepresentation],[symlinkPath fileSystemRepresentation]),0);
    [self sidecarFor:@"symlink"];
    NSString *hard=[self.root stringByAppendingPathComponent:@"hard"];
    XCTAssertEqual(link([outside fileSystemRepresentation],[hard fileSystemRepresentation]),0);[self sidecarFor:@"hard"];
    NSDictionary *r=AFPFixtureMetadataRun(self.prefs,YES,NO);XCTAssertEqualObjects(r[@"counts"][@"finderAdded"],@0);XCTAssertEqualObjects(r[@"counts"][@"resourceAdded"],@0);XCTAssertGreaterThan([r[@"counts"][@"errors"]integerValue],0);
    errno=0;XCTAssertEqual(getxattr([outside fileSystemRepresentation],"com.apple.FinderInfo",NULL,0,0,XATTR_NOFOLLOW),(ssize_t)-1);XCTAssertEqual(errno,ENOATTR);
}
- (void)testDescriptorTraversalRejectsSymlinkAncestorsAndParentTraversal {
    NSString *outside=[self.base stringByAppendingPathComponent:@"outside-directory"];
    XCTAssertTrue([[NSFileManager defaultManager]createDirectoryAtPath:outside withIntermediateDirectories:NO attributes:nil error:NULL]);
    XCTAssertTrue([[@"private"dataUsingEncoding:NSUTF8StringEncoding]writeToFile:[outside stringByAppendingPathComponent:@"file"]atomically:NO]);
    XCTAssertEqual(symlink([outside fileSystemRepresentation],[[self.root stringByAppendingPathComponent:@"escape"]fileSystemRepresentation]),0);
    int rootFD=open([self.root fileSystemRepresentation],O_RDONLY|O_DIRECTORY);struct stat rootStat;XCTAssertEqual(fstat(rootFD,&rootStat),0);
    XCTAssertEqual(OpenRelative(rootFD,@"escape/file",rootStat.st_dev),-1);XCTAssertEqual(OpenRelative(rootFD,@"../outside-directory/file",rootStat.st_dev),-1);close(rootFD);
}
- (void)testUnknownServerStatusPausesBeforeAnyWrite {
    NSString *target=[self target:@"unknown"];[self sidecarFor:@"unknown"];processUnknown=YES;
    NSDictionary *r=AFPFixtureMetadataRun(self.prefs,YES,NO);XCTAssertTrue([r[@"paused"]boolValue]);XCTAssertFalse([r[@"ok"]boolValue]);
    errno=0;XCTAssertEqual(getxattr([target fileSystemRepresentation],"com.apple.FinderInfo",NULL,0,0,XATTR_NOFOLLOW),(ssize_t)-1);XCTAssertEqual(errno,ENOATTR);
}
- (void)testOfficialHeaderOnlyOutputConfirmsNoClientsButUnknownOutputDoesNot {
    processActive=YES;
    sessionOutput=@"Connected user  PID  Login time  State  Protocol  Client address  Mounted volumes\n";
    XCTAssertNil(BusySessions());
    sessionOutput=@"Connected user forged prefix\n";XCTAssertNotNil(BusySessions());
    sessionOutput=@"";XCTAssertNotNil(BusySessions());
    sessionOutput=@"Connected user  PID  Login time  State  Protocol  Client address  Mounted volumes\nWARNING Unexpected output\n";XCTAssertNotNil(BusySessions());
}
- (void)testRecentFilesAndMalformedSidecarsAreDeferredOrRejected {
    NSString *recent=[self target:@"recent"];[self sidecarFor:@"recent"];
    XCTAssertTrue([[NSFileManager defaultManager]setAttributes:@{NSFileModificationDate:[NSDate date]}ofItemAtPath:recent error:NULL]);
    [self target:@"bad"];NSString *bad=[self.root stringByAppendingPathComponent:@"._bad"];
    XCTAssertTrue([[@"invalid"dataUsingEncoding:NSUTF8StringEncoding]writeToFile:bad atomically:NO]);[self age:bad];
    NSDictionary *r=AFPFixtureMetadataRun(self.prefs,YES,NO);XCTAssertEqualObjects(r[@"counts"][@"unstable"],@1);XCTAssertEqualObjects(r[@"counts"][@"errors"],@1);XCTAssertEqualObjects(r[@"counts"][@"finderAdded"],@0);
}
- (NSString *)importSourceFolder {
    NSString *folder=[self.base stringByAppendingPathComponent:@"source-folder"];
    XCTAssertTrue([[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSString *file=[folder stringByAppendingPathComponent:@"file"];
    XCTAssertTrue([[@"source bytes"dataUsingEncoding:NSUTF8StringEncoding]writeToFile:file atomically:NO]);
    unsigned char finder[32]={0};memcpy(finder,"TEXTttxt",8);
    XCTAssertEqual(setxattr([file fileSystemRepresentation],"com.apple.FinderInfo",finder,32,0,XATTR_CREATE),0);
    XCTAssertEqual(setxattr([file fileSystemRepresentation],"com.apple.ResourceFork","FORKDATA",8,0,XATTR_CREATE),0);
    return folder;
}
- (void)testImportStagesVerifiesAndPublishesNativeMetadataWithoutOverwrite {
    NSString *source=[self importSourceFolder];dropNativeCopyMetadata=YES;
    NSDictionary *r=AFPFixtureMetadataCopy(self.prefs,source,self.root);XCTAssertTrue([r[@"ok"]boolValue]);XCTAssertEqual(nadOperations,(NSUInteger)2);
    NSString *file=[[self.root stringByAppendingPathComponent:@"source-folder"]stringByAppendingPathComponent:@"file"];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:file],[NSData dataWithContentsOfFile:[source stringByAppendingPathComponent:@"file"]]);
    unsigned char fork[8];XCTAssertEqual(getxattr([file fileSystemRepresentation],"com.apple.ResourceFork",fork,sizeof fork,0,XATTR_NOFOLLOW),(ssize_t)8);XCTAssertEqual(memcmp(fork,"FORKDATA",8),0);
    NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.root error:NULL];XCTAssertEqual([items count],(NSUInteger)1);
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)2);
}
- (void)testImportRejectsUnrecognizedAFPVolumeBeforeStagingOrCopying {
    NSString *source=[self importSourceFolder];unrecognizedCopyDestination=YES;
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)0);
    NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.root error:NULL];XCTAssertEqual([items count],(NSUInteger)0);
}
- (void)testImportRefusesToOverwriteConflictingStagedNativeMetadata {
    NSString *source=[self importSourceFolder];conflictingNativeCopyMetadata=YES;
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)1);
    XCTAssertFalse([[NSFileManager defaultManager]fileExistsAtPath:[self.root stringByAppendingPathComponent:@"source-folder"]]);
    NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.root error:NULL];XCTAssertEqual([items count],(NSUInteger)1);
    NSString *file=[[[self.root stringByAppendingPathComponent:[items firstObject]]stringByAppendingPathComponent:@"source-folder"]stringByAppendingPathComponent:@"file"];
    unsigned char finder[32];XCTAssertEqual(getxattr([file fileSystemRepresentation],"com.apple.FinderInfo",finder,32,0,XATTR_NOFOLLOW),(ssize_t)32);XCTAssertEqual(memcmp(finder,"APPLDIFF",8),0);
}
- (void)testImportRejectsSymlinkSourcesBeforeCallingNad {
    NSString *source=[self importSourceFolder],*alias=[self.base stringByAppendingPathComponent:@"alias"];
    XCTAssertEqual(symlink([source fileSystemRepresentation],[alias fileSystemRepresentation]),0);
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,alias,self.root));XCTAssertEqual(nadOperations,(NSUInteger)0);
    XCTAssertEqual(symlink([[source stringByAppendingPathComponent:@"file"]fileSystemRepresentation],[[source stringByAppendingPathComponent:@"nested-alias"]fileSystemRepresentation]),0);
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)0);
}
- (void)testImportSourceCopyRaceRetainsStagingAndDoesNotPublish {
    NSString *source=[self importSourceFolder];mutateCopySource=YES;
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)1);
    XCTAssertFalse([[NSFileManager defaultManager]fileExistsAtPath:[self.root stringByAppendingPathComponent:@"source-folder"]]);
    NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.root error:NULL];XCTAssertEqual([items count],(NSUInteger)1);XCTAssertTrue([[items firstObject]hasPrefix:@".AFP Import "]);
}
- (void)testImportDestinationRaceRetainsVerifiedStagingAndExistingFile {
    NSString *source=[self importSourceFolder];createCopyCollision=YES;
    XCTAssertThrows(AFPFixtureMetadataCopy(self.prefs,source,self.root));XCTAssertEqual(nadOperations,(NSUInteger)1);
    NSString *final=[self.root stringByAppendingPathComponent:@"source-folder"];
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:final encoding:NSUTF8StringEncoding error:NULL],@"racing destination");
    NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.root error:NULL];XCTAssertEqual([items count],(NSUInteger)2);
}
- (void)testNativeClassicFileContainsTypeCreatorAndValidResourceMap {
    NSDictionary *r=AFPFixtureMetadataTest(self.prefs);XCTAssertTrue([r[@"ok"]boolValue]);
    int fd=open([r[@"path"]fileSystemRepresentation],O_RDONLY|O_NOFOLLOW);XCTAssertGreaterThanOrEqual(fd,0);
    BOOL absent;NSData *fi=FDXattr(fd,@"com.apple.FinderInfo",&absent),*rsrc=FDXattr(fd,@"com.apple.ResourceFork",&absent);
    XCTAssertEqual(memcmp([fi bytes],"TEXTttxt",8),0);const unsigned char *b=[rsrc bytes];
    uint32_t mapOffset=((uint32_t)b[4]<<24)|((uint32_t)b[5]<<16)|((uint32_t)b[6]<<8)|b[7];
    XCTAssertGreaterThan([rsrc length],(NSUInteger)mapOffset+49);XCTAssertEqual(memcmp(b+mapOffset+30,"STR ",4),0);XCTAssertEqual(b[mapOffset+39],(unsigned char)128);close(fd);
}
@end
