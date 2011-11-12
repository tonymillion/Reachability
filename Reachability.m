/*
 Copyright (c) 2011, Tony Million.
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

NSString *const kReachabilityChangedNotification = @"kReachabilityChangedNotification";

@interface Reachability (private)

+(Reachability *)reachabilityWithAddress:(const struct sockaddr_in *)hostAddress;

-(void)reachabilityChanged:(SCNetworkReachabilityFlags)flags;
-(BOOL)setReachabilityTarget:(NSString*)hostname;

@end

static NSString *reachabilityFlags(SCNetworkReachabilityFlags flags) 
{
    return [NSString stringWithFormat:@"%c%c %c%c%c%c%c%c%c",
			(flags & kSCNetworkReachabilityFlagsIsWWAN)               ? 'W' : '-',
			(flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',
			(flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
			(flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
			(flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
			(flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
			(flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
			(flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
			(flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-'];
}

//Start listening for reachability notifications on the current run loop
static void TMReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) 
{
#pragma unused (target)
    Reachability *reachability = ((__bridge Reachability*)info);
    
    // we probably dont need an autoreleasepool here as GCD docs state each queue has its own autorelease pool
    // but what the heck eh?
	@autoreleasepool 
    {
        [reachability reachabilityChanged:flags];
    }
}


@implementation Reachability

@synthesize reachabilityRef;
@synthesize reachabilitySerialQueue;

@synthesize reachableOnWWAN;

@synthesize reachableBlock;
@synthesize unreachableBlock;

@synthesize reachabilityObject;

+(Reachability*)reachabilityWithHostname:(NSString*)hostname
{
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String]);
	if (ref) 
    {
		return [[self alloc] initWithReachabilityRef:ref];
	}
	
	return nil;
}

+(Reachability *)reachabilityWithAddress:(const struct sockaddr_in *)hostAddress 
{
	SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)hostAddress);
	if (ref) 
    {
		return [[self alloc] initWithReachabilityRef:ref];
	}
	
	return nil;
}

+(Reachability *)reachabilityForInternetConnection 
{	
	struct sockaddr_in zeroAddress;
	bzero(&zeroAddress, sizeof(zeroAddress));
	zeroAddress.sin_len = sizeof(zeroAddress);
	zeroAddress.sin_family = AF_INET;
    
	return [self reachabilityWithAddress:&zeroAddress];
}

// initialization methods

-(Reachability *)initWithReachabilityRef:(SCNetworkReachabilityRef)ref 
{
    self = [super init];
	if (self != nil) 
    {
        self.reachableOnWWAN = YES;
		self.reachabilityRef = ref;
	}
	
	return self;	
}

-(void)dealloc
{
    if(self.reachabilityRef)
    {
        CFRelease(self.reachabilityRef);
        self.reachabilityRef = nil;
    }
#ifdef DEBUG
    NSLog(@"DEALLOC ZOMG");
#endif
}

// Notifier 
// NOTE: this uses GCD to trigger the blocks - they *WILL NOT* be called on THE MAIN THREAD
// - In other words DO NOT DO ANY UI UPDATES IN THE BLOCKS.
//   INSTEAD USE dispatch_async(dispatch_get_main_thread(), ^{UISTUFF}) (or dispatch_sync if you want)

-(BOOL)startNotifier
{
    SCNetworkReachabilityContext	context	= { 0, NULL, NULL, NULL, NULL };
    
    // this should do a retain on ourself, so as long as we're in notifier mode we shouldn't disappear out from under ourselves
    // woah
    self.reachabilityObject = self;
    
    context.info = (__bridge void *)self;
    
    if (!SCNetworkReachabilitySetCallback(self.reachabilityRef, TMReachabilityCallback, &context)) 
    {
        printf("SCNetworkReachabilitySetCallback() failed: %s\n", SCErrorString(SCError()));
        return NO;
    }
    
    //create a serial queue
    self.reachabilitySerialQueue = dispatch_queue_create("com.tonymillion.reachability", DISPATCH_QUEUE_SERIAL);        
    
    // set it as our reachability queue which will retain the queue
    if(SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, self.reachabilitySerialQueue))
    {
        dispatch_release(self.reachabilitySerialQueue);
        // refcount should be ++ from the above function so this -- will mean its still 1
        return YES;
    }
    
    dispatch_release(self.reachabilitySerialQueue);
    self.reachabilitySerialQueue = nil;
    return NO;
}

-(void)stopNotifier
{
    // first stop any callbacks!
    SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);
    
    // unregister target from the GCD serial dispatch queue
    // this will mean the dispatch queue gets dealloc'ed
    if(self.reachabilitySerialQueue)
    {
        SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, NULL);
        self.reachabilitySerialQueue = nil;
    }
    
    self.reachabilityObject = nil;
}

#define testcase (kSCNetworkReachabilityFlagsConnectionRequired | kSCNetworkReachabilityFlagsTransientConnection)

-(BOOL)isReachable
{
    SCNetworkReachabilityFlags flags;  
    
    if(!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
        return NO;
    
    BOOL connectionUP = YES;
	
    if(!(flags & kSCNetworkReachabilityFlagsReachable))
        connectionUP = NO;
    
    if( (flags & testcase) == testcase )
        connectionUP = NO;
	
	if(flags & kSCNetworkReachabilityFlagsIsWWAN)
	{
		// we're on 3G
		if(!self.reachableOnWWAN)
		{
			// we dont want to connect when on 3G
			connectionUP = NO;
		}
	}
    
    return connectionUP;
}

-(BOOL)isReachableViaWWAN 
{
	SCNetworkReachabilityFlags flags = 0;
	
	if(SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) 
    {
        if(!(flags & kSCNetworkReachabilityFlagsReachable))
            return NO;
        
        if(flags & kSCNetworkReachabilityFlagsIsWWAN)
        {
            return YES;
        }
	}
	
	return NO;
}

-(BOOL)isReachableViaWiFi 
{
	SCNetworkReachabilityFlags flags = 0;
	
	if(SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) 
    {
        if(!(flags & kSCNetworkReachabilityFlagsReachable))
            return NO;
        
        if(!(flags & kSCNetworkReachabilityFlagsIsWWAN))
        {
            return YES;
        }
	}
	
	return NO;
}

-(NetworkStatus)currentReachabilityStatus
{
    if([self isReachable])
    {
        if([self isReachableViaWiFi])
            return ReachableViaWiFi;
        
        return ReachableViaWWAN;
    }
    
    return NotReachable;
}


-(void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
#ifdef DEBUG
    NSLog(@"Reachability: %@", reachabilityFlags(flags));
#endif
    
	if([self isReachable])
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

@end
