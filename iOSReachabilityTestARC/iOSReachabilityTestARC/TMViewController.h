//
//  TMViewController.h
//  iOSReachabilityTestARC
//
//  Created by Tony Million on 21/11/2011.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TMViewController : UIViewController

@property (weak, nonatomic) IBOutlet UILabel * blockLabel;
@property (weak, nonatomic) IBOutlet UILabel * notificationLabel;


@property (weak, nonatomic) IBOutlet UILabel * localWifiblockLabel;
@property (weak, nonatomic) IBOutlet UILabel * localWifinotificationLabel;


@property (weak, nonatomic) IBOutlet UILabel * internetConnectionblockLabel;
@property (weak, nonatomic) IBOutlet UILabel * internetConnectionnotificationLabel;


@end
