#import "Core.h"
#include <copyfile.h>

static NSString *const ReleaseEndpoint=@"https://api.github.com/repos/Netatalk/netatalk/releases/latest";
static NSString *const ReleaseHome=@"https://github.com/Netatalk/netatalk/releases";
static NSString *PackageStatusPath(void){return [SupportDir()stringByAppendingPathComponent:@"package-status.json"];}
static NSString *PackageVersion(NSString *text){
    NSArray *m=Match(@"(?i)(?:netatalk[^0-9]*)?([0-9]{1,9}\\.[0-9]{1,9}(?:\\.[0-9]{1,9})?)",S(text));
    return m?m[1]:@"";
}
// Pure helpers are also exercised by the package regression tests.
NSComparisonResult PackageCompareVersions(NSString *left,NSString *right){
    if(!Match(@"^[0-9]{1,9}\\.[0-9]{1,9}(?:\\.[0-9]{1,9})?$",S(left))||!Match(@"^[0-9]{1,9}\\.[0-9]{1,9}(?:\\.[0-9]{1,9})?$",S(right)))Fail(@"A Netatalk version number was not recognised.");
    NSArray *a=[left componentsSeparatedByString:@"."],*b=[right componentsSeparatedByString:@"."];
    for(NSUInteger i=0;i<3;i++){NSInteger x=i<[a count]?[a[i]integerValue]:0,y=i<[b count]?[b[i]integerValue]:0;if(x<y)return NSOrderedAscending;if(x>y)return NSOrderedDescending;}return NSOrderedSame;
}
NSDictionary *PackageValidateRelease(NSDictionary *raw){
    if(![raw isKindOfClass:[NSDictionary class]]||![raw[@"draft"]isKindOfClass:[NSNumber class]]||![raw[@"prerelease"]isKindOfClass:[NSNumber class]]||[raw[@"draft"]boolValue]||[raw[@"prerelease"]boolValue])Fail(@"GitHub did not return a published stable Netatalk release.");
    NSString *tag=S(raw[@"tag_name"]);NSArray *m=Match(@"^netatalk-([0-9]{1,9})-([0-9]{1,9})-([0-9]{1,9})$",tag);if(!m)Fail(@"The upstream stable-release tag was not recognised.");
    NSString *version=[NSString stringWithFormat:@"%@.%@.%@",m[1],m[2],m[3]],*page=[ReleaseHome stringByAppendingFormat:@"/tag/%@",tag];
    if(![S(raw[@"html_url"])isEqualToString:page])Fail(@"The release URL is outside the official Netatalk repository.");
    NSString *assetName=[NSString stringWithFormat:@"netatalk-%@.tar.xz",version],*source=[ReleaseHome stringByAppendingFormat:@"/download/%@/%@",tag,assetName],*digest=@"";
    if(![raw[@"assets"]isKindOfClass:[NSArray class]])Fail(@"The release has no recognised source assets.");
    for(id value in raw[@"assets"]){if(![value isKindOfClass:[NSDictionary class]])continue;NSDictionary *asset=value;if(![S(asset[@"name"])isEqualToString:assetName])continue;if(![S(asset[@"browser_download_url"])isEqualToString:source]||![S(asset[@"state"])isEqualToString:@"uploaded"]||!Match(@"^sha256:[0-9a-fA-F]{64}$",S(asset[@"digest"])))Fail(@"The stable source asset URL or digest could not be verified.");digest=[S(asset[@"digest"])substringFromIndex:7];break;}
    if(![digest length])Fail(@"The official release source checksum was not available.");
    return @{@"latestVersion":version,@"latestURL":page,@"sourceURL":source,@"sourceSHA256":[digest lowercaseString],@"publishedAt":S(raw[@"published_at"])};
}
NSDictionary *PackageValidateFormula(NSDictionary *raw,NSDictionary *release){
    if(![raw isKindOfClass:[NSDictionary class]]||![raw[@"formulae"]isKindOfClass:[NSArray class]])Fail(@"Homebrew returned unrecognised package information.");
    NSDictionary *formula=nil;for(id f in raw[@"formulae"])if([f isKindOfClass:[NSDictionary class]]&&[S(f[@"full_name"])isEqualToString:@"netatalk"]&&[S(f[@"tap"])isEqualToString:@"homebrew/core"]){formula=f;break;}
    if(!formula)Fail(@"The official Homebrew core Netatalk formula was not found.");
    if([formula[@"disabled"]boolValue]||[formula[@"deprecated"]boolValue])Fail(@"The Homebrew Netatalk formula is disabled or deprecated; no package was changed.");
    NSString *version=S(formula[@"versions"][@"stable"]);if(PackageCompareVersions(version,S(release[@"latestVersion"]))!=NSOrderedSame)Fail([NSString stringWithFormat:@"The latest stable Netatalk release is %@, but Homebrew currently offers %@. No older release was installed. Try again after the formula is updated.",release[@"latestVersion"],version]);
    NSDictionary *source=formula[@"urls"][@"stable"];
    if(![S(source[@"url"])isEqualToString:S(release[@"sourceURL"])]||![[S(source[@"checksum"])lowercaseString]isEqualToString:S(release[@"sourceSHA256"])])Fail(@"Homebrew's source URL/checksum does not match the verified upstream stable release. No package was changed.");
    if([formula[@"pinned"]boolValue])Fail(@"The Netatalk formula is pinned in Homebrew. Its pin was preserved; no update was attempted.");
    return formula;
}

@interface AFPReleaseFetcher : NSObject <NSURLSessionTaskDelegate>
@end
@implementation AFPReleaseFetcher
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session;(void)task;(void)response;
    NSURL *url=[request URL];completionHandler([[url scheme]isEqualToString:@"https"]&&[[url host]isEqualToString:@"api.github.com"]?request:nil);
}
@end
static NSDictionary *PackageFetchLatest(void){
    NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=25;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;
    AFPReleaseFetcher *delegate=[AFPReleaseFetcher new];NSURLSession *session=[NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:ReleaseEndpoint]];[request setValue:@"application/vnd.github+json"forHTTPHeaderField:@"Accept"];[request setValue:@"2022-11-28"forHTTPHeaderField:@"X-GitHub-Api-Version"];[request setValue:[@"AFPServer/"stringByAppendingString:AFP_VERSION]forHTTPHeaderField:@"User-Agent"];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *data=nil;__block NSError *failure=nil;__block NSHTTPURLResponse *response=nil;
    NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *body,NSURLResponse *reply,NSError *error){data=body;failure=error;if([reply isKindOfClass:[NSHTTPURLResponse class]])response=(NSHTTPURLResponse *)reply;dispatch_semaphore_signal(done);}];[task resume];
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))){[task cancel];[session invalidateAndCancel];Fail(@"The Netatalk release check timed out. The installed server was not changed.");}
    [session finishTasksAndInvalidate];if(failure)Fail([@"Cannot check the official Netatalk release: "stringByAppendingString:S([failure localizedDescription])]);
    if(response.statusCode!=200)Fail([NSString stringWithFormat:@"The official release endpoint returned HTTP %ld. Try again later; no package was changed.",(long)response.statusCode]);
    if(!data||[data length]>2*1024*1024)Fail(@"The release response was empty or too large.");
    id raw=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];return PackageValidateRelease(raw);
}
static NSDictionary *PackagePAMState(void){
    NSString *target=@"/usr/local/etc/pam.d/netatalk",*source=Tool(@"brew")?@"/opt/homebrew/etc/pam.d/netatalk":@"";
    if(![[NSFileManager defaultManager]fileExistsAtPath:source])source=@"/usr/local/etc/pam.d/netatalk";
    struct stat a;BOOL ready=lstat([target fileSystemRepresentation],&a)==0&&S_ISREG(a.st_mode)&&a.st_size>0&&a.st_size<1024*1024;
    NSData *existing=ready?[NSData dataWithContentsOfFile:target]:nil,*packaged=[source length]?[NSData dataWithContentsOfFile:source]:nil;ready=ready&&[existing length]>0;
    BOOL same=ready&&packaged&&[existing isEqualToData:packaged];
    return @{@"pamReady":@(ready),@"pamMatchesPackaged":@(same),@"pamMessage":same?@"The required AFP PAM configuration matches the installed package.":(ready?@"An existing AFP PAM configuration was preserved. It differs from the packaged file; account login still needs verification.":@"AFP account authentication needs /usr/local/etc/pam.d/netatalk. Use the app's administrator setup action; no global directory ownership change is required.")};
}
static NSMutableDictionary *PackageLocalState(void){
    NSDictionary *install=Installation(S(Prefs()[@"configPath"]));NSString *binary=S(install[@"binary"]),*version=[binary length]?PackageVersion(S(install[@"version"])):@"";BOOL installed=[binary length]>0;
    NSString *manager=!installed?@"none":([S(install[@"brew"])length]?@"homebrew":@"source");
    NSMutableDictionary *state=[@{@"installed":@(installed),@"installedVersion":version,@"manager":manager,@"canInstall":@([Tool(@"brew")length]&&![manager isEqualToString:@"source"]),@"config":S(install[@"config"]),@"compiledConfig":S(install[@"compiledConfig"])}mutableCopy];[state addEntriesFromDictionary:PackagePAMState()];return state;
}
static void PackageCache(NSMutableDictionary *report){if(!SaveJSON(report,PackageStatusPath()))report[@"output"]=[S(report[@"output"])stringByAppendingString:@"\nThe package-status cache could not be saved; the installed server was not changed by this logging failure."];}
NSDictionary *PackageCheck(void){
    NSMutableDictionary *report=[(JSONFile(PackageStatusPath())?:@{})mutableCopy];[report addEntriesFromDictionary:PackageLocalState()];report[@"checkedAtEpoch"]=@([[NSDate date]timeIntervalSince1970]);
    @try {
        NSDictionary *release=PackageFetchLatest();[report addEntriesFromDictionary:release];BOOL installed=[report[@"installed"]boolValue];if(installed&&![S(report[@"installedVersion"])length])Fail(@"Netatalk was found, but its installed version could not be verified. No package change was offered.");
        BOOL newer=installed&&[S(report[@"installedVersion"])length]&&PackageCompareVersions(report[@"installedVersion"],release[@"latestVersion"])==NSOrderedAscending;
        report[@"updateAvailable"]=@(newer);report[@"action"]=![report[@"canInstall"]boolValue]?@"unsupported":(!installed?@"install":(newer?@"update":@"current"));report[@"ok"]=@YES;report[@"lastSuccessfulCheckEpoch"]=report[@"checkedAtEpoch"];report[@"stale"]=@NO;
        report[@"message"]=[NSString stringWithFormat:@"Latest stable: Netatalk %@. %@",release[@"latestVersion"],!installed?@"Netatalk is not installed.":(newer?@"An update is available. Updates run only after your click and with the server stopped.":@"The installed version is current or newer than this stable release.")];
        if([S(report[@"manager"])isEqualToString:@"source"])report[@"message"]=[S(report[@"message"])stringByAppendingString:@" The existing installation is not managed by Homebrew; it will not be replaced automatically."];
        else if(!Tool(@"brew"))report[@"message"]=[S(report[@"message"])stringByAppendingString:@" Homebrew is not installed; the app will not bootstrap a package manager silently."];
    } @catch(NSException *e){report[@"ok"]=@NO;report[@"stale"]=@YES;report[@"canInstall"]=@NO;report[@"message"]=[e reason]?:@"Release check failed.";}
    PackageCache(report);return report;
}
static NSString *PackageCommand(NSString *program,NSArray *arguments,NSTimeInterval timeout){NSDictionary *r=Run(program,arguments,timeout,nil);if(![r[@"ok"]boolValue])Fail([NSString stringWithFormat:@"%@ failed (exit %@).\n%@",[program lastPathComponent],r[@"code"],S(r[@"out"])]);return S(r[@"out"]);}
static void PackageRequireStopped(void){for(NSString *name in @[@"afpd",@"netatalk",@"cnid_dbd",@"cnid_metad"])if(Running(name))Fail(@"Stop Netatalk explicitly in Overview before installing or updating. No connected clients were disconnected by the package operation.");}
static NSDictionary *PackageBackupConfigPaths(NSArray *paths,NSString *directory){
    NSMutableDictionary *saved=[NSMutableDictionary dictionary];NSMutableArray *manifest=[NSMutableArray array];
    for(NSString *original in paths){NSString *path=[[original stringByStandardizingPath]stringByResolvingSymlinksInPath];if(saved[path])continue;struct stat a;if(lstat([path fileSystemRepresentation],&a)){if(errno==ENOENT)continue;Fail([@"Cannot inspect configuration before installation: "stringByAppendingString:path]);}
        if(!S_ISREG(a.st_mode)||a.st_nlink!=1||a.st_size>4000000||a.st_size<0)Fail([@"Unsafe or oversized configuration; no package was changed: "stringByAppendingString:path]);
        NSData *data=[NSData dataWithContentsOfFile:path];if(!data)Fail([@"Cannot read configuration for a verified backup: "stringByAppendingString:path]);
        NSString *backup=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"config-%lu.conf",(unsigned long)[saved count]+1]];if(![data writeToFile:backup options:NSDataWritingWithoutOverwriting error:NULL]||chmod([backup fileSystemRepresentation],0600)||![[NSData dataWithContentsOfFile:backup]isEqualToData:data])Fail(@"A configuration backup could not be written and verified. No package was changed.");
        // Preserve a private metadata copy in addition to the verified text bytes.
        NSString *metadata=[backup stringByAppendingString:@".metadata"];if(copyfile([path fileSystemRepresentation],[metadata fileSystemRepresentation],NULL,COPYFILE_DATA|COPYFILE_XATTR|COPYFILE_ACL|COPYFILE_EXCL))Fail(@"A configuration metadata backup failed. No package was changed.");chmod([metadata fileSystemRepresentation],0600);
        struct stat b;if(lstat([path fileSystemRepresentation],&b)||a.st_dev!=b.st_dev||a.st_ino!=b.st_ino||a.st_size!=b.st_size||a.st_mtimespec.tv_sec!=b.st_mtimespec.tv_sec||a.st_mtimespec.tv_nsec!=b.st_mtimespec.tv_nsec||![[NSData dataWithContentsOfFile:path]isEqualToData:data])Fail(@"A configuration changed during backup. No package was changed.");
        saved[path]=@{@"data":data,@"backup":backup};[manifest addObject:@{@"source":path,@"backup":backup,@"metadataBackup":metadata}];
    }
    if(!SaveJSON(@{@"created":Stamp(),@"files":manifest},[directory stringByAppendingPathComponent:@"manifest.json"]))Fail(@"The package backup manifest could not be saved. No package was changed.");return saved;
}
static NSDictionary *PackageBackupConfigs(NSString *selected,NSString *directory){
    NSMutableArray *paths=[NSMutableArray arrayWithArray:@[@"/usr/local/etc/afp.conf",@"/usr/local/etc/netatalk/afp.conf",@"/opt/homebrew/etc/afp.conf",@"/opt/homebrew/etc/netatalk/afp.conf"]];if([selected length])[paths addObject:selected];
    return PackageBackupConfigPaths(paths,directory);
}
static void PackageVerifyConfigs(NSDictionary *saved){for(NSString *path in saved)if(![[NSData dataWithContentsOfFile:path]isEqualToData:saved[path][@"data"]])Fail([NSString stringWithFormat:@"The package operation changed or removed %@. The verified backup is %@. Netatalk was left stopped; review this configuration before starting it.",path,saved[path][@"backup"]]);}
static NSString *PackageMigrateConfigContents(NSString *selected,NSDictionary *saved,NSString *compiled,NSString *backups){
    selected=[[selected stringByStandardizingPath]stringByResolvingSymlinksInPath];compiled=[[compiled stringByStandardizingPath]stringByResolvingSymlinksInPath];
    if(![compiled length]||[selected isEqualToString:compiled]||saved[compiled]||!saved[selected])return @"";
    if(![[compiled lastPathComponent]isEqualToString:@"afp.conf"])Fail(@"The new default configuration must be afp.conf.");
    struct stat a;if(lstat([compiled fileSystemRepresentation],&a)||!S_ISREG(a.st_mode)||a.st_nlink!=1||a.st_size>4000000||a.st_uid!=getuid())Fail(@"The new default afp.conf cannot be migrated safely without administrator setup. Original configs and their backups were retained.");
    NSData *generated=[NSData dataWithContentsOfFile:compiled],*source=saved[selected][@"data"];NSString *backup=[backups stringByAppendingPathComponent:@"new-package-default.conf"];
    if(!generated||![generated writeToFile:backup options:NSDataWritingWithoutOverwriting error:NULL]||chmod([backup fileSystemRepresentation],0600)||![[NSData dataWithContentsOfFile:backup]isEqualToData:generated])Fail(@"The package's new default config could not be backed up. It was not overwritten.");
    NSString *temp=[[compiled stringByDeletingLastPathComponent]stringByAppendingPathComponent:[@".afp-package-"stringByAppendingString:[[NSUUID UUID]UUIDString]]];
    @try {
        if(copyfile([compiled fileSystemRepresentation],[temp fileSystemRepresentation],NULL,COPYFILE_ALL|COPYFILE_EXCL))Fail(@"Cannot stage the new default configuration while preserving its permissions.");
        int fd=open([temp fileSystemRepresentation],O_WRONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)Fail(@"Cannot write the staged default configuration.");
        @try{if(ftruncate(fd,0))Fail(@"Cannot truncate staged config.");size_t count=0;while(count<[source length]){ssize_t n=write(fd,(const char *)[source bytes]+count,[source length]-count);if(n<0&&errno==EINTR)continue;if(n<=0)Fail(@"Cannot write the staged configuration completely.");count+=(size_t)n;}if(fsync(fd))Fail(@"Cannot synchronize staged configuration.");}@finally{close(fd);}
        struct stat b;if(lstat([compiled fileSystemRepresentation],&b)||a.st_dev!=b.st_dev||a.st_ino!=b.st_ino||![[NSData dataWithContentsOfFile:compiled]isEqualToData:generated]||![[NSData dataWithContentsOfFile:selected]isEqualToData:source])Fail(@"A configuration changed before migration. No newer content was overwritten.");
        if(rename([temp fileSystemRepresentation],[compiled fileSystemRepresentation]))Fail(@"Cannot publish the migrated default configuration.");if(![[NSData dataWithContentsOfFile:compiled]isEqualToData:source])Fail(@"The migrated default configuration did not verify. Backups were retained.");
    }@finally{[[NSFileManager defaultManager]removeItemAtPath:temp error:NULL];}
    return [NSString stringWithFormat:@"Preserved selected settings from %@ in the newly created %@. Its original package default was backed up at %@.\n",selected,compiled,backup];
}
static NSString *PackageMigrateConfig(NSString *selected,NSDictionary *saved,NSString *compiled,NSString *backups){
    selected=[[selected stringByStandardizingPath]stringByResolvingSymlinksInPath];compiled=[[compiled stringByStandardizingPath]stringByResolvingSymlinksInPath];
    if(![compiled length]||[selected isEqualToString:compiled]||saved[compiled]||!saved[selected])return @"";
    if(![[compiled lastPathComponent]isEqualToString:@"afp.conf"]||![@[@"/opt/homebrew/etc/netatalk/afp.conf",@"/opt/homebrew/etc/afp.conf",@"/usr/local/etc/netatalk/afp.conf",@"/usr/local/etc/afp.conf"]containsObject:compiled])Fail(@"The newly installed default configuration path was not recognised. Original configs and backups were retained; no automatic migration was attempted.");
    NSString *message=PackageMigrateConfigContents(selected,saved,compiled,backups);
    if([message length]){NSMutableDictionary *prefs=Prefs();prefs[@"configPath"]=compiled;SavePrefs(prefs);}return message;
}
NSDictionary *PackageInstallLatest(void){
    int lock=-1,metadata=-1;NSMutableString *output=[NSMutableString string];NSString *backups=@"";NSMutableDictionary *result=[NSMutableDictionary dictionary];
    @try {
        if(geteuid()==0)Fail(@"Install and update Homebrew packages as the logged-in user. The GUI and Homebrew must not run as root.");
        NSString *brew=Tool(@"brew");if(!brew)Fail(@"Homebrew is not installed. No package manager was installed automatically.");
        NSString *lockPath=[SupportDir()stringByAppendingPathComponent:@"packages.lock"];lock=open([lockPath fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);metadata=open([[SupportDir()stringByAppendingPathComponent:@"metadata.lock"]fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
        if(lock<0||metadata<0||flock(lock,LOCK_EX|LOCK_NB)||flock(metadata,LOCK_EX|LOCK_NB))Fail(@"Another package, administrator or metadata operation is in progress.");
        PackageRequireStopped();NSMutableDictionary *before=PackageLocalState();if([S(before[@"manager"])isEqualToString:@"source"])Fail(@"An existing Netatalk installation is not managed by Homebrew. It was preserved; an automatic second installation was not created.");
        NSDictionary *release=PackageFetchLatest();[result addEntriesFromDictionary:release];
        if([before[@"installed"]boolValue]&&[S(before[@"installedVersion"])length]&&PackageCompareVersions(before[@"installedVersion"],release[@"latestVersion"])!=NSOrderedAscending){[result addEntriesFromDictionary:before];result[@"ok"]=@YES;result[@"action"]=@"current";result[@"message"]=@"The installed Netatalk version is current or newer than the latest stable release. No downgrade or reinstall was attempted.";}
        else {
            backups=[[SupportDir()stringByAppendingPathComponent:@"PackageBackups"]stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]];if(![[NSFileManager defaultManager]createDirectoryAtPath:backups withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700}error:NULL])Fail(@"Cannot create private configuration backups.");
            NSString *selected=S(before[@"config"]);NSDictionary *saved=PackageBackupConfigs(selected,backups);[output appendFormat:@"Configuration backups: %@\n",backups];
            [output appendString:PackageCommand(brew,@[@"update"],600)];PackageRequireStopped();
            NSString *info=PackageCommand(brew,@[@"info",@"--json=v2",@"netatalk"],60);id raw=[NSJSONSerialization JSONObjectWithData:[info dataUsingEncoding:NSUTF8StringEncoding]options:0 error:NULL];PackageValidateFormula(raw,release);
            PackageRequireStopped();[output appendString:PackageCommand(brew,@[[before[@"installed"]boolValue]?@"upgrade":@"install",@"netatalk"],3600)];PackageRequireStopped();PackageVerifyConfigs(saved);
            NSDictionary *installed=Installation(@"");NSString *version=PackageVersion(S(installed[@"version"]));if(![S(installed[@"binary"])length]||PackageCompareVersions(version,release[@"latestVersion"])!=NSOrderedSame)Fail(@"Homebrew finished, but the installed Netatalk binary did not verify as the requested latest stable version. The server was left stopped.");
            [output appendString:PackageMigrateConfig(selected,saved,S(installed[@"compiledConfig"]),backups)];PackageVerifyConfigs(saved);
            [result addEntriesFromDictionary:PackageLocalState()];result[@"ok"]=@YES;result[@"action"]=[before[@"installed"]boolValue]?@"updated":@"installed";result[@"message"]=[NSString stringWithFormat:@"Netatalk %@ %@ and verified. The server remains stopped; boot/login settings and accounts were preserved.",version,[before[@"installed"]boolValue]?@"updated":@"installed"];
        }
        // An earlier authorization cancellation must be retryable even if the
        // package is already current. This runs only for an explicit button click.
        if([result[@"ok"]boolValue]&&[result[@"installed"]boolValue]) {
            if(![PackagePAMState()[@"pamReady"]boolValue]) {
                @try{NSDictionary *setup=AdminCall(@{@"action":@"installPAM"},nil);[output appendFormat:@"\nAFP authentication setup: %@\n%@\n",S(setup[@"message"]),S(setup[@"output"])];}
                @catch(NSException *authorization){[output appendFormat:@"\nNetatalk is installed, but AFP authentication setup was cancelled or failed: %@\n",[authorization reason]];}
            }
            [result addEntriesFromDictionary:PackagePAMState()];result[@"setupRequired"]=@(![result[@"pamReady"]boolValue]);
            if([result[@"setupRequired"]boolValue])result[@"message"]=[S(result[@"message"])stringByAppendingString:@" AFP authentication setup is still required; see the PAM status."];
        }
    }@catch(NSException *e){result[@"ok"]=@NO;result[@"message"]=[e reason]?:@"Netatalk package operation failed.";}
    @finally{if(metadata>=0){flock(metadata,LOCK_UN);close(metadata);}if(lock>=0){flock(lock,LOCK_UN);close(lock);}}
    result[@"output"]=output;result[@"backup"]=backups;result[@"checkedAtEpoch"]=@([[NSDate date]timeIntervalSince1970]);PackageCache(result);return result;
}

// Explicit test-only invocation. All paths come from one disposable fixture;
// no Homebrew command, network request, app preference or real config is used.
NSDictionary *PackageSafetySelfTest(void){
    NSFileManager *fm=[NSFileManager defaultManager];NSString *base=[[NSTemporaryDirectory()stringByAppendingPathComponent:[@"afp-package-tests-"stringByAppendingString:[[NSUUID UUID]UUIDString]]]stringByResolvingSymlinksInPath];NSMutableArray *checks=[NSMutableArray array];
    @try {
        NSString *sourceDir=[base stringByAppendingPathComponent:@"selected"],*defaultDir=[base stringByAppendingPathComponent:@"default"],*backupDir=[base stringByAppendingPathComponent:@"backup"];
        for(NSString *path in @[sourceDir,defaultDir,backupDir])if(![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700}error:NULL])Fail(@"Cannot create disposable package fixture.");
        NSString *selected=[sourceDir stringByAppendingPathComponent:@"afp.conf"],*compiled=[defaultDir stringByAppendingPathComponent:@"afp.conf"];
        NSData *old=[@"[Global]\nserver name=Existing\n[Classic]\npath=/fixture/share\n"dataUsingEncoding:NSUTF8StringEncoding],*existing=[@"[Global]\nserver name=Existing default\n"dataUsingEncoding:NSUTF8StringEncoding],*generated=[@"[Global]\n[Homes]\n"dataUsingEncoding:NSUTF8StringEncoding];
        if(![old writeToFile:selected options:NSDataWritingWithoutOverwriting error:NULL]||![existing writeToFile:compiled options:NSDataWritingWithoutOverwriting error:NULL])Fail(@"Cannot create disposable config files.");
        const char marker[]="config-metadata";if(setxattr([selected fileSystemRepresentation],"org.local.afpserver.package-test",marker,sizeof marker,0,0))Fail(@"Cannot set disposable config metadata.");
        NSDictionary *saved=PackageBackupConfigPaths(@[selected,compiled],backupDir);PackageVerifyConfigs(saved);
        NSString *sourceBackup=saved[selected][@"backup"];
        if([saved count]!=2||![[NSData dataWithContentsOfFile:sourceBackup]isEqualToData:old]||![[NSData dataWithContentsOfFile:saved[compiled][@"backup"]]isEqualToData:existing])Fail(@"Config backup bytes did not verify.");
        struct stat privateBackup;if(lstat([sourceBackup fileSystemRepresentation],&privateBackup)||(privateBackup.st_mode&0777)!=0600)Fail(@"Config backups were not private.");
        char copied[32]={0};NSString *metadata=[sourceBackup stringByAppendingString:@".metadata"];if(getxattr([metadata fileSystemRepresentation],"org.local.afpserver.package-test",copied,sizeof copied,0,0)!=sizeof marker||memcmp(marker,copied,sizeof marker))Fail(@"Config metadata backup did not preserve the original attributes.");
        NSDictionary *manifest=JSONFile([backupDir stringByAppendingPathComponent:@"manifest.json"]);if([manifest[@"files"]count]!=2)Fail(@"Verified config backup manifest is incomplete.");[checks addObject:@"Private verified config byte/metadata backups and manifest"];
        NSString *message=PackageMigrateConfigContents(selected,saved,compiled,backupDir);
        if([message length]||![[NSData dataWithContentsOfFile:compiled]isEqualToData:existing]||![[NSData dataWithContentsOfFile:selected]isEqualToData:old])Fail(@"A pre-existing default configuration was overwritten.");[checks addObject:@"Pre-existing default configuration preserved"];
        // A separate snapshot precedes creation of the package's new default.
        NSString *freshBackup=[base stringByAppendingPathComponent:@"fresh-backup"];if(![fm createDirectoryAtPath:freshBackup withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700}error:NULL])Fail(@"Cannot create fresh backup fixture.");
        if(![fm removeItemAtPath:compiled error:NULL])Fail(@"Cannot remove disposable default before its install simulation.");
        NSDictionary *fresh=PackageBackupConfigPaths(@[selected,compiled],freshBackup);if(fresh[compiled]||![generated writeToFile:compiled options:NSDataWritingWithoutOverwriting error:NULL]||chmod([compiled fileSystemRepresentation],0640))Fail(@"Cannot simulate a newly created package default.");
        if(![PackageMigrateConfigContents(selected,fresh,compiled,freshBackup)length]||![[NSData dataWithContentsOfFile:compiled]isEqualToData:old]||![[NSData dataWithContentsOfFile:[freshBackup stringByAppendingPathComponent:@"new-package-default.conf"]]isEqualToData:generated])Fail(@"New-default migration or its original-default backup did not verify.");
        struct stat migrated;if(lstat([compiled fileSystemRepresentation],&migrated)||(migrated.st_mode&0777)!=0640)Fail(@"Migration did not preserve the new default's permissions.");PackageVerifyConfigs(fresh);[checks addObject:@"New default migrated with generated default backed up and permissions preserved"];
        NSString *staleBackup=[base stringByAppendingPathComponent:@"stale-backup"];if(![fm createDirectoryAtPath:staleBackup withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700}error:NULL])Fail(@"Cannot create stale-source fixture.");
        if(![fm removeItemAtPath:compiled error:NULL])Fail(@"Cannot reset disposable default.");NSDictionary *stale=PackageBackupConfigPaths(@[selected,compiled],staleBackup);
        NSData *changed=[@"[Global]\nserver name=Changed externally\n"dataUsingEncoding:NSUTF8StringEncoding];if(![generated writeToFile:compiled options:NSDataWritingWithoutOverwriting error:NULL]||![changed writeToFile:selected options:0 error:NULL])Fail(@"Cannot simulate a concurrent config edit.");
        BOOL rejected=NO;@try{PackageMigrateConfigContents(selected,stale,compiled,staleBackup);}@catch(NSException *e){rejected=YES;}
        if(!rejected||![[NSData dataWithContentsOfFile:compiled]isEqualToData:generated]||![[NSData dataWithContentsOfFile:selected]isEqualToData:changed])Fail(@"Migration replaced a default or source after the source changed.");[checks addObject:@"Stale selected source rejected without replacing the new default"];
        rejected=NO;@try{PackageVerifyConfigs(stale);}@catch(NSException *e){rejected=YES;}if(!rejected)Fail(@"A changed original config was not detected after installation.");[checks addObject:@"Changed original configuration detected before service use"];
        return @{@"ok":@YES,@"count":@([checks count]),@"checks":checks};
    }@catch(NSException *e){return @{@"ok":@NO,@"count":@([checks count]),@"checks":checks,@"error":[e reason]?:@"Unknown package safety error"};}
    @finally{[fm removeItemAtPath:base error:NULL];}
}
