#import <XCTest/XCTest.h>
extern NSComparisonResult PackageCompareVersions(NSString *,NSString *);
extern NSDictionary *PackageValidateRelease(NSDictionary *);
extern NSDictionary *PackageSafetySelfTest(void);
extern NSDictionary *PackageValidateFormula(NSDictionary *,NSDictionary *);
@interface PackageTests : XCTestCase
@end
@implementation PackageTests
- (void)testConfigurationBackupsAndMigrationUseDisposableFiles {
    NSDictionary *report=PackageSafetySelfTest();
    XCTAssertTrue([report[@"ok"]boolValue],@"%@",report);
    XCTAssertEqual([report[@"count"]unsignedIntegerValue],(NSUInteger)5);
}
- (NSDictionary *)releaseFixture {
    return @{@"tag_name":@"netatalk-4-6-1",@"draft":@NO,@"prerelease":@NO,@"html_url":@"https://github.com/Netatalk/netatalk/releases/tag/netatalk-4-6-1",@"published_at":@"2026-10-02T05:28:00Z",@"assets":@[@{@"name":@"netatalk-4.6.1.tar.xz",@"state":@"uploaded",@"browser_download_url":@"https://github.com/Netatalk/netatalk/releases/download/netatalk-4-6-1/netatalk-4.6.1.tar.xz",@"digest":@"sha256:c97412f7f4bbbbfa922664f52b9d6a5f75282b99a52fe0463134bb477fea715e"}]};
}
- (NSDictionary *)formula {
    return @{@"formulae":@[@{@"full_name":@"netatalk",@"tap":@"homebrew/core",@"versions":@{@"stable":@"4.6.1"},@"urls":@{@"stable":@{@"url":@"https://github.com/Netatalk/netatalk/releases/download/netatalk-4-6-1/netatalk-4.6.1.tar.xz",@"checksum":@"c97412f7f4bbbbfa922664f52b9d6a5f75282b99a52fe0463134bb477fea715e"}},@"pinned":@NO,@"disabled":@NO,@"deprecated":@NO}]};
}
- (void)testVersionComparisonIsNumericAndDoesNotAcceptShellText {
    XCTAssertEqual(PackageCompareVersions(@"4.10.0",@"4.9.9"),NSOrderedDescending);
    XCTAssertEqual(PackageCompareVersions(@"4.6",@"4.6.0"),NSOrderedSame);
    XCTAssertEqual(PackageCompareVersions(@"4.6.1",@"4.7.0"),NSOrderedAscending);
    XCTAssertThrows(PackageCompareVersions(@"4.6.1; touch /tmp/no",@"4.6.1"));
    XCTAssertThrows(PackageCompareVersions(@"4.7.0-rc1",@"4.6.1"));
}
- (void)testStableReleaseRequiresOfficialRepositoryAndSourceDigest {
    NSDictionary *valid=PackageValidateRelease([self releaseFixture]);XCTAssertEqualObjects(valid[@"latestVersion"],@"4.6.1");
    NSMutableDictionary *other=[[self releaseFixture]mutableCopy];other[@"html_url"]=@"https://example.org/releases/netatalk-4-6-1";XCTAssertThrows(PackageValidateRelease(other));
    NSMutableDictionary *asset=[other[@"assets"][0]mutableCopy];asset[@"digest"]=@"sha256:invalid";other=[[self releaseFixture]mutableCopy];other[@"assets"]=@[asset];XCTAssertThrows(PackageValidateRelease(other));
    asset=[[[self releaseFixture][@"assets"]firstObject]mutableCopy];asset[@"browser_download_url"]=@"https://example.org/netatalk-4.6.1.tar.xz";other[@"assets"]=@[asset];XCTAssertThrows(PackageValidateRelease(other));
}
- (void)testDraftAndPrereleaseAreNeverPresentedAsLatestStable {
    NSMutableDictionary *raw=[[self releaseFixture]mutableCopy];raw[@"draft"]=@YES;XCTAssertThrows(PackageValidateRelease(raw));
    raw=[[self releaseFixture]mutableCopy];raw[@"prerelease"]=@YES;XCTAssertThrows(PackageValidateRelease(raw));
    raw=[[self releaseFixture]mutableCopy];raw[@"tag_name"]=@"netatalk-4-7-0-rc1";XCTAssertThrows(PackageValidateRelease(raw));
}
- (void)testHomebrewMustMatchVerifiedStableSourceAndChecksum {
    NSDictionary *release=PackageValidateRelease([self releaseFixture]);XCTAssertNoThrow(PackageValidateFormula([self formula],release));
    NSMutableDictionary *f=[[self formula][@"formulae"][0]mutableCopy];f[@"versions"]=@{@"stable":@"4.5.0"};XCTAssertThrows(PackageValidateFormula(@{@"formulae":@[f]},release));
    f=[[self formula][@"formulae"][0]mutableCopy];f[@"urls"]=@{@"stable":@{@"url":release[@"sourceURL"],@"checksum":@"0000000000000000000000000000000000000000000000000000000000000000"}};XCTAssertThrows(PackageValidateFormula(@{@"formulae":@[f]},release));
}
- (void)testCustomTapPinnedAndDisabledFormulaArePreserved {
    NSDictionary *release=PackageValidateRelease([self releaseFixture]);
    for(NSString *key in @[@"pinned",@"disabled",@"deprecated"]){NSMutableDictionary *f=[[self formula][@"formulae"][0]mutableCopy];f[key]=@YES;XCTAssertThrows(PackageValidateFormula(@{@"formulae":@[f]},release));}
    NSMutableDictionary *f=[[self formula][@"formulae"][0]mutableCopy];f[@"tap"]=@"someone/custom";XCTAssertThrows(PackageValidateFormula(@{@"formulae":@[f]},release));
}
@end
