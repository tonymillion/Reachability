//
//  TMViewController.m
//  iOSReachabilityTestARC
//
//  Created by Tony Million on 21/11/2011.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "TMViewController.h"

#import "Reachability.h"

@interface TMViewController ()

-(void)reachabilityChanged:(NSNotification*)note;

@property(strong) Reachability * googleReach;
@property(strong) Reachability * localWiFiReach;
@property(strong) Reachability * internetConnectionReach;

@end



@implementation TMViewController


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    self.blockLabel.text = @"Not Fired Yet";
    self.notificationLabel.text = @"Not Fired Yet";
    self.localWifiblockLabel.text = @"Not Fired Yet";
    self.localWifinotificationLabel.text = @"Not Fired Yet";
    self.internetConnectionblockLabel.text = @"Not Fired Yet";
    self.internetConnectionnotificationLabel.text = @"Not Fired Yet";

    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(reachabilityChanged:) 
                                                 name:kReachabilityChangedNotification 
                                               object:nil];


    __weak __block typeof(self) weakself = self;

    //////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////
    //
    // create a Reachability object for www.google.com

    self.googleReach = [Reachability reachabilityWithHostname:@"www.google.com"];
    
    self.googleReach.reachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@"GOOGLE Block Says Reachable(%@)", reachability.currentReachabilityString];
        NSLog(@"%@", temp);

        // to update UI components from a block callback
        // you need to dipatch this to the main thread
        // this uses NSOperationQueue mainQueue
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            weakself.blockLabel.text = temp;
            weakself.blockLabel.textColor = [UIColor blackColor];
        }];
    };
    
    self.googleReach.unreachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@"GOOGLE Block Says Unreachable(%@)", reachability.currentReachabilityString];
        NSLog(@"%@", temp);

        // to update UI components from a block callback
        // you need to dipatch this to the main thread
        // this one uses dispatch_async they do the same thing (as above)
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.blockLabel.text = temp;
            weakself.blockLabel.textColor = [UIColor redColor];
        });
    };
    
    [self.googleReach startNotifier];



    //////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////
    //
    // create a reachability for the local WiFi

    self.localWiFiReach = [Reachability reachabilityForLocalWiFi];

    // we ONLY want to be reachable on WIFI - cellular is NOT an acceptable connectivity
    self.localWiFiReach.reachableOnWWAN = NO;

    self.localWiFiReach.reachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@"LocalWIFI Block Says Reachable(%@)", reachability.currentReachabilityString];
        NSLog(@"%@", temp);

        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.localWifiblockLabel.text = temp;
            weakself.localWifiblockLabel.textColor = [UIColor blackColor];
        });
    };

    self.localWiFiReach.unreachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@"LocalWIFI Block Says Unreachable(%@)", reachability.currentReachabilityString];

        NSLog(@"%@", temp);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.localWifiblockLabel.text = temp;
            weakself.localWifiblockLabel.textColor = [UIColor redColor];
        });
    };

    [self.localWiFiReach startNotifier];



    //////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////
    //
    // create a Reachability object for the internet

    self.internetConnectionReach = [Reachability reachabilityForInternetConnection];

    self.internetConnectionReach.reachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@" InternetConnection Says Reachable(%@)", reachability.currentReachabilityString];
        NSLog(@"%@", temp);

        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.internetConnectionblockLabel.text = temp;
            weakself.internetConnectionblockLabel.textColor = [UIColor blackColor];
        });
    };

    self.internetConnectionReach.unreachableBlock = ^(Reachability * reachability)
    {
        NSString * temp = [NSString stringWithFormat:@"InternetConnection Block Says Unreachable(%@)", reachability.currentReachabilityString];

        NSLog(@"%@", temp);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.internetConnectionblockLabel.text = temp;
            weakself.internetConnectionblockLabel.textColor = [UIColor redColor];
        });
    };

    [self.internetConnectionReach startNotifier];

}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

-(void)reachabilityChanged:(NSNotification*)note
{
    Reachability * reach = [note object];

    if(reach == self.googleReach)
    {
        if([reach isReachable])
        {
            NSString * temp = [NSString stringWithFormat:@"GOOGLE Notification Says Reachable(%@)", reach.currentReachabilityString];
            NSLog(@"%@", temp);

            self.notificationLabel.text = temp;
            self.notificationLabel.textColor = [UIColor blackColor];
        }
        else
        {
            NSString * temp = [NSString stringWithFormat:@"GOOGLE Notification Says Unreachable(%@)", reach.currentReachabilityString];
            NSLog(@"temp");

            self.notificationLabel.text = temp;
            self.notificationLabel.textColor = [UIColor redColor];
        }
    }
    else if (reach == self.localWiFiReach)
    {
        if([reach isReachable])
        {
            NSString * temp = [NSString stringWithFormat:@"LocalWIFI Notification Says Reachable(%@)", reach.currentReachabilityString];
            NSLog(@"%@", temp);

            self.localWifinotificationLabel.text = temp;
            self.localWifinotificationLabel.textColor = [UIColor blackColor];
        }
        else
        {
            NSString * temp = [NSString stringWithFormat:@"LocalWIFI Notification Says Unreachable(%@)", reach.currentReachabilityString];
            NSLog(@"%@", temp);

            self.localWifinotificationLabel.text = temp;
            self.localWifinotificationLabel.textColor = [UIColor redColor];
        }
    }
    else if (reach == self.internetConnectionReach)
    {
        if([reach isReachable])
        {
            NSString * temp = [NSString stringWithFormat:@"InternetConnection Notification Says Reachable(%@)", reach.currentReachabilityString];
            NSLog(@"%@", temp);

            self.internetConnectionnotificationLabel.text = temp;
            self.internetConnectionnotificationLabel.textColor = [UIColor blackColor];
        }
        else
        {
            NSString * temp = [NSString stringWithFormat:@"InternetConnection Notification Says Unreachable(%@)", reach.currentReachabilityString];
            NSLog(@"%@", temp);

            self.internetConnectionnotificationLabel.text = temp;
            self.internetConnectionnotificationLabel.textColor = [UIColor redColor];
        }
    }

}


@end
