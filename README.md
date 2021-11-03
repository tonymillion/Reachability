[![Reference Status](https://www.versioneye.com/objective-c/reachability/reference_badge.svg?style=flat)](https://www.versioneye.com/objective-c/reachability/references)
[![build-status](https://github.com/tonymillion/Reachability/actions/workflows/CI.yml/badge.svg)](https://github.com/tonymillion/Reachability/actions)

# **WARNING** there have been reports of apps being rejected when Reachability is used in a framework. The only solution to this so far is to rename the class.

# Reachability

This is a drop-in replacement for Apple's `Reachability` class. It is ARC-compatible, and it uses the new GCD methods to notify of network interface changes.

In addition to the standard `NSNotification`, it supports the use of blocks for when the network becomes reachable and unreachable.

Finally, you can specify whether a WWAN connection is considered "reachable".

*DO NOT OPEN BUGS UNTIL YOU HAVE TESTED ON DEVICE*

**BEFORE YOU OPEN A BUG ABOUT iOS6/iOS5 build errors, use Tag 3.2 or 3.1 as they support assign types**

## Requirements

Once you have added the `.h/m` files to your project, simply:

* Go to the `Project->TARGETS->Build Phases->Link Binary With Libraries`.
* Press the plus in the lower left of the list.
* Add `SystemConfiguration.framework`.

Boom, you're done.

## Examples

### Block Example

This sample uses blocks to notify when the interface state has changed. The blocks will be called on a **BACKGROUND THREAD**, so you need to dispatch UI updates onto the main thread.

#### In Objective-C

```objc
// Allocate a reachability object
Reachability* reach = [Reachability reachabilityWithHostname:@"www.google.com"];

// Set the blocks
reach.reachableBlock = ^(Reachability*reach)
{
    // keep in mind this is called on a background thread
    // and if you are updating the UI it needs to happen
    // on the main thread, like this:

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"REACHABLE!");
    });
};

reach.unreachableBlock = ^(Reachability*reach)
{
    NSLog(@"UNREACHABLE!");
};

// Start the notifier, which will cause the reachability object to retain itself!
[reach startNotifier];
```

### In Swift 3

```swift
import Reachability

var reach: Reachability?

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Allocate a reachability object
        self.reach = Reachability.forInternetConnection()
        
        // Set the blocks
        self.reach!.reachableBlock = {
            (reach: Reachability?) -> Void in
            
            // keep in mind this is called on a background thread
            // and if you are updating the UI it needs to happen
            // on the main thread, like this:
            DispatchQueue.main.async {
                print("REACHABLE!")
            }
        }
        
        self.reach!.unreachableBlock = {
            (reach: Reachability?) -> Void in
            print("UNREACHABLE!")
        }
        
        self.reach!.startNotifier()
    
        return true
}
```

### `NSNotification` Example

This sample will use `NSNotification`s to notify when the interface has changed. They will be delivered on the **MAIN THREAD**, so you *can* do UI updates from within the function.

In addition, it asks the `Reachability` object to consider the WWAN (3G/EDGE/CDMA) as a non-reachable connection (you might use this if you are writing a video streaming app, for example, to save the user's data plan).

#### In Objective-C

```objc
// Allocate a reachability object
Reachability* reach = [Reachability reachabilityWithHostname:@"www.google.com"];

// Tell the reachability that we DON'T want to be reachable on 3G/EDGE/CDMA
reach.reachableOnWWAN = NO;

// Here we set up a NSNotification observer. The Reachability that caused the notification
// is passed in the object parameter
[[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(reachabilityChanged:)
                                             name:kReachabilityChangedNotification
                                           object:nil];

[reach startNotifier];
```

#### In Swift 3

```swift
import Reachability

var reach: Reachability?

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    // Allocate a reachability object
    self.reach = Reachability.forInternetConnection()
    
    // Tell the reachability that we DON'T want to be reachable on 3G/EDGE/CDMA
    self.reach!.reachableOnWWAN = false
    
    // Here we set up a NSNotification observer. The Reachability that caused the notification
    // is passed in the object parameter
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(reachabilityChanged),
        name: NSNotification.Name.reachabilityChanged,
        object: nil
    )
    
    self.reach!.startNotifier()
    
    return true
}
        
func reachabilityChanged(notification: NSNotification) {
    if self.reach!.isReachableViaWiFi() || self.reach!.isReachableViaWWAN() {
        print("Service available!!!")
    } else {
        print("No service available!!!")
    }
}
```

## Tell the world

Head over to [Projects using Reachability](https://github.com/tonymillion/Reachability/wiki/Projects-using-Reachability) and add your project for "Maximum Wins!".
