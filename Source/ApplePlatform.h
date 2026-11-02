/* Native SDK build: compile only with the actual Apple SDK. */
#pragma once
#ifndef __APPLE__
#error "Build AFP Server using Xcode on macOS. The old ABI shim is no longer used."
#endif
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <OpenDirectory/OpenDirectory.h>
#include <sys/types.h>
#include <sys/file.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import <objc/runtime.h>
