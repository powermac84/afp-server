#import "Core.h"
#include <copyfile.h>
static NSString *RString(NSDictionary *r,NSString *k){return S(r[k]);}
static NSString *CanonicalConfig(NSString *path) { return [[S(path)stringByStandardizingPath]stringByResolvingSymlinksInPath]; }
static void ValidateServiceConfig(NSDictionary *install) {
    NSString *selected=CanonicalConfig(install[@"config"]),*service=CanonicalConfig(install[@"serviceConfig"]);
    if(![service length])Fail(@"The Netatalk service's configuration file could not be established. No service change was made. Check the service arguments or the daemon's compiled configuration path.");
    if(![selected length]||![selected isEqualToString:service])Fail([NSString stringWithFormat:@"The selected configuration (%@) differs from the service configuration (%@). Select the service's afp.conf before starting or restarting Netatalk. No service change was made.",selected,service]);
}
static void ValidateActiveConfig(NSString *selected,NSDictionary *install,BOOL running) {
    if(!running)return; // A stopped daemon does not make a fallback path authoritative.
    NSString *active=CanonicalConfig(install[@"activeConfig"]);
    if(![active length])Fail(@"The running daemon's configuration file could not be verified. No configuration was changed. Stop Netatalk explicitly before editing a different configuration.");
    if(![CanonicalConfig(selected)isEqualToString:active])Fail([NSString stringWithFormat:@"The selected configuration (%@) differs from the running daemon's configuration (%@). No configuration was changed.",selected,active]);
}
static void RequireInstalledService(NSDictionary *install) {
    if(![S(install[@"binary"])length]&&![S(install[@"controller"])length]&&![S(install[@"plist"])length])Fail(@"No installed Netatalk binary or supported service was found. An afp.conf alone is not a server installation. No server installation was changed.");
}
NSDictionary *AdminCall(NSDictionary *request,NSString *secret){
    NSString *action=RString(request,@"action");
    if([action isEqualToString:@"start"]||[action isEqualToString:@"restart"]||([action isEqualToString:@"boot"]&&[request[@"enabled"]boolValue])) {
        NSDictionary *install=Installation(RString(request,@"config"));RequireInstalledService(install);ValidateServiceConfig(install);
    }
    NSFileManager *fm=[NSFileManager defaultManager];NSString *dir=[NSTemporaryDirectory()stringByAppendingPathComponent:[@"afp-admin-"stringByAppendingString:[[NSUUID UUID]UUIDString]]];
    NSError *error=nil;if(![fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])Fail(S([error localizedDescription]));
    dir=[dir stringByResolvingSymlinksInPath];NSMutableDictionary *payload=[request mutableCopy];payload[@"callerUID"]=@(getuid());int fd=-1;int metadataLock=-1;
    @try {
        if(![@[@"snapshot",@"installPAM"]containsObject:S(request[@"action"])]){
            NSString *lockPath=[SupportDir()stringByAppendingPathComponent:@"metadata.lock"];
            metadataLock=open([lockPath fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
            if(metadataLock<0||flock(metadataLock,LOCK_EX|LOCK_NB)!=0)Fail(@"Metadata maintenance is currently running. Retry this server change when it finishes.");
        }
        if(secret){NSData *d=[[secret stringByAppendingString:@"\n"]dataUsingEncoding:NSUTF8StringEncoding];if([d length]<9||[d length]>1025||[secret rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound)Fail(@"Use a password of 8-1024 UTF-8 bytes without control characters.");
            NSString *pipe=[dir stringByAppendingPathComponent:@"password.fifo"];if(mkfifo([pipe fileSystemRepresentation],0600)!=0)Fail(@"Cannot create the in-memory password pipe.");
            fd=open([pipe fileSystemRepresentation],O_RDWR|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);if(fd<0 || write(fd,[d bytes],[d length])!=(ssize_t)[d length])Fail(@"Cannot fill the secure password pipe.");payload[@"secretPipe"]=pipe;
        }
        NSString *path=[dir stringByAppendingPathComponent:@"request.json"];if(!SaveJSON(payload,path))Fail(@"Cannot create the administrator request.");
        NSString *cmd=[NSString stringWithFormat:@"%@ --admin %@",Quote(HelperPath()),Quote(path)];
        NSString *esc=[[cmd stringByReplacingOccurrencesOfString:@"\\"withString:@"\\\\"]stringByReplacingOccurrencesOfString:@"\""withString:@"\\\""];
        NSString *script=[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges\n",esc];
        NSDictionary *r=Run(@"/usr/bin/osascript",[NSArray array],1800,[script dataUsingEncoding:NSUTF8StringEncoding]);
        if(![r[@"ok"]boolValue])Fail([@"Administrator operation was cancelled or failed.\n"stringByAppendingString:S(r[@"out"])]);
        NSData *data=[Trim(r[@"out"])dataUsingEncoding:NSUTF8StringEncoding];NSDictionary *result=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if(![result isKindOfClass:[NSDictionary class]])Fail([@"Unexpected administrator response:\n"stringByAppendingString:S(r[@"out"])]);
        return result;
    } @finally {if(metadataLock>=0){flock(metadataLock,LOCK_UN);close(metadataLock);}if(fd>=0)close(fd);[fm removeItemAtPath:dir error:NULL];}
}
// A process-query error must never be interpreted as an offline server.
static BOOL AdminRunning(NSString *name) {
    NSDictionary *r=Run(@"/usr/bin/pgrep",@[@"-x",name],4,nil);
    NSInteger code=[r[@"code"] integerValue];
    if(code==0)return YES;
    if(code==1)return NO;
    Fail([NSString stringWithFormat:@"Cannot establish whether %@ is running. No server change or offline maintenance was attempted.\n%@",name,S(r[@"out"])]);
}
static BOOL Listener(void){
    NSDictionary *result=Run(@"/usr/sbin/lsof",@[@"-nP",@"-a",@"-c",@"afpd",@"-iTCP",@"-FpcufnT"],4,nil);
    if([result[@"code"]integerValue]>1)Fail([@"Cannot inspect AFP listening sockets.\n"stringByAppendingString:S(result[@"out"])]);
    for(NSDictionary *s in SocketRows(result[@"out"]))if([s[@"state"]isEqualToString:@"LISTEN"])return YES;return NO;
}
static BOOL WaitServer(BOOL on){NSDate *d=[NSDate dateWithTimeIntervalSinceNow:15];do{if(on?Listener():(!AdminRunning(@"afpd")&&!AdminRunning(@"netatalk")&&!AdminRunning(@"cnid_dbd")&&!AdminRunning(@"cnid_metad")))return YES;[NSThread sleepForTimeInterval:0.3];}while([d timeIntervalSinceNow]>0);return NO;}
static BOOL Loaded(NSString *label){return [label length]&&[Run(@"/bin/launchctl",@[@"print",[@"system/"stringByAppendingString:label]],4,nil)[@"ok"]boolValue];}
static NSString *StartServer(NSDictionary *i){
    RequireInstalledService(i);ValidateServiceConfig(i);
    if(AdminRunning(@"afpd")||AdminRunning(@"netatalk")){if(!WaitServer(YES))Fail(@"Netatalk is running but no AFP listener was verified. No duplicate server was started.");return @"AFP listener is already active.";}
    NSString *label=S(i[@"label"]),*plist=S(i[@"plist"]);NSMutableString *out=[NSMutableString string];
    if([label length]&&[plist length]&&[i[@"boot"]boolValue]){
        if(!Loaded(label))[out appendString:Checked(@"/bin/launchctl",@[@"bootstrap",@"system",plist],30)];
        [out appendString:Checked(@"/bin/launchctl",@[@"kickstart",[@"system/"stringByAppendingString:label]],30)];
    }else if([S(i[@"controller"])length])[out appendString:Checked(i[@"controller"],@[@"start"],40)];
    else if([S(i[@"brew"])length])[out appendString:Checked(i[@"brew"],@[@"services",@"run",@"netatalk"],90)];
    else Fail(@"No supported Netatalk service was found. Install Netatalk with Homebrew, or provide its netatalkd controller. The app does not install a second server.");
    if(!WaitServer(YES))Fail([@"The start command finished, but AFP did not open a verified listening socket.\n"stringByAppendingString:out]);
    [out appendString:@"\nAFP listener verified."];return out;
}
static NSString *StopServer(NSDictionary *i){
    (void)AdminRunning(@"afpd");(void)AdminRunning(@"netatalk");
    NSString *label=S(i[@"label"]);NSMutableString *out=[NSMutableString string];
    if(Loaded(label))[out appendString:Checked(@"/bin/launchctl",@[@"bootout",[@"system/"stringByAppendingString:label]],40)];
    else if([S(i[@"controller"])length])[out appendString:Checked(i[@"controller"],@[@"stop"],40)];
    else if([S(i[@"brew"])length])[out appendString:Checked(i[@"brew"],@[@"services",@"stop",@"netatalk",@"--keep"],90)];
    else if(AdminRunning(@"afpd")||AdminRunning(@"netatalk"))Fail(@"Unknown server service manager. The app will not kill all afpd processes blindly.");
    if(!WaitServer(NO))Fail(@"AFP is still running. Offline maintenance was not started.");[out appendString:@"\nAFP is stopped."];return out;
}
static NSString *RestartServer(NSDictionary *i){RequireInstalledService(i);ValidateServiceConfig(i);NSMutableString *s=[StopServer(i)mutableCopy];[NSThread sleepForTimeInterval:0.5];[s appendString:@"\n"];[s appendString:StartServer(Installation(i[@"config"]))];return s;}
static NSDictionary *Reply(BOOL ok,NSString *msg,NSString *out){return @{@"ok":@(ok),@"message":msg?:@"",@"output":out?:@""};}
static NSString *ConfigTextFD(int fd) {
    struct stat a,b;if(fstat(fd,&a)||!S_ISREG(a.st_mode)||a.st_nlink!=1||a.st_size<0||a.st_size>4000000)Fail(@"afp.conf must be a regular, singly linked file smaller than 4 MB.");
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)a.st_size];size_t done=0;
    while(done<[data length]){ssize_t n=pread(fd,(char *)[data mutableBytes]+done,[data length]-done,(off_t)done);if(n<0&&errno==EINTR)continue;if(n<=0)Fail(@"afp.conf changed or could not be read safely.");done+=(size_t)n;}
    if(fstat(fd,&b)||a.st_size!=b.st_size||a.st_mtimespec.tv_sec!=b.st_mtimespec.tv_sec||a.st_mtimespec.tv_nsec!=b.st_mtimespec.tv_nsec)Fail(@"afp.conf changed while being read. Refresh before saving.");
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(!text)Fail(@"afp.conf is not valid UTF-8 text.");return text;
}
static void AtomicWrite(NSString *path,NSString *text,NSString *expected){
    NSString *parent=[path stringByDeletingLastPathComponent],*name=[path lastPathComponent],*temp=[@".afpserver-"stringByAppendingString:[[NSUUID UUID]UUIDString]];
    int directory=-1,source=-1,destination=-1;BOOL staged=NO;
    @try {
        directory=open([parent fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(directory<0)Fail(@"Cannot open the configuration directory safely.");
        source=openat(directory,[name fileSystemRepresentation],O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(source<0||flock(source,LOCK_EX|LOCK_NB))Fail(@"Cannot exclusively inspect the configuration file.");
        if(![ConfigTextFD(source)isEqualToString:expected])Fail(@"afp.conf changed before replacement. No newer configuration was overwritten.");
        struct stat original,current;if(fstat(source,&original))Fail(@"Cannot inspect afp.conf.");
        destination=openat(directory,[temp fileSystemRepresentation],O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);if(destination<0)Fail(@"Cannot create the staged configuration.");staged=YES;
        if(fcopyfile(source,destination,NULL,COPYFILE_ALL))Fail(@"Cannot preserve afp.conf metadata and permissions.");
        NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];if(ftruncate(destination,0))Fail(@"Cannot write staged afp.conf.");size_t done=0;
        while(done<[data length]){ssize_t n=pwrite(destination,(const char *)[data bytes]+done,[data length]-done,(off_t)done);if(n<0&&errno==EINTR)continue;if(n<=0)Fail(@"Cannot write staged afp.conf.");done+=(size_t)n;}
        if(fsync(destination))Fail(@"Cannot synchronize staged afp.conf.");
        if(fstatat(directory,[name fileSystemRepresentation],&current,AT_SYMLINK_NOFOLLOW)||!S_ISREG(current.st_mode)||current.st_dev!=original.st_dev||current.st_ino!=original.st_ino||![ConfigTextFD(source)isEqualToString:expected])Fail(@"afp.conf changed during staging. No newer configuration was overwritten.");
        if(renameat(directory,[temp fileSystemRepresentation],directory,[name fileSystemRepresentation]))Fail(@"Atomic replacement of afp.conf failed.");staged=NO;fsync(directory);
    } @finally {if(destination>=0)close(destination);if(source>=0){flock(source,LOCK_UN);close(source);}if(directory>=0){if(staged)unlinkat(directory,[temp fileSystemRepresentation],0);close(directory);}}
}
static NSDictionary *ApplyConfig(NSDictionary *r){
    NSString *path=[RString(r,@"config")stringByResolvingSymlinksInPath];if(![[path lastPathComponent]isEqualToString:@"afp.conf"])Fail(@"Only an explicit afp.conf can be edited.");
    BOOL was=AdminRunning(@"afpd")||AdminRunning(@"netatalk");NSDictionary *install=Installation(path);ValidateActiveConfig(path,install,was);if(was){RequireInstalledService(install);ValidateServiceConfig(install);}
    NSString *old=ReadText(path),*expected=RString(r,@"expected"),*text=RString(r,@"text");if(![old isEqualToString:expected])Fail(@"afp.conf changed since it was opened. Refresh before saving; nothing was overwritten.");
    AFPConfig *cfg=[[AFPConfig alloc]initWithText:text];[cfg validate];
    NSDictionary *attrs=[[NSFileManager defaultManager]attributesOfItemAtPath:path error:NULL];if(![attrs[NSFileType]isEqualToString:NSFileTypeRegular])Fail(@"The config is not a regular file.");
    NSString *backup=[path stringByAppendingFormat:@".backup.%@",[[NSUUID UUID]UUIDString]];
    Checked(@"/usr/bin/ditto",@[@"--rsrc",@"--extattr",@"--acl",path,backup],30);chmod([backup fileSystemRepresentation],0600);
    NSMutableString *out=[NSMutableString stringWithFormat:@"Configuration backup: %@\n",backup];
    AtomicWrite(path,text,old);
    @try{
        if(![ReadText(path)isEqualToString:text])Fail(@"Written config did not match the requested text.");
        if(was){[out appendString:RestartServer(install)];NSString *port=S([cfg global][@"afp port"]);if(![port length])port=@"548";if(![S([cfg global][@"afp listen"])length]){BOOL match=NO;for(NSDictionary *sock in SocketRows(Run(@"lsof",@[@"-nP",@"-a",@"-c",@"afpd",@"-iTCP",@"-FpcufnT"],5,nil)[@"out"]))if([sock[@"state"]isEqualToString:@"LISTEN"]&&[S(sock[@"local"])hasSuffix:[@":"stringByAppendingString:port]])match=YES;if(!match)Fail(@"The configured AFP port was not verified after restart.");}}
        else [out appendString:@"The server was stopped and remains stopped.\n"];
        return Reply(YES,@"afp.conf was backed up, saved atomically, and verified.",out);
    }@catch(NSException *e){@try{AtomicWrite(path,old,text);} @catch(NSException *restore){[out appendFormat:@"\nChange failed: %@\nROLLBACK FAILED: %@\nBackup retained at %@.\n",[e reason],[restore reason],backup];return Reply(NO,@"Configuration change failed; rollback was not completed.",out);}[out appendFormat:@"\nThe change failed: %@\nRestored the previous configuration.\n",[e reason]];if(was){@try{[out appendString:RestartServer(Installation(path))];}@catch(NSException *restart){[out appendFormat:@"\nRESTORE RESTART FAILED: %@",[restart reason]];}}return Reply(NO,@"Configuration change rolled back.",out);}
}
static void ValidateUser(NSString *name){if(!Match(@"^[a-z][a-z0-9_-]{0,30}$",name)||[@[@"root",@"admin",@"daemon",@"nobody"]containsObject:name])Fail(@"Account name: 1-31 lowercase ASCII characters, beginning with a letter; no system account names.");}
static BOOL ManagedUser(NSString *name){ValidateUser(name);NSDictionary *r=Run(@"/usr/bin/dscl",@[@".",@"-read",[@"/Users/"stringByAppendingString:name],@"Comment",@"UniqueID"],5,nil);NSArray *m=Match(@"UniqueID:\\s*(\\d+)",r[@"out"]);return [r[@"ok"]boolValue]&&m&&[m[1]integerValue]>=500&&[S(r[@"out"])containsString:@"AFPServerManaged:v1"];}
static NSString *Password(NSDictionary *r){
    NSString *path=RString(r,@"secretPipe"),*parent=[path stringByDeletingLastPathComponent];
    if(![[path lastPathComponent]isEqualToString:@"password.fifo"])Fail(@"The password pipe is missing or invalid.");
    int directory=-1,fd=-1;unsigned char b[2048]={0};NSString *secret=nil;
    @try {
        directory=open([parent fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);struct stat d,a;
        uid_t uid=(uid_t)[r[@"callerUID"]unsignedIntValue];
        if(!uid||directory<0||fstat(directory,&d)||!S_ISDIR(d.st_mode)||d.st_uid!=uid||(d.st_mode&077))Fail(@"Unsafe password-channel directory.");
        fd=openat(directory,"password.fifo",O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
        if(fd<0||fstat(fd,&a)||!S_ISFIFO(a.st_mode)||a.st_uid!=uid||(a.st_mode&077)||a.st_nlink!=1)Fail(@"The password channel is not a private FIFO owned by the caller.");
        ssize_t n;do{n=read(fd,b,sizeof b);}while(n<0&&errno==EINTR);
        if(n<9||n>1025||b[n-1]!='\n')Fail(@"The password pipe is empty or malformed.");
        secret=[[NSString alloc]initWithBytes:b length:(NSUInteger)n-1 encoding:NSUTF8StringEncoding];
        if(!secret||[secret rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound)Fail(@"Use a password of 8-1024 UTF-8 bytes without control characters.");
    } @finally {for(volatile unsigned char *v=b;v<b+sizeof b;v++)*v=0;if(fd>=0)close(fd);if(directory>=0)close(directory);}
    return secret;
}
static void SetPassword(NSString *name,NSString *secret){NSError *e=nil;ODNode *node=[ODNode nodeWithSession:[ODSession defaultSession]name:@"/Local/Default"error:&e];if(!node)Fail(S([e localizedDescription]));ODRecord *rec=[node recordWithRecordType:kODRecordTypeUsers name:name attributes:kODAttributeTypeAllAttributes error:&e];if(!rec)Fail(S([e localizedDescription]));if(![rec changePassword:nil toPassword:secret error:&e]||![rec verifyPassword:secret error:&e])Fail([@"macOS could not set/verify this password: "stringByAppendingString:S([e localizedDescription])]);}
static NSDictionary *CreateUser(NSDictionary *r){
    NSString *name=RString(r,@"user");ValidateUser(name);NSString *pw=Password(r);
    NSMutableSet *ids=[NSMutableSet set],*names=[NSMutableSet set];
    for(NSString *line in Lines(Checked(@"/usr/bin/dscl",@[@".",@"-list",@"/Users",@"UniqueID"],6))){NSArray *m=Match(@"^(\\S+)\\s+(\\d+)\\s*$",line);if(m){[names addObject:m[1]];[ids addObject:m[2]];}}
    if([names containsObject:name])Fail(@"An account with this name already exists. It was not changed.");
    NSInteger uid=501;while([ids containsObject:[NSString stringWithFormat:@"%ld",(long)uid]]&&uid<65000)uid++;if(uid>=65000)Fail(@"No free local user ID.");
    NSError *error=nil;ODNode *node=[ODNode nodeWithSession:[ODSession defaultSession]name:@"/Local/Default"error:&error];if(!node)Fail(S([error localizedDescription]));
    NSDictionary *attributes=@{kODAttributeTypeUniqueID:@[[NSString stringWithFormat:@"%ld",(long)uid]],kODAttributeTypePrimaryGroupID:@[@"20"],kODAttributeTypeGUID:@[[[NSUUID UUID]UUIDString]],kODAttributeTypeFullName:@[[RString(r,@"display")length]?RString(r,@"display"):name],kODAttributeTypeUserShell:@[@"/usr/bin/false"],kODAttributeTypeNFSHomeDirectory:@[@"/var/empty"],@"dsAttrTypeNative:IsHidden":@[@"1"],kODAttributeTypePassword:@[@"*"],kODAttributeTypeComment:@[@"AFPServerManaged:v1"]};
    // Unlike dscl -create, createRecord fails if the name already exists.
    ODRecord *record=[node createRecordWithRecordType:kODRecordTypeUsers name:name attributes:attributes error:&error];if(!record)Fail([@"Sharing account was not created: "stringByAppendingString:S([error localizedDescription])]);
    @try {
        if(![record changePassword:nil toPassword:pw error:&error]||![record verifyPassword:pw error:&error])Fail([@"macOS could not set/verify this password: "stringByAppendingString:S([error localizedDescription])]);
        return Reply(YES,@"Non-administrator sharing account created.",@"This is a real local macOS account, hidden from the login list, with no login shell and no personal home directory. Add it to the share's allowed-users list and grant suitable folder permissions. Enable 'Allow no-login-shell accounts' for Netatalk explicitly.");
    } @catch(NSException *e){NSError *cleanup=nil;if(![record deleteRecordAndReturnError:&cleanup])Fail([NSString stringWithFormat:@"%@\nThe partially created account could not be removed: %@",[e reason],[cleanup localizedDescription]]);@throw e;}
}
static NSDictionary *ConfigAndShare(NSDictionary *r){NSString *cfg=RString(r,@"config"),*section=RString(r,@"section");if(![[cfg lastPathComponent]isEqualToString:@"afp.conf"])Fail(@"Invalid config path.");AFPConfig *c=[[AFPConfig alloc]initWithText:ReadText(cfg)];for(NSDictionary *s in [c shares])if([[s[@"section"]lowercaseString]isEqualToString:[section lowercaseString]]){NSMutableDictionary *ret=[s mutableCopy];ret[@"root"]=SafeRoot(s[@"path"]);ret[@"global"]=[c global];return ret;}Fail(@"The selected share no longer exists in afp.conf.");}
static NSDictionary *CNID(NSDictionary *r){NSDictionary *share=ConfigAndShare(r);NSString *root=share[@"root"],*cfg=RString(r,@"config");BOOL repair=[r[@"repair"]boolValue];if(!Tool(@"dbd"))Fail(@"Netatalk's dbd tool was not found.");BOOL was=AdminRunning(@"afpd")||AdminRunning(@"netatalk");NSDictionary *serverInstallation=Installation(@"");
    if(was){ValidateActiveConfig(serverInstallation[@"config"],serverInstallation,YES);RequireInstalledService(serverInstallation);ValidateServiceConfig(serverInstallation);}
    NSMutableString *out=[NSMutableString string];NSException *saved=nil;
    @try{
        if(was)[out appendString:StopServer(serverInstallation)];for(NSString *p in @[@"afpd",@"netatalk",@"cnid_dbd",@"cnid_metad"])if(AdminRunning(p))Fail([p stringByAppendingString:@" is still active. Offline CNID maintenance was not performed."]);
        if(repair){NSDictionary *o=share[@"options"],*g=share[@"global"];NSString *details=Installation(cfg)[@"details"];NSString *scheme=S(o[@"cnid scheme"]?:g[@"cnid scheme"]);if(![scheme length]){NSArray *m=Match(@"(?i)CNID default backend:\\s*(\\S+)",details);if(m)scheme=m[1];}if(![@[@"dbd",@"sqlite"]containsObject:scheme])Fail(@"CNID backend could not be identified safely. Use the read-only check.");
            NSString *db=@"";NSString *nest=[S(o[@"vol dbnest"]?:g[@"vol dbnest"])lowercaseString];BOOL nested=[@[@"yes",@"true",@"1"]containsObject:nest];if(nested)db=[root stringByAppendingPathComponent:@".AppleDB"];else db=S(o[@"vol dbpath"]?:g[@"vol dbpath"]);
            if(![db length]){NSArray *m=Match(@"(?i)CNID database location:\\s*(/[^\\r\\n]+)",details);if(m)db=Trim(m[1]);}
            db=[[db stringByStandardizingPath]stringByResolvingSymlinksInPath];if(![db hasPrefix:@"/"]||[db containsString:@"$"]||[@[@"/",@"/usr",@"/opt",@"/var",@"/private",@"/Library",@"/Users",root]containsObject:db])Fail(@"The database backup location is not safely identified. No repair without a backup.");
            if(IsDir(db)){NSString *backup=[[cfg stringByDeletingLastPathComponent]stringByAppendingPathComponent:[@"cnid-backup-"stringByAppendingString:[[NSUUID UUID]UUIDString]]];if(ad_path_contains([[db stringByResolvingSymlinksInPath]UTF8String],[[backup stringByResolvingSymlinksInPath]UTF8String]))Fail(@"The database backup would be inside its source.");[out appendString:Checked(@"/usr/bin/ditto",@[@"--rsrc",@"--extattr",db,backup],600)];chmod([backup fileSystemRepresentation],0700);[out appendFormat:@"\nDatabase backup: %@\n",backup];}else Fail(@"The CNID database directory is missing. No repair was performed without a verified backup.");
        }
        NSMutableArray *args=[NSMutableArray arrayWithArray:@[@"-t",@"-F",cfg]];if(!repair)[args insertObject:@"-s"atIndex:0];[args addObject:root];[out appendString:Checked(@"dbd",args,900)];
    }@catch(NSException *e){saved=e;[out appendFormat:@"\n%@\n",[e reason]];}
    if(was){@try{[out appendString:StartServer(serverInstallation)];}@catch(NSException *e){saved=e;[out appendFormat:@"\nSERVER RESTART FAILED: %@",[e reason]];}}
    return Reply(saved==nil,saved?[saved reason]:(repair?@"CNID reconciliation completed; no forced ID rebuild.":@"Read-only CNID check completed."),out);
}
static BOOL SupportedPAM(NSString *text) {
    NSMutableArray *rules=[NSMutableArray array];
    for(NSString *line in Lines(text)) {
        NSString *value=Trim(line);if(![value length]||[value hasPrefix:@"#"])continue;
        NSMutableArray *parts=[NSMutableArray array];
        for(NSString *part in [value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])if([part length])[parts addObject:part];
        [rules addObject:[parts componentsJoinedByString:@" "]];
    }
    return [rules isEqualToArray:@[@"auth required pam_opendirectory.so",@"account required pam_opendirectory.so",@"password required pam_permit.so",@"session required pam_permit.so"]];
}
static BOOL InstallMissingPAM(int directory,NSData *data,uid_t owner) {
    int current=openat(directory,"netatalk",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if(current>=0) {
        @try {
            struct stat st;if(fstat(current,&st)||!S_ISREG(st.st_mode)||st.st_nlink!=1||st.st_size<0||st.st_size>65536)Fail(@"The existing PAM policy is not a safe regular file. It was not changed.");
            NSMutableData *old=[NSMutableData dataWithLength:(NSUInteger)st.st_size];
            if(pread(current,[old mutableBytes],[old length],0)!=(ssize_t)[old length]||![old isEqualToData:data])Fail(@"A different existing Netatalk PAM policy is protected. Review it manually; no authentication policy was overwritten.");
            return NO;
        } @finally {close(current);}
    }
    if(errno!=ENOENT)Fail(@"The existing Netatalk PAM policy cannot be checked safely.");
    NSString *name=[@".afpserver-pam-"stringByAppendingString:[[NSUUID UUID]UUIDString]];
    int fd=openat(directory,[name fileSystemRepresentation],O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0)Fail(@"Cannot stage the Netatalk authentication policy.");
    @try {
        size_t done=0;while(done<[data length]){ssize_t n=write(fd,(const char *)[data bytes]+done,[data length]-done);if(n<0&&errno==EINTR)continue;if(n<=0)Fail(@"Cannot write the Netatalk authentication policy.");done+=(size_t)n;}
        if(fchown(fd,owner,owner==0?0:getgid())||fchmod(fd,0644)||fsync(fd))Fail(@"Cannot verify the authentication policy's permissions.");
        if(linkat(directory,[name fileSystemRepresentation],directory,"netatalk",0))Fail(@"A Netatalk authentication policy appeared during setup. It was not overwritten.");
        fsync(directory);return YES;
    } @finally {close(fd);unlinkat(directory,[name fileSystemRepresentation],0);}
}
static NSDictionary *InstallPAM(void) {
    NSString *source=@"/opt/homebrew/etc/pam.d/netatalk";
    NSData *data=[NSData dataWithContentsOfFile:source];
    if(!data)data=[NSData dataWithContentsOfFile:@"/usr/local/etc/pam.d/netatalk"];
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    if(!data||[data length]>65536||!SupportedPAM(text))Fail(@"The packaged PAM policy differs from the supported OpenDirectory policy. No system authentication setting was changed.");
    int local=-1,etc=-1,pam=-1;
    @try {
        local=open("/usr/local",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(local<0)Fail(@"Cannot safely open /usr/local.");
        if(mkdirat(local,"etc",0755)&&errno!=EEXIST)Fail(@"Cannot create the required local configuration directory.");
        etc=openat(local,"etc",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(etc<0)Fail(@"Cannot safely open /usr/local/etc.");
        if(mkdirat(etc,"pam.d",0755)&&errno!=EEXIST)Fail(@"Cannot create the dedicated PAM directory.");
        pam=openat(etc,"pam.d",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(pam<0)Fail(@"Cannot safely open the dedicated PAM directory.");
        BOOL changed=InstallMissingPAM(pam,data,0);
        return Reply(YES,changed?@"Netatalk OpenDirectory authentication policy installed.":@"The existing Netatalk authentication policy already matches.",@"Only /usr/local/etc/pam.d/netatalk was considered. Existing custom policies and directory ownership were preserved.");
    } @finally {if(pam>=0)close(pam);if(etc>=0)close(etc);if(local>=0)close(local);}
}

NSDictionary *AdminExecute(NSDictionary *r){
    if(geteuid()!=0)Fail(@"Administrator authorization is required.");NSString *action=RString(r,@"action");if([action isEqualToString:@"installPAM"])return InstallPAM();NSDictionary *install=Installation(RString(r,@"config"));
    if([action isEqualToString:@"snapshot"])return @{@"ok":@YES,@"message":@"Administrator snapshot captured.",@"snapshot":Snapshot(RString(r,@"config"))};
    if([action isEqualToString:@"start"])return Reply(YES,@"AFP server started.",StartServer(install));
    if([action isEqualToString:@"stop"])return Reply(YES,@"AFP server stopped.",StopServer(install));
    if([action isEqualToString:@"restart"])return Reply(YES,@"AFP server restarted.",RestartServer(install));
    if([action isEqualToString:@"applyConfig"])return ApplyConfig(r);
    if([action isEqualToString:@"boot"]){BOOL enable=[r[@"enabled"]boolValue];if(enable){RequireInstalledService(install);ValidateServiceConfig(install);}NSString *brew=S(install[@"brew"]);NSMutableString *out=[NSMutableString string];if([brew length]){BOOL was=AdminRunning(@"afpd")||AdminRunning(@"netatalk");if(was)ValidateServiceConfig(install);[out appendString:Checked(brew,@[@"services",enable?@"start":@"stop",@"netatalk"],90)];if(!enable&&was)[out appendString:Checked(brew,@[@"services",@"run",@"netatalk"],90)];if((enable||was)&&!WaitServer(YES))Fail([@"Boot setting changed but server listener was not verified.\n"stringByAppendingString:out]);}else{NSString *label=S(install[@"label"]);if(![label length])Fail(@"No supported system LaunchDaemon was found.");[out appendString:Checked(@"/bin/launchctl",@[enable?@"enable":@"disable",[@"system/"stringByAppendingString:label]],8)];if(enable&&!AdminRunning(@"afpd"))[out appendString:StartServer(Installation(RString(r,@"config")))];}return Reply(YES,enable?@"AFP starts at system boot.":@"AFP boot startup is disabled.",out);}
    if([action isEqualToString:@"createUser"])return CreateUser(r);
    if([action isEqualToString:@"resetPassword"]){NSString *name=RString(r,@"user");if(!ManagedUser(name))Fail(@"Only passwords for accounts created by this app may be reset.");SetPassword(name,Password(r));return Reply(YES,@"Account password changed and verified.",@"No password was logged or saved by the app.");}
    if([action isEqualToString:@"deleteUser"]){NSString *name=RString(r,@"user");if(!ManagedUser(name))Fail(@"Only app-managed sharing accounts may be removed.");return Reply(YES,@"Sharing account removed. No user files were deleted.",Checked(@"dscl",@[@".",@"-delete",[@"/Users/"stringByAppendingString:name]],12));}
    if([action isEqualToString:@"grantACL"]){NSDictionary *s=ConfigAndShare(r);NSString *name=RString(r,@"user");ValidateUser(name);Checked(@"/usr/bin/dscl",@[@".",@"-read",[@"/Users/"stringByAppendingString:name],@"UniqueID"],5);BOOL ro=[r[@"readOnly"]boolValue];NSString *rights=ro?@"list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit":@"list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit";NSString *ace=[NSString stringWithFormat:@"user:%@ allow %@",name,rights];NSString *before=Checked(@"/bin/ls",@[@"-led",s[@"root"]],5);NSString *out=Checked(@"/bin/chmod",@[@"+a",ace,s[@"root"]],8);return Reply(YES,@"Inheritable folder permission added; existing files were not changed recursively.",[NSString stringWithFormat:@"Before:\n%@\n%@\nAfter:\n%@\nAFP allowlists and file permissions are separate. Read-only permissions do not revoke existing write permissions.",before,out,Checked(@"/bin/ls",@[@"-led",s[@"root"]],5)]);}
    if([action isEqualToString:@"disconnect"]){NSString *pid=RString(r,@"pid");if(!Match(@"^[0-9]+$",pid)||[pid intValue]<=1)Fail(@"Invalid session PID.");NSArray *rows=SocketRows(Run(@"lsof",@[@"-nP",@"-a",@"-c",@"afpd",@"-iTCP",@"-FpcufnT"],5,nil)[@"out"]);BOOL established=NO;for(NSDictionary *row in rows)if([row[@"pid"]isEqualToString:pid]){if([row[@"state"]isEqualToString:@"LISTEN"])Fail(@"This PID owns a listener. It will not be disconnected.");if([row[@"state"]isEqualToString:@"ESTABLISHED"])established=YES;}NSString *cmd=Trim(Run(@"/bin/ps",@[@"-p",pid,@"-o",@"comm="],4,nil)[@"out"]);if(!established||![[cmd lastPathComponent]isEqualToString:@"afpd"])Fail(@"The selected AFP connection no longer matches. Nothing was terminated.");if(kill([pid intValue],SIGTERM)!=0)Fail(@"Could not disconnect the selected process.");return Reply(YES,@"Disconnect request sent to the selected AFP session.",@"Its ongoing file operations may have been interrupted.");}
    if([action isEqualToString:@"cnid"])return CNID(r);
    Fail(@"This administrator action is not allowed.");
}
int AdminMain(NSString *path){NSDictionary *reply=nil;int lock=-1,directory=-1,fd=-1;
    @try{
        if(geteuid()!=0)Fail(@"Run administrator operations through the app.");
        NSString *dir=[[path stringByDeletingLastPathComponent]stringByResolvingSymlinksInPath];
        if(![path hasPrefix:@"/"]||![[path lastPathComponent]isEqualToString:@"request.json"])Fail(@"Invalid administrator request path.");
        directory=open([dir fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);struct stat d,a;
        if(directory<0||fstat(directory,&d)||!S_ISDIR(d.st_mode)||(d.st_mode&077)||d.st_uid==0)Fail(@"Unsafe administrator request directory.");
        fd=openat(directory,"request.json",O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
        if(fd<0||fstat(fd,&a)||!S_ISREG(a.st_mode)||(a.st_mode&077)||a.st_nlink!=1||a.st_size>4000000||a.st_size<0||a.st_uid!=d.st_uid)Fail(@"Unsafe administrator request file.");
        NSMutableData *data=[NSMutableData data];unsigned char bytes[8192];ssize_t n;
        while((n=read(fd,bytes,sizeof bytes))!=0){if(n<0&&errno==EINTR)continue;if(n<0)Fail(@"Cannot read administrator request.");[data appendBytes:bytes length:(NSUInteger)n];if([data length]>4000000)Fail(@"Administrator request is too large.");}
        close(fd);fd=-1;
        NSDictionary *r=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if(![r isKindOfClass:[NSDictionary class]]||![r[@"callerUID"]isKindOfClass:[NSNumber class]]||[r[@"callerUID"]unsignedIntValue]!=a.st_uid)Fail(@"Invalid request owner.");
        if([S(r[@"secretPipe"])length]){
            NSString *pipe=RString(r,@"secretPipe");struct stat pa;
            if(![[[pipe stringByDeletingLastPathComponent]stringByResolvingSymlinksInPath]isEqualToString:dir]||![[pipe lastPathComponent]isEqualToString:@"password.fifo"]||fstatat(directory,"password.fifo",&pa,AT_SYMLINK_NOFOLLOW)||!S_ISFIFO(pa.st_mode)||pa.st_uid!=a.st_uid||(pa.st_mode&077)||pa.st_nlink!=1)Fail(@"Unsafe password channel.");
        }
        if(unlinkat(directory,"request.json",0))Fail(@"Cannot consume administrator request.");
        lock=open("/var/run/afpserver-control.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);struct stat control;
        if(lock<0||fstat(lock,&control)||!S_ISREG(control.st_mode)||control.st_uid!=0||(control.st_mode&077)||control.st_nlink!=1||flock(lock,LOCK_EX|LOCK_NB)!=0)Fail(@"Another administrator operation is in progress or the control lock is unsafe.");reply=AdminExecute(r);
    }@catch(NSException *e){reply=Reply(NO,[e reason],@"");}@finally{if(fd>=0)close(fd);if(directory>=0)close(directory);if(lock>=0){flock(lock,LOCK_UN);close(lock);}}
    NSData *out=[[JSON(reply)stringByAppendingString:@"\n"]dataUsingEncoding:NSUTF8StringEncoding];write(1,[out bytes],[out length]);return 0;
}
void OldAgentsRemove(void){
    NSString *domain=[NSString stringWithFormat:@"gui/%d",getuid()];NSFileManager *fm=[NSFileManager defaultManager];
    NSString *label=@"com.netatalk.classic-metadata";NSString *plist=[NSHomeDirectory()stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/LaunchAgents/%@.plist",label]];
    Run(@"/bin/launchctl",@[@"bootout",[domain stringByAppendingFormat:@"/%@",label]],8,nil);if([fm fileExistsAtPath:plist]){Run(@"/bin/launchctl",@[@"unload",plist],8,nil);if([Run(@"/bin/launchctl",@[@"print",[domain stringByAppendingFormat:@"/%@",label]],5,nil)[@"ok"]boolValue])Fail(@"The old agent is still loaded. Its files were not removed.");[fm removeItemAtPath:plist error:NULL];}
    for(NSString *n in @[@"netatalk-classic-metadata.sh",@"netatalk-metadaten-pflege.sh"]){NSString *p=[NSHomeDirectory()stringByAppendingPathComponent:[@"bin/"stringByAppendingString:n]];if([fm fileExistsAtPath:p]){NSString *text=ReadText(p);if([text containsString:@"dot_clean"])[fm removeItemAtPath:p error:NULL];}}
    Log(@"Removed legacy v1-v6 metadata agent. Netatalk and shared files were not changed.");
}

// Explicit regression entry point. Never invoked by application startup.
NSDictionary *AdminSafetySelfTest(void) {
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *dir=[[NSTemporaryDirectory()stringByAppendingPathComponent:[@"afp-admin-tests-"stringByAppendingString:[[NSUUID UUID]UUIDString]]]stringByResolvingSymlinksInPath];
    NSMutableArray *checks=[NSMutableArray array];int pipe=-1;
    @try {
        NSError *error=nil;if(![fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700}error:&error])Fail(S([error localizedDescription]));
        NSString *path=[dir stringByAppendingPathComponent:@"afp.conf"];
        NSString *old=@"[Global]\nserver name=before\n",*next=@"[Global]\nserver name=after\n";
        if(![old writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:&error]||chmod([path fileSystemRepresentation],0640))Fail(@"Cannot create disposable configuration.");
        const char marker[]="preserved";if(setxattr([path fileSystemRepresentation],"org.local.afpserver.test",marker,sizeof marker,0,0))Fail(@"Cannot set disposable configuration metadata.");
        AtomicWrite(path,next,old);if(![ReadText(path)isEqualToString:next])Fail(@"Atomic config replacement did not preserve requested content.");[checks addObject:@"Atomic configuration replacement"];
        struct stat a;if(lstat([path fileSystemRepresentation],&a)||(a.st_mode&0777)!=0640)Fail(@"Config permissions were not preserved.");
        char markerOut[32]={0};if(getxattr([path fileSystemRepresentation],"org.local.afpserver.test",markerOut,sizeof markerOut,0,0)!=sizeof marker||memcmp(marker,markerOut,sizeof marker))Fail(@"Config extended attributes were not preserved.");[checks addObject:@"Configuration permissions and metadata preserved"];
        BOOL rejected=NO;@try{AtomicWrite(path,old,old);}@catch(NSException *e){rejected=YES;}
        if(!rejected||![ReadText(path)isEqualToString:next])Fail(@"A stale configuration request replaced newer content.");[checks addObject:@"Stale configuration write rejected"];
        NSString *link=[dir stringByAppendingPathComponent:@"linked.conf"];
        if(symlink([path fileSystemRepresentation],[link fileSystemRepresentation]))Fail(@"Cannot create disposable symlink.");rejected=NO;@try{AtomicWrite(link,old,next);}@catch(NSException *e){rejected=YES;}
        if(!rejected||![ReadText(path)isEqualToString:next])Fail(@"A symlink configuration was followed.");[fm removeItemAtPath:link error:NULL];[checks addObject:@"Symlink configuration rejected"];
        if(linkat(AT_FDCWD,[path fileSystemRepresentation],AT_FDCWD,[link fileSystemRepresentation],0))Fail(@"Cannot create disposable hardlink.");rejected=NO;@try{AtomicWrite(path,old,next);}@catch(NSException *e){rejected=YES;}
        if(!rejected||![ReadText(path)isEqualToString:next])Fail(@"A hard-linked configuration was replaced.");[fm removeItemAtPath:link error:NULL];[checks addObject:@"Hard-linked configuration rejected"];
        NSString *fifo=[dir stringByAppendingPathComponent:@"password.fifo"];
        if(mkfifo([fifo fileSystemRepresentation],0600)||(pipe=open([fifo fileSystemRepresentation],O_RDWR|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC))<0)Fail(@"Cannot create disposable private FIFO.");
        const char secret[]="test-only-password\n";if(write(pipe,secret,sizeof secret-1)!=sizeof secret-1)Fail(@"Cannot fill disposable private FIFO.");
        NSDictionary *request=@{@"secretPipe":fifo,@"callerUID":@(getuid())};
        if(![Password(request)isEqualToString:@"test-only-password"])Fail(@"The private password FIFO did not round-trip.");[checks addObject:@"Private password FIFO round-trip"];
        if(chmod([fifo fileSystemRepresentation],0644))Fail(@"Cannot change disposable FIFO permissions.");rejected=NO;@try{Password(request);}@catch(NSException *e){rejected=YES;}
        if(!rejected)Fail(@"An insecure password FIFO was accepted.");[checks addObject:@"Insecure password FIFO rejected"];
        NSDictionary *selection=@{@"config":@"/fixture/selected/afp.conf",@"activeConfig":@"/fixture/service/afp.conf",@"serviceConfig":@"/fixture/service/afp.conf"};
        ValidateActiveConfig(selection[@"config"],selection,NO);rejected=NO;@try{ValidateActiveConfig(selection[@"config"],selection,YES);}@catch(NSException *e){rejected=YES;}
        if(!rejected)Fail(@"A running daemon's different config was accepted for editing.");[checks addObject:@"Explicit offline config allowed; running mismatch rejected"];
        rejected=NO;@try{ValidateServiceConfig(selection);}@catch(NSException *e){rejected=YES;}
        if(!rejected)Fail(@"A service restart accepted a different selected configuration.");
        ValidateServiceConfig(@{@"config":@"/fixture/service/afp.conf",@"serviceConfig":@"/fixture/service/afp.conf"});[checks addObject:@"Service configuration selection checked before restart"];
        NSString *pamPath=[dir stringByAppendingPathComponent:@"pam-tests"];if(![fm createDirectoryAtPath:pamPath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700}error:NULL])Fail(@"Cannot create disposable PAM fixture.");
        int pamDir=open([pamPath fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if(pamDir<0)Fail(@"Cannot open disposable PAM fixture.");
        @try {
            NSData *policy=[@"#%PAM-1.0\nauth required pam_opendirectory.so\naccount required pam_opendirectory.so\npassword required pam_permit.so\nsession required pam_permit.so\n"dataUsingEncoding:NSUTF8StringEncoding];
            if(!SupportedPAM([[NSString alloc]initWithData:policy encoding:NSUTF8StringEncoding])||SupportedPAM(@"auth sufficient pam_permit.so\n"))Fail(@"Unexpected PAM policy was accepted.");[checks addObject:@"Only the supported OpenDirectory PAM policy accepted"];
            if(!InstallMissingPAM(pamDir,policy,getuid())||InstallMissingPAM(pamDir,policy,getuid()))Fail(@"PAM setup was not create-only and idempotent.");[checks addObject:@"Missing PAM policy created once with safe permissions"];
            rejected=NO;@try{InstallMissingPAM(pamDir,[@"different custom policy"dataUsingEncoding:NSUTF8StringEncoding],getuid());}@catch(NSException *e){rejected=YES;}
            if(!rejected||![[NSData dataWithContentsOfFile:[pamPath stringByAppendingPathComponent:@"netatalk"]]isEqualToData:policy])Fail(@"A differing PAM policy was overwritten.");[checks addObject:@"Existing custom PAM policy protected"];
        } @finally {close(pamDir);}
        return @{@"ok":@YES,@"count":@([checks count]),@"checks":checks};
    } @catch(NSException *e) {return @{@"ok":@NO,@"count":@([checks count]),@"checks":checks,@"error":[e reason]?:@"Unknown error"};}
    @finally {if(pipe>=0)close(pipe);[fm removeItemAtPath:dir error:NULL];}
}
