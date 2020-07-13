/*
 Copyright (c) 2011-2015, Tony Million.
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

#import "Reachability.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>


#if DEBUG
#	define RLog(_format, ...) NSLog(_format, ##__VA_ARGS__)
#else
#	define RLog(_format, ...)
#endif


// Notification definition
NSString *const kReachabilityChangedNotification = @"kReachabilityChangedNotification";


// Reachability internal interface
@interface Reachability ()

@property (nonatomic, assign) SCNetworkReachabilityRef      reachabilityRef;
@property (nonatomic, strong) dispatch_queue_t              reachabilitySerialQueue;
@property (nonatomic, strong) id                            reachabilityObject;

@property (nonatomic, assign) SCNetworkReachabilityFlags    cachedFlags;

-(void)reachabilityChanged:(SCNetworkReachabilityFlags)flags;
-(BOOL)isReachableWithFlags:(SCNetworkReachabilityFlags)flags;

@end



/*
 Callback for reachability changed notifications
 This basically just calls a method on the Reachability instance
 */

static void TMReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info)
{
#pragma unused (target)

    Reachability *reachability = ((__bridge Reachability*)info);

    // We probably don't need an autoreleasepool here, as GCD docs state each queue has its own autorelease pool,
    // but what the heck eh?
    @autoreleasepool
    {
        [reachability reachabilityChanged:flags];
    }
}


@implementation Reachability

#pragma mark - Class Constructor Methods

+(instancetype)reachabilityWithHostname:(NSString*)hostname
{
    if ([hostname hasPrefix:@"http://"]) {
        RLog(@"-----------> WARNING: you are passing a URL as the hostname, consider only passing the NAME of the HOST you are trying to reach. i.e. www.apple.com instead of http://www.apple.com/ ");
        NSURL * url = [NSURL URLWithString:hostname];
        hostname = url.host;
    }

    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String]);
    if (ref)
    {
        id reachability = [[self alloc] initWithReachabilityRef:ref];

        return reachability;
    }

    return nil;
}

+(instancetype)reachabilityWithAddress:(void *)hostAddress
{
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)hostAddress);
    if (ref)
    {
        id reachability = [[self alloc] initWithReachabilityRef:ref];

        return reachability;
    }

    return nil;
}

+(instancetype)reachabilityForInternetConnection
{
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    return [self reachabilityWithAddress:&zeroAddress];
}

+(instancetype)reachabilityForLocalWiFi
{
    struct sockaddr_in localWifiAddress;
    bzero(&localWifiAddress, sizeof(localWifiAddress));
    localWifiAddress.sin_len            = sizeof(localWifiAddress);
    localWifiAddress.sin_family         = AF_INET;
    // IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0
    localWifiAddress.sin_addr.s_addr    = htonl(IN_LINKLOCALNETNUM);

    return [self reachabilityWithAddress:&localWifiAddress];
}

+(instancetype)reachabilityWithURL:(NSURL*)url
{
    id reachability;

    NSString *host = url.host;
    BOOL isIpAddress = [self isIpAddress:host];

    if (isIpAddress)
    {
        NSNumber *port = url.port ?: [url.scheme isEqualToString:@"https"] ? @(443) : @(80);

        struct sockaddr_in address;
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        address.sin_port = htons([port intValue]);
        address.sin_addr.s_addr = inet_addr([host UTF8String]);

        reachability = [self reachabilityWithAddress:&address];
    }
    else
    {
        reachability = [self reachabilityWithHostname:host];
    }

    return reachability;
}

+(BOOL)isIpAddress:(NSString*)host
{
    struct in_addr pin;
    return 1 == inet_aton([host UTF8String], &pin);
}


// Initialization methods

-(instancetype)initWithReachabilityRef:(SCNetworkReachabilityRef)ref
{
    self = [super init];
    if (self != nil)
    {
        self.reachableOnWWAN = YES;
        self.reachabilityRef = ref;

        // We need to create a serial queue.
        // We allocate this once for the lifetime of the notifier.

        self.reachabilitySerialQueue = dispatch_queue_create("com.tonymillion.reachability", DISPATCH_QUEUE_SERIAL);

        [self updateReachabilityFlagsCompletion:nil];
    }

    return self;
}

-(void)dealloc
{
    [self stopNotifier];

    if(self.reachabilityRef)
    {
        CFRelease(self.reachabilityRef);
        self.reachabilityRef = nil;
    }

	self.reachableBlock          = nil;
    self.unreachableBlock        = nil;
    self.reachabilityBlock       = nil;
    self.reachabilitySerialQueue = nil;
}

#pragma mark - reachability flag getting/updating

-(SCNetworkReachabilityFlags)reachabilityFlags
{
    return self.cachedFlags;
}

/*
 A word of caution about using `synchronousReachabilityFlags`
 This will block the current thread for the duration of getting the flags
 If you call this from the main thread, prepare for deadlocks & UI stutters

 Preferably if you need to do this at all either use `reachabilityFlags` which
 will return a cached view of the status or use the
 `updateReachabilityFlagsCompletion` function with a callback
 */

-(SCNetworkReachabilityFlags)synchronousReachabilityFlags
{
    SCNetworkReachabilityFlags flags = 0;
    if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
    {
        self.cachedFlags = flags;
        return flags;
    }

    return 0;
}

-(void)updateReachabilityFlagsCompletion:(void (^)(SCNetworkReachabilityFlags flags, BOOL success))completion
{
    dispatch_async(self.reachabilitySerialQueue, ^{
        SCNetworkReachabilityFlags flags = 0;
        BOOL worked = NO;
        if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
        {
            worked = YES;
            self.cachedFlags = flags;
        }

        if(completion)
        {
            completion(self.cachedFlags, worked);
        }
    });
}

#pragma mark - Notifier

// Notifier
// NOTE: This uses GCD to trigger the blocks - they *WILL NOT* be called on THE MAIN THREAD
// - In other words DO NOT DO ANY UI UPDATES IN THE BLOCKS.
//   INSTEAD USE dispatch_async(dispatch_get_main_queue(), ^{UISTUFF}) (or dispatch_sync if you want)

-(BOOL)startNotifier
{
    // allow start notifier to be called multiple times
    if(self.reachabilityObject && (self.reachabilityObject == self))
    {
        return YES;
    }

    // first lets retain ourselves
    self.reachabilityObject = self;
    self.cachedFlags = 0;


    SCNetworkReachabilityContext    context = { 0, NULL, NULL, NULL, NULL };
    context.info = (__bridge void *)self;

    if(SCNetworkReachabilitySetCallback(self.reachabilityRef, TMReachabilityCallback, &context))
    {
        // Set it as our reachability queue, which will retain the queue
        if(SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, self.reachabilitySerialQueue))
        {
            [self updateReachabilityFlagsCompletion:^(SCNetworkReachabilityFlags flags, BOOL success) {
                [self reachabilityChanged:flags];
            }];

            return YES;
        }
        else
        {
            RLog(@"SCNetworkReachabilitySetDispatchQueue() failed: %s", SCErrorString(SCError()));
            // UH OH - FAILURE - stop any callbacks!
            SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);
        }
    }
    else
    {
        RLog(@"SCNetworkReachabilitySetCallback() failed: %s", SCErrorString(SCError()));
    }

    // if we get here we fail at the internet
    self.reachabilityObject = nil;
    return NO;
}

-(void)stopNotifier
{
    // First stop, any callbacks!
    SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);

    // Unregister target from the GCD serial dispatch queue.
    SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, NULL);

    self.reachabilityObject = nil;
}

#pragma mark Notifier callback

-(void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
    self.cachedFlags = flags;

    if([self isReachableWithFlags:flags])
    {
        if(self.reachableBlock)
        {
            self.reachableBlock(self);
        }
    }
    else
    {
        if(self.unreachableBlock)
        {
            self.unreachableBlock(self);
        }
    }

    // this makes sure the change notification happens on the MAIN THREAD
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kReachabilityChangedNotification
                                                            object:self];
    });
}

#pragma mark - reachability tests

// This is for the case where you flick the airplane mode;
// you end up getting something like this:
//Reachability: WR ct-----
//Reachability: -- -------
//Reachability: WR ct-----
//Reachability: -- -------
// We treat this as 4 UNREACHABLE triggers - really apple should do better than this

-(BOOL)isReachableWithFlags:(SCNetworkReachabilityFlags)flags
{
#define testcase (kSCNetworkReachabilityFlagsConnectionRequired | kSCNetworkReachabilityFlagsTransientConnection)

    BOOL connectionUP = YES;

    if(!(flags & kSCNetworkReachabilityFlagsReachable))
        connectionUP = NO;

    if( (flags & testcase) == testcase )
        connectionUP = NO;

#if	TARGET_OS_IPHONE
    if(flags & kSCNetworkReachabilityFlagsIsWWAN)
    {
        // We're on 3G.
        if(!self.reachableOnWWAN)
        {
            // We don't want to connect when on 3G.
            connectionUP = NO;
        }
    }
#endif

    return connectionUP;
}

-(BOOL)isReachable
{
    return [self isReachableWithFlags:self.cachedFlags];
}

-(NetworkStatus)currentReachabilityStatus
{
#if	TARGET_OS_IPHONE
    // are we reachable at all?
    if(self.cachedFlags & kSCNetworkReachabilityFlagsReachable)
    {
        // we have a
        if((self.cachedFlags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
        {
            // we are on WIFI
            return ReachableViaWWAN;
        }
        else
        {
            return ReachableViaWiFi;
        }
    }
#else
    // are we reachable at all?
    if(self.cachedFlags & kSCNetworkReachabilityFlagsReachable)
    {
        // we have a
        if((self.cachedFlags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
        {
            // we are on WIFI
            return ReachableViaWWAN;
        }
        else
        {
            return ReachableViaWiFi;
        }
    }
#endif

    return NotReachable;
}

#pragma mark - connection required

// WWAN may be available, but not active until a connection has been established.
// WiFi may require a connection for VPN on Demand.
-(BOOL)connectionRequired
{
    return (self.cachedFlags & kSCNetworkReachabilityFlagsConnectionRequired);
}

// Dynamic, on demand connection?
-(BOOL)connectionOnDemand
{
    return ((self.cachedFlags & kSCNetworkReachabilityFlagsConnectionRequired) &&
            (self.cachedFlags & (kSCNetworkReachabilityFlagsConnectionOnTraffic | kSCNetworkReachabilityFlagsConnectionOnDemand)));
}

// Is user intervention required?
-(BOOL)interventionRequired
{
    return ((self.cachedFlags & kSCNetworkReachabilityFlagsConnectionRequired) &&
            (self.cachedFlags & kSCNetworkReachabilityFlagsInterventionRequired));
}

#pragma mark - printability stuff

-(NSString*)reachabilityString
{
	NetworkStatus temp = [self currentReachabilityStatus];

	if(temp == ReachableViaWWAN)
	{
        // Updated for the fact that we have CDMA phones now!
		return NSLocalizedString(@"Cellular", @"");
	}
	if (temp == ReachableViaWiFi)
	{
		return NSLocalizedString(@"WiFi", @"");
	}

	return NSLocalizedString(@"No Connection", @"");
}

-(NSString*)reachabilityFlagsString
{
    SCNetworkReachabilityFlags flags = self.cachedFlags;

    return [NSString stringWithFormat:@"%c%c %c%c%c%c%c%c%c",
#if	TARGET_OS_IPHONE
            (flags & kSCNetworkReachabilityFlagsIsWWAN)               ? 'W' : '-',
#else
            'X',
#endif
            (flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',
            (flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
            (flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
            (flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
            (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
            (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
            (flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
            (flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-'];
}

#pragma mark - Debug Description

- (NSString *) description
{
    NSString *description = [NSString stringWithFormat:@"<%@: %#x (%@)>",
                             NSStringFromClass([self class]), (unsigned int) self, [self reachabilityFlagsString]];
    return description;
}

@end
