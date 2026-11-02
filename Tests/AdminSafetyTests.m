#import <XCTest/XCTest.h>
extern NSDictionary *AdminSafetySelfTest(void);
@interface AdminSafetyTests : XCTestCase
@end
@implementation AdminSafetyTests
- (void)testConfigurationAndPasswordChannelsOnDisposableFiles {
    NSDictionary *report=AdminSafetySelfTest();
    XCTAssertTrue([report[@"ok"]boolValue],@"%@",report);
    XCTAssertEqual([report[@"count"]unsignedIntegerValue],(NSUInteger)12);
}
@end
