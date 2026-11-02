#import "Core.h"
NSString *S(id x){return [x isKindOfClass:[NSString class]]?x:(x?[x description]:@"");}
NSString *Trim(NSString *s){return [S(s) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];}
NSArray *Lines(NSString *s){return [S(s) componentsSeparatedByString:@"\n"];}
NSArray *Match(NSString *p,NSString *s){
    NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:p options:0 error:NULL];
    NSTextCheckingResult *m=[r firstMatchInString:S(s) options:0 range:NSMakeRange(0,[S(s) length])];
    if(!m)return nil;NSMutableArray *a=[NSMutableArray array];
    for(NSUInteger i=0;i<[m numberOfRanges];i++){NSRange z=[m rangeAtIndex:i];[a addObject:z.location==NSNotFound?@"":[s substringWithRange:z]];}return a;
}
void Fail(NSString *s){@throw [NSException exceptionWithName:@"AFPServerError" reason:s userInfo:nil];}
NSString *Stamp(void){NSDateFormatter *f=[NSDateFormatter new];[f setDateFormat:@"yyyy-MM-dd HH:mm:ss"];return [f stringFromDate:[NSDate date]];}
NSString *Tool(NSString *name){
    NSFileManager *fm=[NSFileManager defaultManager];if([name hasPrefix:@"/"])return [fm isExecutableFileAtPath:name]?name:nil;
    for(NSString *p in @[@"/opt/homebrew/bin",@"/opt/homebrew/sbin",@"/usr/local/bin",@"/usr/local/sbin",@"/opt/local/bin",@"/opt/local/sbin",@"/usr/bin",@"/usr/sbin",@"/bin",@"/sbin"]){NSString *q=[p stringByAppendingPathComponent:name];if([fm isExecutableFileAtPath:q])return q;}return nil;
}
NSString *ReadText(NSString *path){NSError *e=nil;NSString *s=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];if(!s)Fail([NSString stringWithFormat:@"Cannot read %@: %@",path,[e localizedDescription]]);return s;}
NSDictionary *Run(NSString *name,NSArray *args,NSTimeInterval timeout,NSData *input){
    NSString *exe=Tool(name);if(!exe)return @{@"ok":@NO,@"code":@127,@"out":[NSString stringWithFormat:@"Tool not found: %@",S(name)]};
    NSFileManager *fm=[NSFileManager defaultManager];NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"afp-task-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    NSError *error=nil;if(![fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])return @{@"ok":@NO,@"code":@126,@"out":S([error localizedDescription])};
    NSString *path=[dir stringByAppendingPathComponent:@"output"];
    if (![fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}]) {
        [fm removeItemAtPath:dir error:NULL];
        return @{@"ok":@NO,@"code":@126,@"out":@"Cannot create the private task-output file."};
    }
    NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [fm removeItemAtPath:dir error:NULL]; return @{@"ok":@NO,@"code":@126,@"out":@"Cannot open the private task-output file."}; }
    NSTask *task=[NSTask new];
    [task setExecutableURL:[NSURL fileURLWithPath:exe]];[task setArguments:args?:[NSArray array]];
    NSMutableDictionary *env=[NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
    env[@"PATH"]=@"/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";
    env[@"LC_ALL"]=@"C";env[@"HOMEBREW_NO_AUTO_UPDATE"]=@"1";env[@"HOMEBREW_NO_ENV_HINTS"]=@"1";env[@"HOMEBREW_NO_INSTALL_CLEANUP"]=@"1";
    for(NSString *key in [[env allKeys] copy])if([key hasPrefix:@"DYLD_"]||[key isEqualToString:@"BASH_ENV"]||[key isEqualToString:@"ENV"])[env removeObjectForKey:key];
    [task setEnvironment:env];[task setStandardOutput:fh];[task setStandardError:fh];
    NSPipe *pipe=nil;if(input){pipe=[NSPipe pipe];[task setStandardInput:pipe];}else [task setStandardInput:[NSFileHandle fileHandleForReadingAtPath:@"/dev/null"]];
    BOOL launched=[task launchAndReturnError:&error];BOOL timed=NO;int code=126;
    if(launched){
        if(pipe){@try{[[pipe fileHandleForWriting] writeData:input];[[pipe fileHandleForWriting] closeFile];}@catch(NSException *e){}}
        NSDate *until=[NSDate dateWithTimeIntervalSinceNow:timeout];
        while([task isRunning] && [until timeIntervalSinceNow]>0)[NSThread sleepForTimeInterval:0.05];
        if([task isRunning]){timed=YES;[task terminate];[NSThread sleepForTimeInterval:0.2];if([task isRunning])kill([task processIdentifier],SIGKILL);}
        [task waitUntilExit];code=timed?124:[task terminationStatus];
    }
    [fh closeFile];NSFileHandle *readHandle=[NSFileHandle fileHandleForReadingAtPath:path];unsigned long long length=[readHandle seekToEndOfFile];
    [readHandle seekToFileOffset:length>4*1024*1024?length-4*1024*1024:0];NSData *data=[readHandle readDataToEndOfFile];[readHandle closeFile];
    NSString *out=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(!out)out=[[NSString alloc]initWithData:data encoding:NSISOLatin1StringEncoding];
    [fm removeItemAtPath:dir error:NULL];
    if(!launched)out=S([error localizedDescription]);if(timed)out=[S(out) stringByAppendingString:@"\nCommand timed out."];
    return @{@"ok":@(code==0),@"code":@(code),@"out":S(out),@"timedOut":@(timed)};
}
NSString *Checked(NSString *exe,NSArray *args,NSTimeInterval t){NSDictionary *r=Run(exe,args,t,nil);if(![r[@"ok"] boolValue])Fail([NSString stringWithFormat:@"%@ failed (exit %@).\n%@",exe,r[@"code"],r[@"out"]]);return r[@"out"];}
NSString *Quote(NSString *s){return [NSString stringWithFormat:@"'%@'",[s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];}
NSString *SupportDir(void){NSString *p=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/AFPServer"];[[NSFileManager defaultManager]createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];return p;}
NSDictionary *JSONFile(NSString *p){NSData *d=[NSData dataWithContentsOfFile:p];if(!d)return nil;id v=[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:NULL];return [v isKindOfClass:[NSDictionary class]]?v:nil;}
NSString *JSON(id o){NSData *d=[NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];return [[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"{}";}
BOOL SaveJSON(id o,NSString *p){NSData *d=[NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];BOOL ok=[d writeToFile:p atomically:YES];if(ok)chmod([p fileSystemRepresentation],0600);return ok;}
NSMutableDictionary *Prefs(void) {
    NSDictionary *raw = JSONFile([SupportDir() stringByAppendingPathComponent:@"preferences.json"]);
    NSMutableDictionary *p = raw ? [raw mutableCopy] : [NSMutableDictionary dictionary];
    for (NSString *key in @[@"configPath", @"selectedSection", @"maintenanceIdentity"]) {
        if (p[key] && ![p[key] isKindOfClass:[NSString class]]) [p removeObjectForKey:key];
    }
    if (p[@"automaticImport"] && ![p[@"automaticImport"] isKindOfClass:[NSNumber class]]) {
        p[@"automaticImport"] = @NO; // Never enable maintenance from malformed preferences.
    }
    return p;
}
void SavePrefs(NSDictionary *p){if(!SaveJSON(p,[SupportDir() stringByAppendingPathComponent:@"preferences.json"]))Fail(@"Could not save app preferences.");}
void Log(NSString *s) {
    // A logging failure is not a reason to crash or prevent server status display.
    @try {
        @synchronized([AFPConfig class]) {
            NSString *p=[SupportDir() stringByAppendingPathComponent:@"activity.log"];
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *a=[fm attributesOfItemAtPath:p error:NULL];
            if ([a[NSFileSize] unsignedLongLongValue]>2000000) {
                NSString *old=[p stringByAppendingString:@".previous"];
                [fm removeItemAtPath:old error:NULL]; [fm moveItemAtPath:p toPath:old error:NULL];
            }
            if (![fm fileExistsAtPath:p]) [fm createFileAtPath:p contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:p];
            if (!f) { AFPStartupLog(@"Activity log is not writable. Check this app’s support-folder permissions."); return; }
            @try {
                [f seekToEndOfFile];
                [f writeData:[[NSString stringWithFormat:@"%@  %@\n",Stamp(),S(s)] dataUsingEncoding:NSUTF8StringEncoding]];
            } @finally { [f closeFile]; }
        }
    } @catch(NSException *e) { AFPRecordException(e); }
}
NSString *LogTail(void) {
    @try {
        NSString *p=[SupportDir() stringByAppendingPathComponent:@"activity.log"];
        NSFileHandle *h=[NSFileHandle fileHandleForReadingAtPath:p];
        if(!h) return @"No readable activity log yet. This does not prevent the app from showing server status.";
        @try {
            uint64_t len=[h seekToEndOfFile]; [h seekToFileOffset:len>120000?len-120000:0];
            NSData *d=[h readDataToEndOfFile];
            return [[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"Log is not UTF-8 text.";
        } @finally { [h closeFile]; }
    } @catch(NSException *e) { AFPRecordException(e); return @"Cannot read the old activity log. Check this app’s support-folder permissions."; }
}
BOOL IsDir(NSString *p){BOOL dir=NO;return [[NSFileManager defaultManager]fileExistsAtPath:p isDirectory:&dir]&&dir;}
NSString *SafeRoot(NSString *p){
    p=[[p stringByExpandingTildeInPath] stringByStandardizingPath];
    if(![p hasPrefix:@"/"]||[p containsString:@"$"]||[p rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound)Fail(@"The share must be an existing absolute directory, not a dynamic path.");
    if(!IsDir(p))Fail([@"Share directory not available: " stringByAppendingString:p]);
    NSString *real=[p stringByResolvingSymlinksInPath];
    if([@[@"/",@"/Users",@"/System",@"/Library",@"/private",@"/var",@"/usr",@"/opt",@"/Volumes",NSHomeDirectory()] containsObject:real])Fail(@"Choose a dedicated share folder, not a system folder or an entire home directory.");
    return real;
}
@implementation AFPConfig
- (instancetype)initWithText:(NSString *)t{if((self=[super init])){_original=t;_newline=[t containsString:@"\r\n"]?@"\r\n":@"\n";_lines=[[[t stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]componentsSeparatedByString:@"\n"] mutableCopy];}return self;}
- (NSArray *)sections{
    NSMutableArray *ss=[NSMutableArray array];NSMutableDictionary *cur=nil;NSMutableSet *names=[NSMutableSet set];
    for(NSUInteger i=0;i<[_lines count];i++){
        NSString *line=Trim(_lines[i]);if(![line length]||[line hasPrefix:@"#"]||[line hasPrefix:@";"])continue;
        NSArray *m=Match(@"^\\[([^\\]\\r\\n]+)\\]\\s*(?:[#;].*)?$",line);
        if(m){NSString *name=Trim(m[1]);NSString *key=[name lowercaseString];if([names containsObject:key])Fail([@"Duplicate configuration section: "stringByAppendingString:name]);[names addObject:key];if(cur)cur[@"end"]=@(i);cur=[@{@"name":name,@"start":@(i),@"end":@([_lines count]),@"options":[NSMutableDictionary dictionary]}mutableCopy];[ss addObject:cur];continue;}
        if(!cur)continue;NSRange eq=[line rangeOfString:@"="];if(eq.location==NSNotFound)continue;
        NSString *key=Trim([line substringToIndex:eq.location]);NSMutableString *val=[Trim([line substringFromIndex:eq.location+1]) mutableCopy];
        while([val hasSuffix:@"\\"] && i+1<[_lines count]){[val setString:[[val substringToIndex:[val length]-1]stringByAppendingString:Trim(_lines[++i])]];}
        ((NSMutableDictionary *)cur[@"options"])[key]=val;
    }return ss;
}
- (NSDictionary *)section:(NSString *)n{for(NSDictionary *s in [self sections])if([[S(s[@"name"])lowercaseString]isEqualToString:[n lowercaseString]])return s;return nil;}
- (NSDictionary *)global{return [self section:@"Global"][@"options"]?:[NSDictionary dictionary];}
- (NSArray *)shares{NSMutableArray *a=[NSMutableArray array];for(NSDictionary *s in [self sections]){NSString *n=s[@"name"];NSDictionary *o=s[@"options"];if([[n lowercaseString]isEqualToString:@"global"]||[[n lowercaseString]isEqualToString:@"homes"]||![S(o[@"path"]) length])continue;[a addObject:@{@"section":n,@"name":o[@"volume name"]?:[n lowercaseString],@"path":o[@"path"],@"options":o}];}return a;}
- (void)patchSection:(NSString *)n options:(NSDictionary *)o create:(BOOL)create{
    if(![n length]||Match(@"[\\[\\]\\r\\n]",n))Fail(@"Invalid section name.");NSDictionary *sec=[self section:n];if(!sec){if(!create)Fail(@"The selected section no longer exists.");[_lines addObject:[NSString stringWithFormat:@"[%@]",n]];[_lines addObject:@""];}
    for(NSString *key in [[o allKeys]sortedArrayUsingSelector:@selector(compare:)]){
        NSString *v=S(o[key]);if(Match(@"[\\r\\n]",v))Fail(@"Configuration values cannot contain a newline.");sec=[self section:n];NSUInteger lo=[sec[@"start"]unsignedIntegerValue]+1,hi=[sec[@"end"]unsignedIntegerValue];BOOL found=NO;
        for(NSUInteger i=lo;i<hi;i++){NSString *ln=Trim(_lines[i]);if([ln hasPrefix:@"#"]||[ln hasPrefix:@";"])continue;NSRange eq=[ln rangeOfString:@"="];if(eq.location==NSNotFound)continue;if(![Trim([ln substringToIndex:eq.location])isEqualToString:key])continue;
            NSUInteger end=i;while([Trim(_lines[end])hasSuffix:@"\\"]&&end+1<hi)end++;
            if(end>i){[_lines removeObjectsInRange:NSMakeRange(i+1,end-i)];hi-=end-i;}
            if(!found){_lines[i]=[NSString stringWithFormat:@"    %@ = %@",key,v];found=YES;}else{[_lines removeObjectAtIndex:i];i--;hi--;}
        }
        if(!found){sec=[self section:n];NSUInteger pos=[sec[@"end"]unsignedIntegerValue];while(pos>lo && ![Trim(_lines[pos-1])length])pos--;[_lines insertObject:[NSString stringWithFormat:@"    %@ = %@",key,v]atIndex:pos];}
    }
}
- (void)removeSection:(NSString *)n{NSDictionary *s=[self section:n];if(!s)Fail(@"Section no longer exists.");if([@[@"global",@"homes"]containsObject:[n lowercaseString]])Fail(@"Special sections cannot be removed here.");NSUInteger lo=[s[@"start"]unsignedIntegerValue],hi=[s[@"end"]unsignedIntegerValue];[_lines removeObjectsInRange:NSMakeRange(lo,hi-lo)];}
- (NSString *)text{NSString *t=[_lines componentsJoinedByString:_newline];return [t hasSuffix:_newline]?t:[t stringByAppendingString:_newline];}
- (void)validate{NSArray *ss=[self shares];NSMutableArray *paths=[NSMutableArray array];for(NSDictionary *s in ss){NSString *p=s[@"path"];if([p containsString:@"$"])continue;if(![p hasPrefix:@"/"])Fail([@"Relative share path: "stringByAppendingString:p]);NSString *rp=[[p stringByStandardizingPath]stringByResolvingSymlinksInPath];for(NSString *prior in paths){if(ad_path_contains([prior UTF8String],[rp UTF8String])||ad_path_contains([rp UTF8String],[prior UTF8String]))Fail(@"Overlapping or nested shares detected. Nothing was written.");}[paths addObject:rp];}NSString *port=[self global][@"afp port"];if([port length]&&(!Match(@"^[0-9]{1,5}$",port)||[port integerValue]<1||[port integerValue]>65535))Fail(@"AFP port must be between 1 and 65535.");}
@end
NSString *BundleRoot(void){NSString *p=[[NSBundle mainBundle]bundlePath];if([p hasSuffix:@".app"])return p;NSString *exe=[[[NSProcessInfo processInfo]arguments] firstObject];NSString *q=[exe stringByResolvingSymlinksInPath];NSRange r=[q rangeOfString:@".app/"];if(r.location!=NSNotFound)return [q substringToIndex:r.location+4];return p;}
NSString *HelperPath(void){return [BundleRoot()stringByAppendingPathComponent:@"Contents/Helpers/AFPServerHelper"];}
static NSString *ExistingConfig(NSArray *candidates) {
    for (NSString *candidate in candidates) {
        BOOL directory=NO;
        if ([[NSFileManager defaultManager]fileExistsAtPath:candidate isDirectory:&directory]&&!directory)
            return [candidate stringByResolvingSymlinksInPath];
    }
    return @"";
}
NSDictionary *Installation(NSString *override) {
    NSMutableDictionary *info=[NSMutableDictionary dictionary];
    NSString *binary=Tool(@"netatalk")?:Tool(@"afpd");
    NSString *details=binary?S(Run(binary,@[@"-V"],4,nil)[@"out"]):@"Netatalk was not found in the standard executable locations.";
    info[@"version"]=binary?Trim([Lines(details)firstObject]):@"Netatalk not found";info[@"details"]=details;info[@"binary"]=binary?:@"";
    info[@"controller"]=Tool(@"netatalkd")?:@"";
    NSString *resolved=[binary stringByResolvingSymlinksInPath];
    BOOL homebrew=[resolved hasPrefix:@"/opt/homebrew/Cellar/netatalk/"]||[resolved hasPrefix:@"/usr/local/Cellar/netatalk/"];
    info[@"brew"]=homebrew?(Tool(@"brew")?:@""):@"";
    NSMutableArray *compiled=[NSMutableArray array],*serviceCandidates=[NSMutableArray array];
    for (NSString *line in Lines(details)) {
        NSArray *match=Match(@"(/[^\\r\\n]*?afp\\.conf)",line);
        if(match)[compiled addObject:Trim(match[1])];
    }
    NSString *compiledConfig=ExistingConfig(compiled),*liveConfig=@"",*activeSource=@"";
    BOOL masterFound=NO;
    for (NSString *process in @[@"netatalk",@"afpd"]) {
        NSDictionary *probe=Run(@"/usr/bin/pgrep",@[@"-x",process],3,nil);
        if(![probe[@"ok"]boolValue])continue;
        if([process isEqualToString:@"netatalk"])masterFound=YES;
        for (NSString *pid in Lines(Trim(probe[@"out"]))) {
            if(!Match(@"^[0-9]+$",pid))continue;
            NSDictionary *command=Run(@"/bin/ps",@[@"-ww",@"-p",pid,@"-o",@"command="],3,nil);
            if(![command[@"ok"]boolValue])continue;
            NSArray *match=Match(@"(?:^|\\s)-F\\s+(?:\"([^\"]+)\"|'([^']+)'|(\\S+))",command[@"out"]);
            if(match)for(NSUInteger n=1;n<[match count];n++)if([match[n]length]) {
                NSString *candidate=ExistingConfig(@[match[n]]);
                if([candidate length]) { liveConfig=candidate;activeSource=@"Live daemon -F argument"; }
                break;
            }
            if([liveConfig length])break;
        }
        if([liveConfig length])break;
    }
    if(![liveConfig length]&&masterFound&&[compiledConfig length]) { liveConfig=compiledConfig;activeSource=@"Running Netatalk master and compiled configuration path"; }
    for (NSString *path in @[@"/Library/LaunchDaemons/homebrew.mxcl.netatalk.plist",@"/Library/LaunchDaemons/io.netatalk.daemon.plist"]) {
        NSDictionary *plist=[NSDictionary dictionaryWithContentsOfFile:path];if(!plist)continue;
        NSString *label=S(plist[@"Label"]);
        if([label length]&&![S(info[@"label"])length]) { info[@"label"]=label;info[@"plist"]=path; }
        NSArray *arguments=plist[@"ProgramArguments"];
        if(![arguments isKindOfClass:[NSArray class]])continue;
        NSUInteger index=[arguments indexOfObject:@"-F"];
        if(index!=NSNotFound&&index+1<[arguments count]&&[arguments[index+1]isKindOfClass:[NSString class]])[serviceCandidates addObject:arguments[index+1]];
    }
    NSString *serviceConfig=ExistingConfig(serviceCandidates),*serviceSource=@"LaunchDaemon -F argument";
    if(![serviceConfig length]) { serviceConfig=compiledConfig;serviceSource=@"Compiled configuration path"; }
    NSArray *fallback=@[@"/opt/homebrew/etc/netatalk/afp.conf",@"/opt/homebrew/etc/afp.conf",@"/usr/local/etc/netatalk/afp.conf",@"/usr/local/etc/afp.conf",@"/opt/local/etc/netatalk/afp.conf",@"/etc/netatalk/afp.conf"];
    NSString *defaultConfig=ExistingConfig(fallback);
    if(![serviceConfig length])serviceSource=@"Service configuration could not be verified";
    info[@"compiledConfig"]=compiledConfig;
    info[@"activeConfig"]=liveConfig;info[@"activeConfigSource"]=activeSource;
    info[@"serviceConfig"]=serviceConfig;info[@"serviceConfigSource"]=serviceSource;
    info[@"config"]=[override length]?ExistingConfig(@[override]):([liveConfig length]?liveConfig:([serviceConfig length]?serviceConfig:defaultConfig));
    NSString *label=S(info[@"label"]);BOOL boot=[label length]>0,bootKnown=YES;
    if(boot) {
        NSDictionary *disabled=Run(@"/bin/launchctl",@[@"print-disabled",@"system"],3,nil);
        bootKnown=[disabled[@"ok"]boolValue];
        if([S(disabled[@"out"])containsString:[NSString stringWithFormat:@"\"%@\" => true",label]])boot=NO;
    }
    info[@"boot"]=@(boot);info[@"bootStatusKnown"]=@(bootKnown);return info;
}
static NSDictionary *ProcessProbe(NSString *process) {
    NSDictionary *result=Run(@"/usr/bin/pgrep",@[@"-x",process],3,nil);
    NSInteger code=[result[@"code"] integerValue];
    return @{@"known":@(code==0||code==1),@"running":@(code==0),@"details":S(result[@"out"])};
}
BOOL Running(NSString *proc) {
    NSDictionary *probe=ProcessProbe(proc);
    if (![probe[@"known"] boolValue]) Fail([NSString stringWithFormat:@"Cannot verify the %@ process state. No server or maintenance change was made.\n%@",proc,probe[@"details"]]);
    return [probe[@"running"] boolValue];
}
static void SocketFlush(NSMutableArray *rows,NSDictionary *p,NSMutableDictionary *f){if([S(f[@"endpoint"])length]){NSMutableDictionary *r=[p mutableCopy];[r addEntriesFromDictionary:f];NSString *e=r[@"endpoint"];NSArray *s=[e componentsSeparatedByString:@"->"];r[@"local"]=s[0];r[@"remote"]=[s count]>1?s[1]:@"";[rows addObject:r];}}
NSArray *SocketRows(NSString *raw){NSMutableArray *rows=[NSMutableArray array];NSMutableDictionary *p=[NSMutableDictionary dictionary],*f=[NSMutableDictionary dictionary];for(NSString *line in Lines(raw)){if(![line length])continue;unichar k=[line characterAtIndex:0];NSString *v=[line substringFromIndex:1];if(k=='p'){SocketFlush(rows,p,f);p=[@{@"pid":v}mutableCopy];f=[NSMutableDictionary dictionary];}else if(k=='c')p[@"process"]=v;else if(k=='u')p[@"uid"]=v;else if(k=='f'){SocketFlush(rows,p,f);f=[@{@"fd":v}mutableCopy];}else if(k=='n')f[@"endpoint"]=v;else if(k=='T'&&[v hasPrefix:@"ST="])f[@"state"]=[v substringFromIndex:3];}SocketFlush(rows,p,f);return rows;}
NSArray *SessionRows(NSString *raw){NSMutableArray *a=[NSMutableArray array];for(NSString *line in Lines(raw)){NSArray *m=Match(@"^\\s*(\\S+)\\s+(\\d+)\\s+(.+?)\\s+(active|sleeping|idle|disconnected)\\s+(?:(TCP/IP|AppleTalk)\\s+)?(\\S+)(?:\\s+(.*))?$",line);if(m)[a addObject:@{@"user":m[1],@"pid":m[2],@"login":m[3],@"state":m[4],@"protocol":[m[5]length]?m[5]:@"TCP/IP",@"client":m[6],@"volumes":m[7]}];}return a;}
NSDictionary *Snapshot(NSString *config){
    NSDictionary *i=Installation(config);NSMutableDictionary *s=[NSMutableDictionary dictionaryWithDictionary:i];NSMutableArray *warnings=[NSMutableArray array];
    s[@"timestamp"]=Stamp();s[@"privileged"]=@(geteuid()==0);
    NSDictionary *process=ProcessProbe(@"afpd");BOOL known=[process[@"known"] boolValue],running=[process[@"running"] boolValue];
    s[@"processStatusKnown"]=@(known);s[@"running"]=@(running);
    if(![S(i[@"binary"]) length]) [warnings addObject:@"No Netatalk executable was found in the supported locations. The existing configuration can be inspected; server operations require a working Netatalk installation."];
    if (!known) [warnings addObject:@"Process status is unavailable. A failed process inspection does not mean the server is stopped."];
    NSString *cfg=i[@"config"];if([cfg length]){@try{AFPConfig *conf=[[AFPConfig alloc]initWithText:ReadText(cfg)];s[@"shares"]=[conf shares];s[@"global"]=[conf global];}@catch(NSException *e){[warnings addObject:[e reason]];}}else [warnings addObject:@"afp.conf was not found. Select the existing file in Settings."];
    NSDictionary *lr=Run(@"/usr/sbin/lsof",@[@"-nP",@"-a",@"-c",@"afpd",@"-iTCP",@"-FpcufnT"],5,nil);NSArray *sockets=SocketRows(lr[@"out"]);s[@"sockets"]=sockets;BOOL listening=NO;for(NSDictionary *r in sockets)if([r[@"state"]isEqualToString:@"LISTEN"])listening=YES;s[@"listening"]=@(listening);
    if(running&&!listening)[warnings addObject:@"afpd exists, but no listener is visible. Request an administrator snapshot to distinguish permissions from a server fault."];
    NSString *ifc=S(Run(@"/sbin/ifconfig",[NSArray array],4,nil)[@"out"]);NSMutableArray *ips=[NSMutableArray array];NSString *iface=@"";
    for(NSString *line in Lines(ifc)){NSArray *m=Match(@"^([^ \\t:]+):",line);if(m)iface=m[1];m=Match(@"\\binet (\\d+\\.\\d+\\.\\d+\\.\\d+)",line);if(m&&![m[1]hasPrefix:@"127."])[ips addObject:@{@"interface":iface,@"address":m[1]}];}s[@"addresses"]=ips;
    s[@"sessionsReadable"]=@NO;s[@"sessions"]=[NSArray array];s[@"sessionRaw"]=known?@"Server is stopped.":@"Server process status is unavailable.";
    if(running&&Tool(@"afpstats")){NSDictionary *r=Run(@"afpstats",[NSArray array],5,nil);NSArray *sessions=SessionRows(r[@"out"]);BOOL formatKnown=NO;NSUInteger dataLines=0;
        for(NSString *line in Lines(r[@"out"])) {
            NSString *value=Trim(line);if(![value length])continue;
            if(Match(@"^Connected user\\s+PID\\s+Login time\\s+State\\s+(?:Protocol\\s+)?Client address\\s+Mounted volumes$",value))formatKnown=YES;
            else dataLines++;
        }
        BOOL readable=[r[@"ok"] boolValue]&&formatKnown&&dataLines==[sessions count];
        s[@"sessionsReadable"]=@(readable);s[@"sessions"]=sessions;s[@"sessionRaw"]=r[@"out"];if(!readable)[warnings addObject:@"Session access unavailable. Enable afpstats and its group permissions in Settings, or request an administrator snapshot."];}
    else if(running){s[@"sessionRaw"]=@"afpstats is not installed. Process UIDs are not authenticated AFP usernames.";[warnings addObject:s[@"sessionRaw"]];}
    s[@"warnings"]=warnings;return s;
}
NSArray *Accounts(void){NSMutableArray *a=[NSMutableArray array];NSString *raw=Checked(@"/usr/bin/dscl",@[@".",@"-list",@"/Users",@"UniqueID"],5);for(NSString *l in Lines(raw)){NSArray *m=Match(@"^(\\S+)\\s+(\\d+)\\s*$",l);if(!m)continue;NSInteger uid=[m[2]integerValue];if(uid<500||uid>=65534)continue;NSString *name=m[1];NSString *record=S(Run(@"/usr/bin/dscl",@[@".",@"-read",[@"/Users/"stringByAppendingString:name],@"RealName",@"Comment"],3,nil)[@"out"]);NSArray *full=Match(@"RealName:\\s*([^\\r\\n]+)",record);[a addObject:@{@"name":name,@"uid":m[2],@"display":full?Trim(full[1]):name,@"managed":@([record containsString:@"AFPServerManaged:v1"])}];}return a;}

// Regression guard for the invalid NSObject ABI declaration in release 1.1.
// This project imports Apple's real SDK; no replacement NSObject is declared.
void AFPAssertObjectLayout(void) {
    Class cls=[AFPConfig class];
    size_t minimum=class_getInstanceSize(class_getSuperclass(cls));
    size_t size=class_getInstanceSize(cls);
    const char *names[]={"_original","_lines","_newline"};
    ptrdiff_t previous=-1;
    for (unsigned int i=0;i<3;i++) {
        Ivar ivar=class_getInstanceVariable(cls,names[i]);
        if (!ivar) Fail(@"AFPConfig is missing an expected instance variable.");
        ptrdiff_t offset=ivar_getOffset(ivar);
        if (offset<0 || (size_t)offset<minimum || (size_t)offset+sizeof(id)>size ||
            (previous>=0 && offset<previous+(ptrdiff_t)sizeof(id)))
            Fail(@"AFPConfig object layout is invalid. Rebuild with Apple's macOS SDK.");
        previous=offset;
    }
}
