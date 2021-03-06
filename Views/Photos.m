/*

Copyright (C) 2010  CycleStreets Ltd

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

*/

//  Photos.m
//  CycleStreets
//
//  Created by Alan Paxton on 09/03/2010.
//

#import "Common.h"
#import "Photos.h"
#import "UIButton+Blue.h"
#import "UserValidate.h"
#import "CycleStreets.h"
#import "Files.h"
#import "CategoryLoader.h"
#import "PhotoEntry.h"
#import "AssetGroupTable.h"
#import "ALAsset+Info.h"
#import "PhotoAsset.h"

@implementation Photos

@synthesize selected;
@synthesize camera;
@synthesize library;
@synthesize caption;
@synthesize info;
@synthesize send;
@synthesize del;
@synthesize accuracy;
@synthesize toolbar;
@synthesize photoToolbar;
@synthesize captionText;
@synthesize captionBar;
@synthesize captionDone;

@synthesize sendingAlert;
@synthesize alert;
@synthesize deleteAlert;
@synthesize emailAlert;
@synthesize errorAlert;

@synthesize loginView;

@synthesize currentCaption;

@synthesize preview;
@synthesize bigImageURL;
@synthesize photoId;

@synthesize userValidate;
@synthesize userCreate;
@synthesize addPhoto;
@synthesize photoInfo;
@synthesize photoAction;
@synthesize location;
@synthesize lastUploadId;

@synthesize assetGroupTable;
@synthesize photoAsset;
@synthesize navigateLibrary;

@synthesize picker;
@synthesize jpegData;

/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}
*/

#pragma mark password load/save

- (void) saveUserPass {
	DLog(@">>>");
	CycleStreets *cycleStreets = (CycleStreets *)[CycleStreets sharedInstance:[CycleStreets class]];
	NSMutableDictionary *misc = [NSMutableDictionary dictionaryWithDictionary:[cycleStreets.files misc]];
	[misc setValue:username forKey:@"username"];
	[misc setValue:validated forKey:@"validated"];
	[cycleStreets.files setMisc:misc];
	[cycleStreets.files setPassword:password];
}

- (void) loadUserPass {
	DLog(@">>>");
	CycleStreets *cycleStreets = (CycleStreets *)[CycleStreets sharedInstance:[CycleStreets class]];
	NSDictionary *misc = [cycleStreets.files misc];
	NSString *loadedPassword = [cycleStreets.files password];
	NSString *loadedUsername = [misc valueForKey:@"username"];
	NSString *loadedValidated = [misc valueForKey:@"validated"];
	if (loadedPassword != nil && ![loadedPassword isEqualToString:@""] && loadedUsername != nil && ![loadedUsername isEqualToString:@""]) {
		username = [loadedUsername copy];
		password = [loadedPassword copy];
		validated = [loadedValidated copy];
	} else {
		validated = nil;
		username = nil;
		password = nil;
	}
}

- (void)didNotificationClearAccount:(NSNotification *)clearAccountNotification {
	[username release];
	[password release];
	[validated release];
	username = nil;
	password = nil;
	validated = nil;
	[self.loginView clearFields];
}

#pragma mark alerts

//release the simple alert we got here.
- (void)alertViewCancel:(UIAlertView *)alertView {
	[alertView release];
}

//cancel one of our own busy alerts.
- (void) didCancelAlert {
	DLog(@">>>");
}

#pragma mark view

-(void)enableButtons:(BOOL)enable {
	toolbar.hidden = (self.photoAsset != nil);
	photoToolbar.hidden = (self.photoAsset == nil);
		
	BOOL libAvail = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary];
	BOOL cameraAvail = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
	self.camera.enabled = enable && (cameraAvail || libAvail) && !sendInProgress;
	self.send.enabled = enable && (self.photoAsset != nil) && (self.photoInfo != nil) && !sendInProgress;
	self.caption.enabled = enable && (self.photoAsset != nil) && !sendInProgress;
	self.info.enabled = enable && (self.photoAsset != nil) && !sendInProgress;
	
	caption.title = ([captionText.text length] == 0) ? @"Add Caption" : @"Set Caption";
	
	if (self.info.enabled && self.photoInfo == nil) {
		self.info.style = UIBarButtonItemStyleDone;
	} else {
		self.info.style = UIBarButtonItemStyleBordered;
	}
	if (self.send.enabled) {
		self.send.style = UIBarButtonItemStyleDone;
	} else {
		self.send.style = UIBarButtonItemStyleBordered;
	}
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
	// set up location manager
	self.accuracy.title = @"";
	locationManager = [[CLLocationManager alloc] init];
	locationManager.delegate = self;
	[locationManager startUpdatingLocation];
	
	// get any stored credentials
	[self loadUserPass];
	
	// set up an alert to use
	self.sendingAlert = [[BusyAlert alloc] initWithTitle:@"CycleStreets" message:@"Sending photomap.."];
	
	//
	self.captionText.hidden = YES;
	self.captionText.delegate = self;
	self.captionBar.hidden = YES;
	self.photoAsset = nil;
	sendInProgress = NO;
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didNotificationLibraryAsset:)
												 name:@"NotificationLibraryAsset"
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didNotificationClearAccount:)
												 name:@"NotificationClearAccount"
											   object:nil];
	[self enableButtons:YES];
}

- (BOOL)textViewShouldEndEditing:(UITextView *)textView {
	return YES;
}

// hide the caption text when it's finished.
- (void)textViewDidEndEditing:(UITextView *)textView {
	[textView resignFirstResponder];
	if (textView == captionText) {
		captionText.hidden = YES;
		captionBar.hidden = YES;
	}
	[self enableButtons:YES];
}

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

//Use the built-in picker(s)
- (void) pickImageFromSource:(int)source {
	if (self.picker == nil) {
		self.picker = [[[UIImagePickerController alloc] init] autorelease];
	}
	self.picker.delegate = self;
	self.picker.allowsEditing = NO;
	self.picker.sourceType = source;
	[self presentModalViewController:self.picker animated:YES];
}

//Use picker which accesses the Asset library
-(void)pickImageFromLibrary {
	if (self.assetGroupTable == nil) {
		self.assetGroupTable = [[[AssetGroupTable alloc] init] autorelease];
	}
	if (self.navigateLibrary == nil) {
		self.navigateLibrary = [[[UINavigationController alloc] init] autorelease];
		[self.navigateLibrary pushViewController:assetGroupTable animated:NO];
	}
	[self presentModalViewController:self.navigateLibrary animated:YES];
}

//What action did the user invoke ?
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	DLog(@"%d", buttonIndex);
	if (actionSheet == self.photoAction) {
		if (buttonIndex == [self.photoAction cancelButtonIndex]) {
			return;
		} else if (buttonIndex == [self.photoAction firstOtherButtonIndex]) {
			[self pickImageFromSource:UIImagePickerControllerSourceTypeCamera];
		} else {
			[self pickImageFromLibrary];
		}
	}
}

//wrap whether there is a camera
- (BOOL)canUseCamera {
	return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
}

//photo library is accessed via custom picker using iOS4.0 Asset Library, as we need EXIF Data.
- (BOOL)canUsePhotoLibrary {
	BOOL hasLibrary = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary];
	NSString *version = [UIDevice currentDevice].systemVersion;
	BOOL canUse = ([version doubleValue] >= 4.0);
	return (hasLibrary && canUse);
}

//if there's a choice to be made, use an action sheet.
//otherwise, straight into the appropriate source type.
- (void) sourceAnImage {
	//what sources are there ?
	if ([self canUseCamera] && [self canUsePhotoLibrary]) {
		if (self.photoAction == nil) {
			self.photoAction = [[[UIActionSheet alloc] initWithTitle:nil
															delegate:self
												   cancelButtonTitle:@"Cancel"
											  destructiveButtonTitle:nil
												   otherButtonTitles:@"Take Photo", @"Choose Existing", nil]
								autorelease];
		}
		[self.photoAction showFromToolbar:self.toolbar];
		//cancel is not detected (iOS bug ?) [self.photoAction showInView:self.view];
	} else if ([self canUseCamera]) {
		[self pickImageFromSource:UIImagePickerControllerSourceTypeCamera];
	} else if ([self canUsePhotoLibrary]) {
		[self pickImageFromLibrary];
	}
}

- (IBAction) didCamera {
	[self sourceAnImage];
}

- (void)sendPhoto {
	self.addPhoto = nil;
	self.addPhoto = [[AddPhoto alloc] initWithUsername:username withPassword:password];
	
	self.addPhoto.caption = self.currentCaption;
	
	self.addPhoto.category = [self.photoInfo category];
	self.addPhoto.metaCategory = [self.photoInfo metaCategory];
	if (self.photoInfo == nil) {
		self.addPhoto.category = [CategoryLoader defaultCategory];
		self.addPhoto.metaCategory = [CategoryLoader defaultMetaCategory];
	}
	
	//lat/long.
	BOOL setLatLon = NO;
	if (self.photoAsset != nil) {
		CLLocationCoordinate2D coordinate = [self.photoAsset coordinate];
		if (coordinate.latitude != 0.0 || coordinate.longitude != 0.0) {
			self.addPhoto.longitude = [NSString stringWithFormat:@"%f", coordinate.longitude];
			self.addPhoto.latitude = [NSString stringWithFormat:@"%f", coordinate.latitude];
			setLatLon = YES;
		}
	}
	if (!setLatLon && location == nil) {
		self.addPhoto.longitude = @"0.0";
		self.addPhoto.latitude = @"60.0";
		setLatLon = YES;
	}
	if (!setLatLon) {
		self.addPhoto.longitude = [NSString stringWithFormat:@"%f", location.coordinate.longitude];
		self.addPhoto.latitude = [NSString stringWithFormat:@"%f", location.coordinate.latitude];
	}
	
	//privacy
	if (validated != nil && ![validated isEqual:@""]) {
		self.addPhoto.privacy = @"Public";
	} else {
		self.addPhoto.privacy = @"Private";
	}
	
	//image
	//self.addPhoto.imageData = UIImageJPEGRepresentation( selected.image, 0.8);
	
	CycleStreets *cycleStreets = (CycleStreets *)[CycleStreets sharedInstance:[CycleStreets class]];
	NSDictionary *settings = [cycleStreets.files settings];
	NSString *imageSize = [settings valueForKey:@"imageSize"];
	if ([imageSize isEqualToString:@"full"]) {
		self.addPhoto.imageData = [self.photoAsset fullData];
	} else {
		self.addPhoto.imageData = [self.photoAsset screenSizeData];
	}
	
	//time.
	NSDate *date = nil;
	date = [self.photoAsset date];
	if (date == nil) {
		//now
		date = [[[NSDate alloc] init] autorelease];
	}
	int delta = [[NSNumber numberWithDouble:[date timeIntervalSince1970]] intValue];
	NSString *time = [NSString stringWithFormat:@"%i", delta];
	self.addPhoto.time = time;
	
	sendInProgress = YES;
	[addPhoto runWithTarget:self onSuccess:@selector(didSucceedAddPhoto:results:) onFailure:@selector(didFailUserOp:withMessage:)];

	[self.sendingAlert show:@"Sending picture to Photomap.."];
	
}

- (IBAction) didCaption {
	DLog(@">>>");
	[self enableButtons:NO];
	self.captionText.hidden = NO;
	self.captionBar.hidden = NO;
	self.captionText.text = self.currentCaption;
	[self.captionText becomeFirstResponder];
}

- (IBAction) didCaptionDone {
	DLog(@">>>");
	[self.captionText resignFirstResponder];
	self.currentCaption = self.captionText.text;
}

- (IBAction) didCaptionCancel {
	DLog(@">>>");
	[self.captionText resignFirstResponder];
}

- (IBAction) didInfo {
	DLog(@">>>");
	if (photoInfo == nil) {
		self.photoInfo = [[[PhotoInfo alloc] initWithNibName:@"PhotoInfo" bundle:nil] autorelease];
	}
	[self enableButtons:YES];
	[self presentModalViewController:photoInfo animated:YES];
}

// Goes and gets a location with which to tag the image.
- (IBAction) didSend {
	if (username == nil || password == nil) {
		if (self.loginView == nil) {
			self.loginView = [[[LoginView alloc] initWithNibName:@"LoginView" bundle:nil] autorelease];
		}
		[self presentModalViewController:self.loginView animated:YES];
		self.loginView.loginDelegate = self; //we get the callback when login is requested.
	} else {
		[self sendPhoto];
	}
}

- (void)didAcknowledgeDelete {
	self.photoAsset = nil;
	self.photoAsset = nil;
	self.selected.image = nil;
	sendInProgress = NO;
	[self enableButtons:YES];	
}

- (IBAction) didDelete {
	DLog(@">>>");
	if (self.deleteAlert == nil) {
		self.deleteAlert = [[UIAlertView alloc] initWithTitle:@"CycleStreets"
													  message:@"Really don't use this photo ?"
													 delegate:self
											cancelButtonTitle:@"Cancel"
											otherButtonTitles:@"Don't Use", nil];
	}
	[self.deleteAlert show];
}

#pragma mark image picker delegate

//the hand-rolled asset picker has picked an asset. So we use that.
- (void)didNotificationLibraryAsset:(NSNotification *)libraryAssetNotification {
	if (libraryAssetNotification == nil) {
		return;
	}
	id object = [libraryAssetNotification object];
	if (object == nil) {
		//clear the asset in use.
		self.photoAsset = nil;
		DLog(@"asset cleared");
	} else if ([object isKindOfClass:[ALAsset class]]) {
		//new asset in use.
		self.photoAsset = [[[PhotoAsset alloc] initWithAsset:[libraryAssetNotification object]] autorelease];
		DLog(@"asset selected %@", self.photoAsset);
	}
	
	//get the image and state
	if (self.photoAsset == nil) {
		selected.image = nil;
	} else {
		selected.image = [self.photoAsset screenImage];
	}
	
	//fix the buttons, as we have an image.
	[self enableButtons:YES];
	
	//dismiss the custom asset picker.
	[self dismissModalViewControllerAnimated:YES];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)pickerToCancel {
	[pickerToCancel dismissModalViewControllerAnimated:YES];
}

void releaseJpegDataProvider(void *info,
							 const void *data,
							 size_t size) {
	DLog(@">>>");
}

//Save the image to the asset library, and then save the asset and its location.
- (void)saveCapturedImage:(UIImage *)image {
	ALAssetsLibrary *assetsLibrary = [[[ALAssetsLibrary alloc] init] autorelease];
	if (assetsLibrary == nil) {
		//sub 4.0, no assets library. Do the cleanup now.
		self.photoAsset = [[PhotoAsset alloc] initWithImage:image withCoordinate:self.location.coordinate];
		[self.picker dismissModalViewControllerAnimated:YES];	
		[self enableButtons:YES];
	}
	//Extract the data.
	//CGImageRef imageRef = [image CGImage]; - just yields a screen-size image.
	self.jpegData = UIImageJPEGRepresentation(image, 0.95);
	jpegDataProvider = CGDataProviderCreateWithData( self,
													[self.jpegData bytes],
													[self.jpegData length],
													&releaseJpegDataProvider);
	imageRef = CGImageCreateWithJPEGDataProvider(jpegDataProvider, nil, NO, kCGRenderingIntentDefault);
	
	ALAssetOrientation orientation = ALAssetOrientationUp;
	UIImageOrientation imageOrientation = [image imageOrientation];
	if (imageOrientation == UIImageOrientationRight) {
		orientation = ALAssetOrientationRight;
	} else if (imageOrientation == UIImageOrientationLeft) {
		orientation = ALAssetOrientationLeft;
	} else if (imageOrientation == UIImageOrientationDown) {
		orientation = ALAssetOrientationDown;
	}
		
	[assetsLibrary writeImageToSavedPhotosAlbum:imageRef
									orientation:orientation
								completionBlock:^(NSURL *assetURL, NSError *error) {
									if (error == nil) {
										[assetsLibrary assetForURL:assetURL
													   resultBlock:^(ALAsset *asset) {
														   self.photoAsset = [[[PhotoAsset alloc] initWithAsset:asset] autorelease];
														   [asset saveLocation:self.location.coordinate];
														   [self.picker dismissModalViewControllerAnimated:YES];	
														   [self enableButtons:YES];
														   
														   self.jpegData = nil;
														   CGDataProviderRelease(jpegDataProvider);
														   CGImageRelease(imageRef);
													   }
													  failureBlock:^(NSError *error) {
														  self.jpegData = nil;
														  CGDataProviderRelease(jpegDataProvider);
														  CGImageRelease(imageRef);
													  }];
									}
								}];
}

- (void)imagePickerController:(UIImagePickerController *)usedPicker
didFinishPickingMediaWithInfo:(NSDictionary *)pickingInfo {
	DLog(@"media picked.");
	selected.image = [pickingInfo valueForKey:UIImagePickerControllerOriginalImage];
	if (self.picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
		//save a new photo to the camera roll.
		//obsolete UIImageWriteToSavedPhotosAlbum(selected.image, nil, nil, nil);
		
		//save the image as an asset
		[self saveCapturedImage:[pickingInfo valueForKey:UIImagePickerControllerOriginalImage]];
	}
}

#pragma mark user validation delegate

- (void) didSucceedUserValidate:(XMLRequest *)request results:(NSDictionary *)elements {
	DLog(@">>>");
	[sendingAlert hide];
	[self dismissModalViewControllerAnimated:YES];
	NSArray *signins = [elements valueForKey:@"signin"];
	validated = nil;
	if (signins != nil) {
		NSDictionary *result = [signins objectAtIndex:0];
		validated = [[result valueForKey:@"username"] copy];
	}
	if (username != nil && password != nil && ![username isEqualToString:@""] && validated != nil &&![validated isEqualToString:@""]) {
		//OK, it got validated.
		[self saveUserPass];
		
		//And now we are ready to send the selected photo...
		[self sendPhoto];
	} else {
		[username release];
		[password release];
		[validated release];
		username = nil;
		password = nil;
		validated = nil;
		
		self.alert = [[UIAlertView alloc] initWithTitle:@"Cyclestreets"
												message:@"Username/password could not be validated"
											   delegate:self
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:nil];
		[alert show];
	}
}

- (void) didSucceedUserCreate:(XMLRequest *)xmlRequest results:(NSDictionary *)elements {
	DLog(@">>>");
	[sendingAlert hide];
	[self dismissModalViewControllerAnimated:YES];
	
	NSInteger code = 0;
	NSArray *codes = [elements valueForKey:@"code"];
	if (codes != nil && [codes isKindOfClass:[NSArray class]] && [codes count] > 0) {
		code = [[[codes objectAtIndex:0] valueForKey:@"code"] integerValue];
	}
	
	NSString *message = @"Unknown error when trying to create user account.";
	NSArray *messages = [elements valueForKey:@"message"];
	if (messages != nil && [messages isKindOfClass:[NSArray class]] && [messages count] > 0) {
		message = [[messages objectAtIndex:0] valueForKey:@"message"];
	}	
	BOOL ok = (code == 1);
	if (ok) {
		//Passed all the registration checks, it is "being" validated.
		[self saveUserPass];
		
		//And now we are ready to send the selected photo...
		self.emailAlert = [[UIAlertView alloc] initWithTitle:@"Cyclestreets"
													 message:message
													delegate:self
										   cancelButtonTitle:@"OK"
										   otherButtonTitles:nil];
		[self.emailAlert show];
	} else {
		[username release];
		[password release];
		[validated release];
		username = nil;
		password = nil;
		validated = nil;
		
		self.alert = [[UIAlertView alloc] initWithTitle:@"Cyclestreets"
												message:message
											   delegate:self
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:nil];
		[self.alert show];
	}
}

//first component after location e.g. http://www.cyclestreets.net/location/24361/
- (NSString *)cycleStreetsPhotoId:(NSString *)url {
	NSArray *parts = [url componentsSeparatedByString:@"/"];
	NSString *result = nil;
	BOOL use = NO;
	for (NSString *part in parts) {
		if (use) {
			result = [[part copy] autorelease];
		}
		use = NO;
		if ([part isEqualToString:@"location"]) {
			use = YES;
		}
	}
	return result;
}

- (void) didSucceedAddPhoto:(XMLRequest *)xmlRequest results:(NSDictionary *)elements {
	DLog(@">>>");
	[sendingAlert hide];
	self.photoAsset = nil;
	BOOL ok = YES;
	NSString *url;
	if ([elements count] != 1) {
		ok = NO;
	}
	if (ok) {
		NSDictionary *result = [[elements valueForKey:@"result"] objectAtIndex:0];
		url = [result valueForKey:@"url"];
		if (url == nil || [url isEqualToString:@""]) {
			ok = NO;
		}
		self.bigImageURL = [result valueForKey:@"thumbnailUrl"];
	}
	NSString *message;
	if (ok) {
		//Nice.
		self.photoId = [self cycleStreetsPhotoId:url];
		message = [NSString stringWithFormat:@"The photo has been uploaded as CycleStreets Photo #%@", self.photoId];
		self.alert = [[UIAlertView alloc] initWithTitle:@"CycleStreets"
												message:message
											   delegate:self
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:@"View", nil];				
	} else {
		message = [NSString stringWithString:@"Could not upload photo"];
		self.alert = [[UIAlertView alloc] initWithTitle:@"CycleStreets"
												message:message
											   delegate:self
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:nil];		
	}
	//turn off sendInProgress when we've acknowledged..
	[alert show];		
}

- (void) didFailUserOp:(XMLRequest *)request withMessage:(NSString *)message {
	DLog(@">>>");
	[sendingAlert hide];
	sendInProgress = NO;
	if (self.errorAlert == nil) {
		self.errorAlert = [[[UIAlertView alloc] initWithTitle:@"CycleStreets"
													 message:@"Could not obtain a response from CycleStreets.net. Please try again later."
													delegate:self
										   cancelButtonTitle:@"OK"
										   otherButtonTitles:nil]
						   autorelease];
		[self.errorAlert show];
	}
}

#pragma mark alert view delegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	DLog(@">>>");
	if (alertView == self.alert) {
		if (sendInProgress) {
			self.photoAsset = nil;
			self.selected.image = nil;
			self.photoInfo = nil;
			if (alertView.firstOtherButtonIndex == buttonIndex) {
				//View
				if (self.preview == nil) {
					self.preview = [[Location2 alloc] init];
				}
				PhotoEntry *photoEntry = [[[PhotoEntry alloc] init] autorelease];
				photoEntry.caption = self.currentCaption;
				photoEntry.bigImageURL = self.bigImageURL;
				photoEntry.csid = self.photoId;
				[self presentModalViewController:self.preview animated:YES];
				[self.preview performSelector:@selector(loadEntry:) withObject:(photoEntry) afterDelay:0.1];
			}
		}
		sendInProgress = NO;
		[self enableButtons:YES];
	}
	
	if (alertView == self.deleteAlert) {
		if (alertView.firstOtherButtonIndex == buttonIndex) {
			[self didAcknowledgeDelete];
		} else if (alertView.cancelButtonIndex == buttonIndex) {
			//Cancel the delete, do nothing.
		}
	}
	
	if (alertView == self.emailAlert) {
		[self sendPhoto];
	}
	
	if (alertView == self.errorAlert) {
		//nothing to do.
	}
}

#pragma mark loginDelegate

// Login has been requested. Save the password, because we need it.
// The username will come back in the response message, if everything is valid.
- (void)didLogin:(NSString *)loginUsername withPassword:(NSString *)loginPassword {
	DLog(@">>>");
	[password release];
	password = [loginPassword copy];
	[username release];
	username = [loginUsername copy];
	[validated release];
	validated = nil;
	
	[self.sendingAlert show:@"Logging in.."];
	self.userValidate = [[[UserValidate alloc] initWithUsername:loginUsername withPassword:loginPassword] autorelease];
	[self.userValidate runWithTarget:self
						   onSuccess:@selector(didSucceedUserValidate:results:)
						   onFailure:@selector(didFailUserOp:withMessage:)];
}

- (void)didRegister:(NSString *)loginUsername
	   withPassword:(NSString *)loginPassword
		  withEmail:(NSString *)email 
		   withName:(NSString *)visibleName{
	DLog(@">>>");
	password = [loginPassword copy];
	username = [loginUsername copy];
	
	[self.sendingAlert show:@"Registering user.."];
	self.userCreate = [[[UserCreate alloc] initWithUsername:loginUsername
											   withPassword:loginPassword
												  withEmail:email
												   withName:visibleName] autorelease];
	[self.userCreate runWithTarget:self
						 onSuccess:@selector(didSucceedUserCreate:results:)
						 onFailure:@selector(didFailUserOp:withMessage:)];
}

- (void)didCancel {
	DLog(@">>>");
	[self dismissModalViewControllerAnimated:YES];
}

#pragma mark location manager delegate

- (void)locationManager:(CLLocationManager *)manager
	didUpdateToLocation:(CLLocation *)newLocation
		   fromLocation:(CLLocation *)oldLocation
{
	DLog(@">>>");
	NSInteger horizontalAccuracy = [newLocation horizontalAccuracy];
	self.location = newLocation;
	accuracy.title = [NSString stringWithFormat:@"%dm", horizontalAccuracy];
}

- (void)locationManager:(CLLocationManager *)manager
	   didFailWithError:(NSError *)error
{
	DLog(@">>>");
}

#pragma mark view unload / release

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

- (void)nullify {
	[locationManager stopUpdatingLocation];
	self.selected = nil;
	self.camera = nil;
	self.library = nil;
	self.send = nil;
	self.caption = nil;
	self.info = nil;
	self.del = nil;
	self.accuracy = nil;
	self.toolbar = nil;
	self.photoToolbar = nil;
	self.captionText = nil;
	self.captionBar = nil;
	self.currentCaption = nil;
	
	self.loginView = nil;
	
	[locationManager release];
	self.location = nil;
	
	self.sendingAlert = nil;
	self.alert = nil;
	self.deleteAlert = nil;
	self.emailAlert = nil;
	self.errorAlert = nil;
	
	self.userValidate = nil;
	self.userCreate = nil;
	self.addPhoto = nil;
	self.photoInfo = nil;
	self.photoAction = nil;
	self.preview = nil;
	self.bigImageURL = nil;
	self.assetGroupTable = nil;
	self.photoAsset = nil;
	self.navigateLibrary = nil;
	self.picker = nil;
	self.photoId = nil;
	
	[username release];
	[password release];
	[validated release];	
}

- (void)viewDidUnload {
	[self nullify];
    [super viewDidUnload];
	DLog(@">>>");
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}


- (void)dealloc {
	[self nullify];
    [super dealloc];
}


@end
