#import "Core.h"
#include <dirent.h>
#include <time.h>

static const off_t MetadataLimit = 256 * 1024 * 1024;
static NSDictionary *SelectedShare(NSDictionary *prefs) {
    NSDictionary *i=Installation(S(prefs[@"configPath"]));
    NSString *path=S(i[@"config"]); if(![path length]) Fail(@"No active afp.conf was found.");
    AFPConfig *cfg=[[AFPConfig alloc]initWithText:ReadText(path)];
    NSArray *shares=[cfg shares]; NSString *selected=S(prefs[@"selectedSection"]); NSDictionary *found=nil;
    if([selected length]) {
        for(NSDictionary *s in shares) if([S(s[@"section"]) caseInsensitiveCompare:selected]==NSOrderedSame) { found=s; break; }
    } else found=[shares firstObject];
    if(!found) Fail(@"The selected share no longer exists. Select a share again; no substitute was used.");
    NSMutableDictionary *s=[found mutableCopy]; s[@"root"]=SafeRoot(found[@"path"]); s[@"config"]=path; return s;
}
static BOOL SameObject(const struct stat *a,const struct stat *b) {
    return a->st_dev==b->st_dev && a->st_ino==b->st_ino && (a->st_mode&S_IFMT)==(b->st_mode&S_IFMT);
}
static BOOL StableObject(const struct stat *a,const struct stat *b) {
    return SameObject(a,b) && a->st_size==b->st_size && a->st_nlink==b->st_nlink &&
        a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec &&
        a->st_ctimespec.tv_sec==b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec==b->st_ctimespec.tv_nsec;
}
static NSString *RootIdentity(NSString *root,const struct stat *st) {
    return [NSString stringWithFormat:@"%@:%llu:%llu",root,(unsigned long long)st->st_dev,(unsigned long long)st->st_ino];
}
// Every component is opened without following symlinks. The descriptor remains tied
// to the inspected inode even if a name is replaced between inspection and write.
static int OpenRelative(int rootFD,NSString *relative,dev_t device) {
    if([relative hasPrefix:@"/"]) { errno=EINVAL; return -1; }
    int current=dup(rootFD); if(current<0) return -1;
    if(![relative length] || [relative isEqualToString:@"."]) return current;
    NSArray *parts=[relative componentsSeparatedByString:@"/"];
    for(NSUInteger i=0;i<[parts count];i++) {
        NSString *part=parts[i];
        if(![part length] || [part isEqualToString:@"."] || [part isEqualToString:@".."]) { close(current); errno=EINVAL; return -1; }
        int flags=O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK;
        if(i+1<[parts count]) flags|=O_DIRECTORY;
        int next=openat(current,[part fileSystemRepresentation],flags); int saved=errno; close(current);
        if(next<0) { errno=saved; return -1; }
        struct stat st;
        if(fstat(next,&st)!=0 || st.st_dev!=device || (!S_ISREG(st.st_mode)&&!S_ISDIR(st.st_mode))) {
            close(next); errno=EXDEV; return -1;
        }
        current=next;
    }
    return current;
}
static int OpenAbsolute(NSString *path,BOOL directory) {
    if(![path hasPrefix:@"/"]) { errno=EINVAL; return -1; }
    // Foundation intentionally shortens /private/var back to /var. POSIX
    // realpath gives the physical components needed for nofollow traversal.
    char *resolved=realpath([path fileSystemRepresentation],NULL);if(!resolved)return -1;
    path=[[NSFileManager defaultManager]stringWithFileSystemRepresentation:resolved length:strlen(resolved)];free(resolved);
    if(!path) { errno=EINVAL;return -1; }
    int current=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC); if(current<0)return -1;
    NSArray *parts=[path pathComponents];
    for(NSUInteger i=1;i<[parts count];i++) {
        NSString *part=parts[i];
        if(![part length]||[part isEqualToString:@"."]||[part isEqualToString:@".."]) { close(current);errno=EINVAL;return -1; }
        int flags=O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK;
        if(directory||i+1<[parts count]) flags|=O_DIRECTORY;
        int next=openat(current,[part fileSystemRepresentation],flags);int saved=errno;close(current);
        if(next<0) { errno=saved;return -1; }current=next;
    }
    return current;
}
static BOOL StillNamed(int rootFD,NSString *root,const struct stat *rootStat,NSString *relative,int fd,const struct stat *expected,BOOL stable) {
    struct stat namedRoot,current,named;
    if(lstat([root fileSystemRepresentation],&namedRoot)!=0 || !SameObject(rootStat,&namedRoot) ||
       fstat(fd,&current)!=0 || !(stable?StableObject(expected,&current):SameObject(expected,&current))) return NO;
    int check=OpenRelative(rootFD,relative,rootStat->st_dev); if(check<0) return NO;
    BOOL ok=fstat(check,&named)==0 && (stable?StableObject(expected,&named):SameObject(expected,&named)); close(check); return ok;
}
static NSData *FDXattr(int fd,NSString *name,BOOL *missing) {
    *missing=NO; const char *n=[name UTF8String]; ssize_t size=fgetxattr(fd,n,NULL,0,0,0);
    if(size<0) {
        if(errno==ENOATTR) { *missing=YES; return nil; }
        Fail([NSString stringWithFormat:@"Cannot read %@ (errno %d).",name,errno]);
    }
    if(size>MetadataLimit) Fail(@"Metadata exceeds the safe 256 MiB limit. Original data was left unchanged.");
    NSMutableData *d=[NSMutableData dataWithLength:(NSUInteger)size];
    // Also read a zero-length attribute again: a concurrent creator must not be
    // mistaken for a confirmed empty attribute.
    ssize_t got=fgetxattr(fd,n,[d mutableBytes],(size_t)size,0,0);
    if(got!=size) Fail(@"Metadata changed while it was being read.");
    return d;
}
static NSData *ReadSidecar(int fd,const struct stat *before) {
    if(before->st_size<0 || before->st_size>MetadataLimit) Fail(@"AppleDouble file exceeds 256 MiB; left untouched.");
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)before->st_size];
    size_t done=0; while(done<[data length]) {
        ssize_t got=pread(fd,(unsigned char *)[data mutableBytes]+done,[data length]-done,(off_t)done);
        if(got<0&&errno==EINTR) continue;
        if(got<=0) Fail(@"AppleDouble file changed or could not be read completely."); done+=(size_t)got;
    }
    struct stat after; if(fstat(fd,&after)!=0 || !StableObject(before,&after)) Fail(@"AppleDouble file changed while it was being read.");
    return data;
}
static void Count(NSMutableDictionary *d,NSString *k) { d[k]=@([d[k]unsignedIntegerValue]+1); }
static NSDictionary *BusySessions(void) {
    NSDictionary *process=Run(@"/usr/bin/pgrep",@[@"-x",@"afpd"],3,nil);
    // pgrep exit 1 with no output means no match. Errors are not a stopped server.
    if([process[@"code"]integerValue]==1 && ![Trim(process[@"out"])length]) return nil;
    if(![process[@"ok"]boolValue]) return @{@"reason":@"Paused: the AFP process status cannot be read. No metadata is changed while server activity is unknown."};
    if(!Tool(@"afpstats")) return @{@"reason":@"Paused: afpd is active and afpstats is unavailable. Stop Netatalk for maintenance, or enable readable session statistics."};
    NSDictionary *r=Run(@"afpstats",@[],5,nil);
    if(![r[@"ok"]boolValue]) return @{@"reason":@"Paused: session statistics are not readable. Enable afpstats group access, or stop Netatalk for maintenance."};
    NSString *raw=Trim(r[@"out"]);
    if([SessionRows(raw) count]) return @{@"reason":@"Paused while AFP users are connected. Metadata will be considered again when the server is idle."};
    BOOL explicitEmpty=NO;
    for(NSString *line in Lines(raw)) {
        NSString *s=Trim(line); if(![s length]) continue;
        if([s hasPrefix:@"No connected"]||[s hasPrefix:@"No users"]||[s hasPrefix:@"No sessions"]) { explicitEmpty=YES; continue; }
        // Official afpstats.pl always prints this complete header, including
        // when its row list is empty. A prefix alone is not sufficient.
        if(Match(@"^Connected user\\s+PID\\s+Login time\\s+State\\s+(?:Protocol\\s+)?Client address\\s+Mounted volumes$",s)) { explicitEmpty=YES; continue; }
        return @{@"reason":@"Paused: session output was not recognised. No zero-session assumption was made."};
    }
    if(!explicitEmpty) return @{@"reason":@"Paused: session statistics did not explicitly confirm that no clients are connected."};
    return nil;
}
static NSString *BackupSidecar(NSData *data,NSString *source,NSString *target,NSString **backupDir) {
    NSFileManager *fm=[NSFileManager defaultManager];
    if(![*backupDir length]) {
        *backupDir=[[SupportDir()stringByAppendingPathComponent:@"MetadataBackups"]stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]];
        if(![fm createDirectoryAtPath:*backupDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]) Fail(@"Could not create a metadata backup folder.");
    }
    NSString *backup=[*backupDir stringByAppendingPathComponent:[[[NSUUID UUID]UUIDString]stringByAppendingString:@".appledouble"]];
    if(![data writeToFile:backup options:NSDataWritingAtomic error:NULL] || chmod([backup fileSystemRepresentation],0600)!=0 ||
       ![[NSData dataWithContentsOfFile:backup]isEqualToData:data]) Fail(@"Metadata backup could not be written and verified. Nothing was imported for this file.");
    if(!SaveJSON(@{@"source":source,@"target":target,@"time":Stamp(),@"nativePolicy":@"Only absent attributes are added. Existing attributes are never replaced."},[backup stringByAppendingString:@".json"]))
        Fail(@"Metadata backup manifest could not be saved. Nothing was imported for this file.");
    return backup;
}
NSDictionary *MetadataRun(NSDictionary *prefs,BOOL repair,BOOL background) {
    NSDictionary *share=SelectedShare(prefs); NSString *root=share[@"root"];
    if(ad_path_contains([root UTF8String],[SupportDir()UTF8String])) Fail(@"The share contains the application's own settings/backups. Choose a dedicated data folder.");
    int rootFD=OpenAbsolute(root,YES);
    if(rootFD<0) Fail(@"The selected share cannot be opened safely.");
    int lock=-1;
    @try {
        struct stat rootStat; if(fstat(rootFD,&rootStat)!=0) Fail(@"The share identity cannot be read.");
        NSString *identity=RootIdentity(root,&rootStat);
        if(repair&&background) {
            if(![prefs[@"automaticImport"]boolValue]) return @{@"ok":@YES,@"message":@"Automatic metadata care is disabled."};
            if(![S(prefs[@"maintenanceIdentity"])isEqualToString:identity]) return @{@"ok":@NO,@"message":@"Paused: the configured share folder or disk changed. Re-enable automatic care for this folder."};
        }
        if(repair) { NSDictionary *busy=BusySessions(); if(busy) return @{@"ok":@NO,@"paused":@YES,@"message":busy[@"reason"],@"share":root,@"timestamp":Stamp()}; }
        NSString *lockPath=[SupportDir()stringByAppendingPathComponent:@"metadata.lock"];
        lock=open([lockPath fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
        if(lock<0||flock(lock,LOCK_EX|LOCK_NB)!=0) Fail(@"Another metadata operation is already running, or its lock cannot be opened.");
        NSMutableDictionary *counts=[NSMutableDictionary dictionary];
        for(NSString *k in @[@"files",@"directories",@"sidecars",@"finderInfo",@"resourceForks",@"netatalkMetadata",@"finderAdded",@"resourceAdded",@"conflicts",@"missingTargets",@"unstable",@"errors",@"symlinksSkipped",@"mountsSkipped"]) counts[k]=@0;
        NSMutableArray *messages=[NSMutableArray array]; NSString *backupDir=@""; BOOL paused=NO;
        // Descriptor-relative traversal never follows a directory replaced by a
        // symlink. A path enumerator alone cannot provide that guarantee.
        NSMutableArray *directories=[NSMutableArray arrayWithObject:@""];
        while([directories count]&&!paused) {
            NSString *directory=[directories lastObject]; [directories removeLastObject];
            int dfd=OpenRelative(rootFD,directory,rootStat.st_dev);
            if(dfd<0) { Count(counts,errno==EXDEV?@"mountsSkipped":@"errors"); continue; }
            DIR *dir=fdopendir(dfd); if(!dir) { close(dfd); Count(counts,@"errors"); continue; }
            @try {
                struct dirent *item;
                while(!paused) {
                    errno=0; item=readdir(dir);
                    if(!item) { if(errno) { Count(counts,@"errors"); [messages addObject:[@"Directory enumeration failed: "stringByAppendingString:directory]]; } break; }
                    @autoreleasepool {
                    if(!strcmp(item->d_name,".")||!strcmp(item->d_name,"..")) continue;
                    NSString *name=[[NSFileManager defaultManager]stringWithFileSystemRepresentation:item->d_name length:strlen(item->d_name)];
                    if(!name) { Count(counts,@"errors"); continue; }
                    NSString *rel=[directory length]?[directory stringByAppendingPathComponent:name]:name;
                    NSString *p=[root stringByAppendingPathComponent:rel]; struct stat a;
                    if(fstatat(dirfd(dir),item->d_name,&a,AT_SYMLINK_NOFOLLOW)!=0) { Count(counts,@"errors"); continue; }
                    if(S_ISLNK(a.st_mode)) { Count(counts,@"symlinksSkipped"); continue; }
                    if(a.st_dev!=rootStat.st_dev) { Count(counts,@"mountsSkipped"); continue; }
                    if(S_ISDIR(a.st_mode)) {
                        Count(counts,@"directories");
                        if(![@[@".AppleDB",@".Spotlight-V100",@".fseventsd",@".Trashes",@".TemporaryItems"]containsObject:name]) [directories addObject:rel];
                        continue;
                    }
                    if(!S_ISREG(a.st_mode)) continue;
                    BOOL dot=[name hasPrefix:@"._"],old=[[directory lastPathComponent]isEqualToString:@".AppleDouble"];
                    if(dot||old) Count(counts,@"sidecars"); else Count(counts,@"files");
                    int sourceFD=-1,targetFD=-1;
                    @try {
                        sourceFD=OpenRelative(rootFD,rel,rootStat.st_dev);
                        struct stat sourceStat;
                        if(sourceFD<0||fstat(sourceFD,&sourceStat)!=0||!StableObject(&a,&sourceStat)) { Count(counts,@"unstable"); continue; }
                        if(!dot&&!old) {
                            if(!background) {
                                BOOL absent; NSData *fi=FDXattr(sourceFD,@"com.apple.FinderInfo",&absent);
                                if([fi length]>=32&&!ad_all_zero([fi bytes],32)) Count(counts,@"finderInfo");
                                if(fgetxattr(sourceFD,"com.apple.ResourceFork",NULL,0,0,0)>0) Count(counts,@"resourceForks");
                                if(fgetxattr(sourceFD,"org.netatalk.Metadata",NULL,0,0,0)>=0) Count(counts,@"netatalkMetadata");
                            }
                            continue;
                        }
                        if(!repair) continue;
                        NSString *parent=[directory stringByDeletingLastPathComponent];
                        if([parent isEqualToString:@"."]) parent=@"";
                        NSString *targetRel=old?([name isEqualToString:@".Parent"]?parent:[parent stringByAppendingPathComponent:name]):
                            [directory stringByAppendingPathComponent:[name substringFromIndex:2]];
                        if(!old&&dot&&[name length]==2) Fail(@"An empty AppleDouble target name was left unchanged.");
                        NSString *target=[root stringByAppendingPathComponent:targetRel];
                        targetFD=OpenRelative(rootFD,targetRel,rootStat.st_dev);
                        if(targetFD<0) {
                            if(errno==ENOENT) Count(counts,@"missingTargets");
                            else if(errno==EXDEV) Count(counts,@"mountsSkipped");
                            else if(errno==ELOOP) Count(counts,@"symlinksSkipped");
                            else Fail([@"Cannot safely open AppleDouble target: "stringByAppendingString:targetRel]);
                            continue;
                        }
                        struct stat ta; if(fstat(targetFD,&ta)!=0) Fail(@"Cannot read the metadata target identity.");
                        if(S_ISREG(ta.st_mode)&&ta.st_nlink>1) Fail(@"Hard-linked target was left unchanged because another link may be outside the share.");
                        time_t now=time(NULL);
                        if(a.st_mtimespec.tv_sec>now-10||ta.st_mtimespec.tv_sec>now-10) { Count(counts,@"unstable"); continue; }
                        NSData *data=ReadSidecar(sourceFD,&a); ADParts ad=ad_parts([data bytes],[data length]);
                        if(!ad.valid) Fail([@"Malformed or unsupported AppleDouble: "stringByAppendingString:rel]);
                        NSMutableArray *pending=[NSMutableArray array];
                        if(ad.finderLength>=32) {
                            NSData *f=[data subdataWithRange:NSMakeRange(ad.finderOffset,32)];
                            if(!ad_all_zero([f bytes],[f length])) [pending addObject:@{@"name":@"com.apple.FinderInfo",@"data":f,@"counter":@"finderAdded"}];
                        }
                        if(ad.resourceLength) [pending addObject:@{@"name":@"com.apple.ResourceFork",@"data":[data subdataWithRange:NSMakeRange(ad.resourceOffset,ad.resourceLength)],@"counter":@"resourceAdded"}];
                        NSMutableArray *missing=[NSMutableArray array]; BOOL conflict=NO;
                        for(NSDictionary *entry in pending) {
                            BOOL absent; NSData *native=FDXattr(targetFD,entry[@"name"],&absent);
                            if(absent) [missing addObject:entry];
                            else if(![native isEqualToData:entry[@"data"]]) { Count(counts,@"conflicts"); conflict=YES; [messages addObject:[NSString stringWithFormat:@"CONFLICT (unchanged): %@ / %@",rel,entry[@"name"]]]; }
                        }
                        // Do not combine a fork from one source with a conflicting
                        // native FinderInfo (or vice versa).
                        if(conflict||![missing count]) continue;
                        NSString *backup=BackupSidecar(data,p,target,&backupDir);
                        for(NSDictionary *entry in missing) {
                            NSDictionary *busy=BusySessions();
                            if(busy) { paused=YES; [messages addObject:busy[@"reason"]]; break; }
                            if(!StillNamed(rootFD,root,&rootStat,rel,sourceFD,&a,YES)||
                               !StillNamed(rootFD,root,&rootStat,targetRel,targetFD,&ta,YES)) Fail(@"A file or share changed before metadata write. Retry after copying completes.");
                            NSData *desired=entry[@"data"]; const char *attr=[entry[@"name"]UTF8String];
                            if(fsetxattr(targetFD,attr,[desired bytes],[desired length],0,XATTR_CREATE)!=0) Fail([NSString stringWithFormat:@"Could not add %@ on %@ (errno %d). Existing metadata was not overwritten.",entry[@"name"],rel,errno]);
                            BOOL absent; if(![FDXattr(targetFD,entry[@"name"],&absent)isEqualToData:desired]) Fail([@"Imported metadata could not be verified. Backup retained at "stringByAppendingString:backup]);
                            Count(counts,entry[@"counter"]); [messages addObject:[NSString stringWithFormat:@"ADDED %@: %@",entry[@"name"],rel]];
                            // Our own xattr changes update ctime; refresh the expected
                            // inode state for the second attribute on this same file.
                            if(fstat(targetFD,&ta)!=0) Fail(@"Cannot verify the target after metadata import.");
                        }
                    } @catch(NSException *e) { Count(counts,@"errors"); [messages addObject:[e reason]?:@"Metadata error"]; }
                    @finally { if(sourceFD>=0)close(sourceFD); if(targetFD>=0)close(targetFD); }
                    if([messages count]>1000) [messages removeObjectsInRange:NSMakeRange(0,200)];
                }}
            } @finally { closedir(dir); }
        }
        BOOL ok=[counts[@"errors"]integerValue]==0&&!paused;
        NSString *summary=repair?[NSString stringWithFormat:@"Added %@ FinderInfo / %@ resource forks. %@ conflicts, %@ errors, %@ recent files deferred. Sources were retained.%@",counts[@"finderAdded"],counts[@"resourceAdded"],counts[@"conflicts"],counts[@"errors"],counts[@"unstable"],paused?@" Paused because client activity could not be excluded.":@""]:
            [NSString stringWithFormat:@"Inventoried %@ files and %@ AppleDouble sidecars.",counts[@"files"],counts[@"sidecars"]];
        NSDictionary *result=@{@"ok":@(ok),@"paused":@(paused),@"message":summary,@"timestamp":Stamp(),@"share":root,@"counts":counts,@"backup":backupDir,@"details":messages};
        if(!SaveJSON(result,[SupportDir()stringByAppendingPathComponent:@"metadata-last-run.json"])) Fail(@"Metadata operation finished, but its result could not be saved. Review the backup folder before retrying.");
        if(!background||[counts[@"finderAdded"]intValue]||[counts[@"resourceAdded"]intValue]||!ok) Log([NSString stringWithFormat:@"Metadata %@: %@",root,summary]);
        return result;
    } @finally { if(lock>=0) { flock(lock,LOCK_UN); close(lock); } close(rootFD); }
}
static void BE16(unsigned char *p,unsigned v) { p[0]=(v>>8)&255;p[1]=v&255; }
static void BE32(unsigned char *p,unsigned v) { p[0]=(v>>24)&255;p[1]=(v>>16)&255;p[2]=(v>>8)&255;p[3]=v&255; }
NSDictionary *MetadataTest(NSDictionary *prefs) {
    NSDictionary *s=SelectedShare(prefs); NSString *root=s[@"root"];
    NSString *name=[NSString stringWithFormat:@"AFP Test %@",[[[NSUUID UUID]UUIDString]substringToIndex:8]],*p=[root stringByAppendingPathComponent:name];
    int rootFD=OpenAbsolute(root,YES); if(rootFD<0) Fail(@"Cannot safely open the test share.");
    int fd=-1;
    @try {
        fd=openat(rootFD,[name fileSystemRepresentation],O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if(fd<0) Fail(@"Cannot create a new test file. Existing files were not overwritten.");
        NSData *body=[@"AFP Server native test\rFinder type: TEXT; creator: ttxt\rThis file also contains a valid STR resource, ID 128.\r"dataUsingEncoding:NSMacOSRomanStringEncoding];
        if(write(fd,[body bytes],[body length])!=(ssize_t)[body length]) Fail(@"Test-file data could not be written completely.");
        unsigned char fi[32]={0}; memcpy(fi,"TEXTttxt",8);
        const char *message="AFP resource fork OK"; unsigned len=(unsigned)strlen(message),recordLen=5+len,mapOffset=256+recordLen,mapLen=50;
        NSMutableData *rsrc=[NSMutableData dataWithLength:mapOffset+mapLen]; unsigned char *b=[rsrc mutableBytes];
        BE32(b,256);BE32(b+4,mapOffset);BE32(b+8,recordLen);BE32(b+12,mapLen);BE32(b+256,len+1);b[260]=(unsigned char)len;memcpy(b+261,message,len);
        unsigned char *map=b+mapOffset;memcpy(map,b,16);BE16(map+24,28);BE16(map+26,50);BE16(map+28,0);memcpy(map+30,"STR ",4);BE16(map+34,0);BE16(map+36,10);BE16(map+38,128);BE16(map+40,0xffff);
        if(fsetxattr(fd,"com.apple.FinderInfo",fi,32,0,XATTR_CREATE)!=0||fsetxattr(fd,"com.apple.ResourceFork",[rsrc bytes],[rsrc length],0,XATTR_CREATE)!=0)
            Fail(@"The test data file exists, but native Mac metadata could not be written on this filesystem.");
        BOOL absent; if(![FDXattr(fd,@"com.apple.FinderInfo",&absent)isEqualToData:[NSData dataWithBytes:fi length:32]]||![FDXattr(fd,@"com.apple.ResourceFork",&absent)isEqualToData:rsrc]) Fail(@"Test-file verification failed.");
        Log([@"Created and verified Classic test file: "stringByAppendingString:p]);
        return @{@"ok":@YES,@"message":@"Native test file created and both metadata attributes verified.",@"path":p,@"output":@"Expected on the Classic Mac: Type TEXT, Creator ttxt, valid STR resource #128. Icon appearance also depends on the Classic Finder's desktop database and installed applications. A generic icon alone is not proof of missing resource data."};
    } @finally { if(fd>=0) close(fd); close(rootFD); }
}
static NSString *CopySignature(const struct stat *st) {
    return [NSString stringWithFormat:@"%llu:%llu:%u:%llu:%lld:%ld:%lld:%ld:%llu",
        (unsigned long long)st->st_dev,(unsigned long long)st->st_ino,(unsigned)st->st_mode,(unsigned long long)st->st_size,
        (long long)st->st_mtimespec.tv_sec,st->st_mtimespec.tv_nsec,(long long)st->st_ctimespec.tv_sec,st->st_ctimespec.tv_nsec,(unsigned long long)st->st_nlink];
}
static NSDictionary *CopyManifest(int sourceFD) {
    struct stat root; if(fstat(sourceFD,&root)!=0)Fail(@"Cannot read the import source identity.");
    NSMutableDictionary *manifest=[NSMutableDictionary dictionary];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:@""];
    while([queue count]) {
        NSString *rel=[queue lastObject];[queue removeLastObject];
        int fd=OpenRelative(sourceFD,rel,root.st_dev);if(fd<0)Fail(@"An import source changed, contains a symlink, or crosses a mounted volume. No publish was performed.");
        @try {
            struct stat st;if(fstat(fd,&st)!=0)Fail(@"Cannot inspect an import source.");
            manifest[rel]=CopySignature(&st);
            if([manifest count]>1000000)Fail(@"The import has more than one million entries; split it into smaller batches.");
            if(!S_ISDIR(st.st_mode))continue;
            int enumerationFD=openat(fd,".",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(enumerationFD<0)Fail(@"Cannot enumerate the import source.");
            DIR *dir=fdopendir(enumerationFD);if(!dir) { close(enumerationFD);Fail(@"Cannot enumerate the import source."); }
            @try {
                while(YES) {
                    errno=0;struct dirent *item=readdir(dir);
                    if(!item) { if(errno)Fail(@"Import source enumeration failed.");break; }
                    if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;
                    NSString *name=[[NSFileManager defaultManager]stringWithFileSystemRepresentation:item->d_name length:strlen(item->d_name)];
                    if(!name)Fail(@"An import filename cannot be represented safely.");
                    struct stat child;if(fstatat(dirfd(dir),item->d_name,&child,AT_SYMLINK_NOFOLLOW)!=0)Fail(@"An import source changed while being inspected.");
                    if(S_ISLNK(child.st_mode))Fail(@"Import source contains a symlink. Copy a dedicated folder without symlinks; no linked content was followed.");
                    if(child.st_dev!=root.st_dev)Fail(@"Import source contains a nested mounted volume. Import that volume separately.");
                    if(!S_ISDIR(child.st_mode)&&!S_ISREG(child.st_mode))Fail(@"Import source contains a special file. Only regular files and folders are supported.");
                    [queue addObject:[rel length]?[rel stringByAppendingPathComponent:name]:name];
                }
            } @finally { closedir(dir); }
        } @finally { close(fd); }
    }
    return manifest;
}
// nad 4.6 skips native metadata for sources outside configured AFP volumes.
// Add only absent Mac-native attributes on the private staged copy. The source
// stays intact, and any different metadata already produced by nad is a conflict.
static void PreserveNativeImportMetadata(int sourceFD,int copyFD,NSDictionary *manifest) {
    struct stat sourceRoot,copyRoot;
    if(fstat(sourceFD,&sourceRoot)!=0||fstat(copyFD,&copyRoot)!=0)Fail(@"Cannot inspect metadata import roots.");
    for(NSString *rel in manifest) { @autoreleasepool {
        int src=OpenRelative(sourceFD,rel,sourceRoot.st_dev),dst=OpenRelative(copyFD,rel,copyRoot.st_dev);
        @try {
            struct stat before,target;
            if(src<0||dst<0||fstat(src,&before)!=0||fstat(dst,&target)!=0||![CopySignature(&before)isEqual:manifest[rel]]||
               (before.st_mode&S_IFMT)!=(target.st_mode&S_IFMT))Fail(@"An import entry changed before native metadata could be preserved.");
            for(NSString *attr in @[@"com.apple.FinderInfo",@"com.apple.ResourceFork"]) {
                BOOL missing;NSData *original=FDXattr(src,attr,&missing);if(missing)continue;
                NSData *existing=FDXattr(dst,attr,&missing);
                if(!missing) {
                    if(![existing isEqualToData:original])Fail(@"The staged copy has conflicting native metadata. It was not overwritten.");
                    continue;
                }
                struct stat current;
                if(fstat(src,&current)!=0||!StableObject(&before,&current))Fail(@"The import source changed before native metadata could be preserved.");
                if(fsetxattr(dst,[attr UTF8String],[original bytes],[original length],0,XATTR_CREATE)!=0)
                    Fail(@"Missing native metadata could not be added to the staged copy. Existing attributes were not overwritten.");
                if(![FDXattr(dst,attr,&missing)isEqualToData:original])Fail(@"Native metadata preservation on the staged copy could not be verified.");
            }
            struct stat after;if(fstat(src,&after)!=0||!StableObject(&before,&after))Fail(@"The import source changed during native metadata preservation.");
        } @finally { if(src>=0)close(src);if(dst>=0)close(dst); }
    }}
}
static void VerifyImportedTree(int sourceFD,int copyFD,NSDictionary *manifest) {
    struct stat sourceRoot,copyRoot;
    if(fstat(sourceFD,&sourceRoot)!=0||fstat(copyFD,&copyRoot)!=0)Fail(@"Cannot verify the import roots.");
    for(NSString *rel in manifest) { @autoreleasepool {
        int src=OpenRelative(sourceFD,rel,sourceRoot.st_dev),dst=OpenRelative(copyFD,rel,copyRoot.st_dev);
        @try {
            struct stat ss,ds;
            if(src<0||dst<0||fstat(src,&ss)!=0||fstat(dst,&ds)!=0||![CopySignature(&ss)isEqual:manifest[rel]]||
                (ss.st_mode&S_IFMT)!=(ds.st_mode&S_IFMT))Fail(@"An import entry changed or could not be verified. The staged copy was retained.");
            if(S_ISREG(ss.st_mode)) {
                if(ss.st_size!=ds.st_size)Fail(@"Copied data-fork length differs from its source. The staged copy was retained.");
                unsigned char a[65536],b[65536];off_t offset=0;
                while(offset<ss.st_size) {
                    size_t length=(size_t)MIN((off_t)sizeof a,ss.st_size-offset);
                    ssize_t sa=pread(src,a,length,offset),sb=pread(dst,b,length,offset);
                    if(sa<0&&errno==EINTR)continue;
                    if(sa!=(ssize_t)length||sb!=(ssize_t)length||memcmp(a,b,length))Fail(@"Copied data fork differs from its source. The staged copy was retained.");
                    offset+=(off_t)length;
                }
            }
            for(NSString *attr in @[@"com.apple.FinderInfo",@"com.apple.ResourceFork"]) {
                BOOL missing;NSData *original=FDXattr(src,attr,&missing);if(missing)continue;
                NSData *copied=FDXattr(dst,attr,&missing);
                if(missing||![original isEqualToData:copied])Fail(@"Native resource-fork or Finder metadata did not survive the import. The staged copy was retained.");
            }
            struct stat after;if(fstat(src,&after)!=0||!StableObject(&ss,&after))Fail(@"An import source changed during verification. The staged copy was retained.");
        } @finally { if(src>=0)close(src);if(dst>=0)close(dst); }
    }}
    if(![CopyManifest(sourceFD)isEqualToDictionary:manifest])Fail(@"The source tree changed during copying. The staged copy was retained.");
}
NSDictionary *MetadataCopy(NSDictionary *prefs,NSString *source,NSString *target) {
    NSDictionary *s=SelectedShare(prefs);NSString *root=s[@"root"];
    source=[source stringByStandardizingPath];target=[target stringByStandardizingPath];
    struct stat rawSource,rawTarget;
    if(lstat([source fileSystemRepresentation],&rawSource)!=0||(!S_ISDIR(rawSource.st_mode)&&!S_ISREG(rawSource.st_mode)))Fail(@"Choose a regular file or folder; a symlink source is not imported.");
    if(lstat([target fileSystemRepresentation],&rawTarget)!=0||!S_ISDIR(rawTarget.st_mode))Fail(@"Choose an existing destination folder without a symlink at its name.");
    source=[source stringByResolvingSymlinksInPath];NSString *dest=[target stringByResolvingSymlinksInPath];
    if(!ad_path_contains([root UTF8String],[dest UTF8String]))Fail(@"Copy destination must be within the selected AFP share.");
    NSString *name=[source lastPathComponent],*relative=[dest isEqualToString:root]?@"":[dest substringFromIndex:[root length]+1];
    if(S_ISDIR(rawSource.st_mode)&&ad_path_contains([source UTF8String],[dest UTF8String]))Fail(@"Cannot copy a folder into itself.");
    int rootFD=-1,destFD=-1,sourceFD=-1,stageFD=-1,copyFD=-1;NSString *stage=nil;BOOL published=NO;
    @try {
        rootFD=OpenAbsolute(root,YES);sourceFD=OpenAbsolute(source,S_ISDIR(rawSource.st_mode));
        struct stat rootStat,sourceStat,destStat;
        if(rootFD<0||sourceFD<0||fstat(rootFD,&rootStat)!=0||fstat(sourceFD,&sourceStat)!=0||!SameObject(&rawSource,&sourceStat))Fail(@"An import source or share changed before it could be opened safely.");
        destFD=OpenRelative(rootFD,relative,rootStat.st_dev);
        if(destFD<0||fstat(destFD,&destStat)!=0||!S_ISDIR(destStat.st_mode)||!SameObject(&rawTarget,&destStat))Fail(@"The import destination changed or crosses a mounted volume.");
        struct stat existing;
        if(fstatat(destFD,[name fileSystemRepresentation],&existing,AT_SYMLINK_NOFOLLOW)==0||errno!=ENOENT)Fail(@"A destination with the same name already exists or cannot be checked. It will not be overwritten.");
        NSDictionary *manifest=CopyManifest(sourceFD);
        if(!Tool(@"nad"))Fail(@"Netatalk's nad utility is not installed. No generic copy was substituted.");
        // --force permits a source outside AFP volumes; cp -n protects existing
        // files. The required capability was introduced in Netatalk 4.6.
        NSDictionary *version=Run(@"nad",@[@"--version"],5,nil);
        NSArray *v=Match(@"(?:^|[^0-9])([0-9]+)\\.([0-9]+)(?:\\.[0-9]+)?",S(version[@"out"]));
        if(![version[@"ok"]boolValue]||![v count]||[v[1]integerValue]<4||([v[1]integerValue]==4&&[v[2]integerValue]<6))Fail(@"Import requires Netatalk nad 4.6 or newer. That capability could not be confirmed; no copy was started.");
        // --force is needed for a non-AFP source, but must never silently
        // turn the selected destination into a non-AFP copy without CNID care.
        NSDictionary *recognized=Run(@"nad",@[@"-F",s[@"config"],@"ls",@"-d",dest],15,nil);
        if(![recognized[@"ok"]boolValue])Fail([NSString stringWithFormat:@"Netatalk does not recognize the destination as a configured AFP volume. Check the selected afp.conf, its volume UUID, and the exact share path; no copy was started.\n%@",S(recognized[@"out"])]);
        // Opening the CNID backend may initialize the destination's Netatalk
        // metadata and update ctime. Require the same named inode, then refresh
        // its expected state after our own preflight.
        if(!StillNamed(rootFD,root,&rootStat,relative,destFD,&destStat,NO)||fstat(destFD,&destStat)!=0)Fail(@"The import destination changed before copying.");
        NSString *stageName=[@".AFP Import "stringByAppendingString:[[NSUUID UUID]UUIDString]];
        if(mkdirat(destFD,[stageName fileSystemRepresentation],0700)!=0)Fail(@"Cannot create a private import staging folder.");
        stage=[dest stringByAppendingPathComponent:stageName];
        stageFD=OpenRelative(destFD,stageName,rootStat.st_dev);struct stat stageStat;
        if(stageFD<0||fstat(stageFD,&stageStat)!=0)Fail(@"Cannot safely open the import staging folder.");
        NSMutableString *out=[NSMutableString stringWithString:Checked(@"nad",@[@"--force",@"-F",s[@"config"],@"cp",@"-n",S_ISDIR(sourceStat.st_mode)?@"-a":@"-p",@"-x",source,stage],1800)];
        if(!StillNamed(rootFD,root,&rootStat,relative,destFD,&destStat,NO)||!StillNamed(destFD,dest,&destStat,stageName,stageFD,&stageStat,NO))Fail(@"The import destination moved during copying. Inspect the retained staged copy.");
        copyFD=OpenRelative(stageFD,name,rootStat.st_dev);if(copyFD<0)Fail(@"nad returned success, but the staged copy was not found.");
        PreserveNativeImportMetadata(sourceFD,copyFD,manifest);
        VerifyImportedTree(sourceFD,copyFD,manifest);
        if(fstatat(destFD,[name fileSystemRepresentation],&existing,AT_SYMLINK_NOFOLLOW)==0||errno!=ENOENT)Fail(@"A destination appeared during copying. It was not overwritten; the verified copy remains in staging.");
        struct stat copyStat;if(fstat(copyFD,&copyStat)!=0)Fail(@"Cannot verify the staged copy before publishing.");
        [out appendString:Checked(@"nad",@[@"--force",@"-F",s[@"config"],@"mv",@"-n",[stage stringByAppendingPathComponent:name],dest],1800)];
        int final=OpenRelative(destFD,name,rootStat.st_dev);struct stat finalStat;
        BOOL moved=final>=0&&fstat(final,&finalStat)==0&&SameObject(&copyStat,&finalStat);if(final>=0)close(final);
        if(!moved)Fail(@"The verified import could not be published without a conflict. Inspect the retained staging folder.");
        published=YES;
        if(unlinkat(destFD,[stageName fileSystemRepresentation],AT_REMOVEDIR)!=0)[out appendFormat:@"\nAn import staging directory remains at %@; inspect it before removing it.\n",stage];
        Log([NSString stringWithFormat:@"Verified nad import: %@ -> %@",source,dest]);
        return @{@"ok":@YES,@"message":@"Netatalk-aware import completed; data forks and existing native resource/Finder metadata were verified. Existing destinations were protected.",@"output":out};
    } @catch(NSException *e) {
        if(stage&&!published)Fail([NSString stringWithFormat:@"%@\nAny partial or verified copy is retained for inspection at %@. No automatic deletion was performed.",[e reason],stage]);
        @throw;
    } @finally { if(copyFD>=0)close(copyFD);if(stageFD>=0)close(stageFD);if(sourceFD>=0)close(sourceFD);if(destFD>=0)close(destFD);if(rootFD>=0)close(rootFD); }
}

int WorkerMain(void) {
    @try { NSMutableDictionary *p=Prefs(); NSDictionary *r=MetadataRun(p,YES,YES); if(!SaveJSON(r,[SupportDir()stringByAppendingPathComponent:@"metadata-worker-status.json"]))return 1;return [r[@"ok"]boolValue]||[r[@"paused"]boolValue]?0:1; }
    @catch(NSException *e) { NSDictionary *r=@{@"ok":@NO,@"message":[e reason]?:@"Metadata worker error",@"timestamp":Stamp()};SaveJSON(r,[SupportDir()stringByAppendingPathComponent:@"metadata-worker-status.json"]);Log([@"Metadata worker: "stringByAppendingString:[e reason]?:@"Unknown error"]);return 1; }
}
