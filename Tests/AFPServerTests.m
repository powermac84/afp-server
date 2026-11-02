#import <XCTest/XCTest.h>
#import "Core.h"
@interface AFPServerTests : XCTestCase
@end
@implementation AFPServerTests
- (void)testObjectHeaderIsNotUsedForTheFirstProperty {
    XCTAssertNoThrow(AFPAssertObjectLayout());
    Ivar field=class_getInstanceVariable([AFPConfig class],"_original");
    XCTAssertNotEqual(field,(Ivar)NULL);
    XCTAssertGreaterThanOrEqual(ivar_getOffset(field),(ptrdiff_t)class_getInstanceSize([NSObject class]));
}
- (void)testCoreRegressionSuite {
    NSDictionary *report=CoreSelfTest();
    XCTAssertTrue([report[@"ok"] boolValue],@"%@",report);
}
- (void)testRepeatedConfigurationInitializationAndRelease {
    for(NSUInteger i=0;i<1000;i++) { @autoreleasepool {
        NSString *text=@"[Global]\nserver name=Test\n[Classic]\npath=/tmp/afp-xcode-test\n";
        AFPConfig *config=[[AFPConfig alloc] initWithText:text];
        XCTAssertEqualObjects(config.original,text);
        XCTAssertEqual([[config shares] count],(NSUInteger)1);
    }}
}
@end
