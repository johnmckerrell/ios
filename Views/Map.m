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

//  Map.m
//  CycleStreets
//
//  Created by Alan Paxton on 02/03/2010.
//

#import "Common.h"
#import "Map.h"
#import "RMMapLayer.h"
#import "RMMarker.h"
#import "RMMarkerManager.h"
#import "Query.h"
#import "CycleStreets.h"
#import "CycleStreetsAppDelegate.h"
#import "BusyAlert.h"
#import "Route.h"
#import "Segment.h"
#import <CoreLocation/CoreLocation.h>
#import "RMCloudMadeMapSource.h"
#import "RMOpenStreetMapSource.h"
#import "RMOpenCycleMapSource.h"
#import "RMTileSource.h"
#import "RMCachedTileSource.h"
#import "PhotoList.h"
#import "PhotoEntry.h"
#import "QueryPhoto.h"
#import "Markers.h"
#import "Namefinder2.h"
#import "RMMapView.h"
#import "CSPoint.h"
#import "RouteLineView.h"
#import "RMMercatorToScreenProjection.h"
#import "Files.h"
#import "Favourites.h"
#import "InitialLocation.h"
#import "CustomButtonView.h"

@implementation Map

static NSString *MAPPING_BASE_OPENCYCLEMAP = @"OpenCycleMap (with hills)";
static NSString *MAPPING_BASE_OSM = @"OpenStreetMap map design";

static NSString *MAPPING_ATTRIBUTION_OPENCYCLEMAP = @"(c) OpenStreetMap and contributors, CC-BY-SA; Map images (c) OpenCycleMap";
static NSString *MAPPING_ATTRIBUTION_OSM = @"(c) OpenStreetMap and contributors, CC-BY-SA";

static NSInteger MAX_ZOOM = 18;
static NSInteger MIN_ZOOM = 1;

static NSInteger MAX_ZOOM_LOCATION = 16;
static NSInteger MAX_ZOOM_LOCATION_ACCURACY = 200;

//handle when to switch off the GPS, and at what accuracy.
static CLLocationDistance LOC_DISTANCE_FILTER = 25;
static CLLocationAccuracy ACCURACY_OK = 100;
static CLLocationAccuracy ACCURACY_BEST = 20;
static NSTimeInterval LOC_OFF_DELAY_BAD = 30.0;
static NSTimeInterval LOC_OFF_DELAY_OK = 3.0;
static NSTimeInterval LOC_OFF_DELAY_BEST = 1.0;

static NSTimeInterval ACCIDENTAL_TAP_DELAY = 1.0;

//don't allow co-location of start/finish
static CLLocationDistance MIN_START_FINISH_DISTANCE = 100;

@synthesize locationButton;
@synthesize activeLocationButton;
@synthesize activeLocationView;
@synthesize toolBar;
@synthesize nameButton;
@synthesize routeButton;
@synthesize deleteButton;
@synthesize attributionLabel;
@synthesize mapView;
@synthesize lineView;
@synthesize blueCircleView;
@synthesize start;
@synthesize end;
@synthesize firstAlert;
@synthesize clearAlert;
@synthesize startFinishAlert;
@synthesize noLocationAlert;
@synthesize planningState;
@synthesize programmaticChange;

+ (NSArray *)mapStyles {
	return [NSArray arrayWithObjects:MAPPING_BASE_OSM, MAPPING_BASE_OPENCYCLEMAP, nil];
}

+ (NSString *)currentMapStyle {
	CycleStreets *cycleStreets = (CycleStreets *)[CycleStreets sharedInstance:[CycleStreets class]];
	NSDictionary *settings = [cycleStreets.files settings];
	NSString *mapStyle = [settings valueForKey:@"mapStyle"];
	if (mapStyle == nil) {
		mapStyle = [[Map mapStyles] objectAtIndex:0];
	}

	return mapStyle;
}

+ (NSString *)mapAttribution {
	NSString *mapStyle = [Map currentMapStyle];
	NSString *mapAttribution = nil;
	if ([mapStyle isEqualToString:MAPPING_BASE_OSM]) {
		mapAttribution = MAPPING_ATTRIBUTION_OSM;
	} else if ([mapStyle isEqualToString:MAPPING_BASE_OPENCYCLEMAP]) {
		mapAttribution = MAPPING_ATTRIBUTION_OPENCYCLEMAP;
	}
	return mapAttribution;
}

+ ( NSObject <RMTileSource> *)tileSource {
	NSString *mapStyle = [Map currentMapStyle];
	NSObject <RMTileSource> *tileSource;
	if ([mapStyle isEqualToString:MAPPING_BASE_OSM])
	{
		tileSource = [[[RMOpenStreetMapSource alloc] init] autorelease];
	}
	/*
	else if ([mapStyle isEqualToString:MAPPING_BASE_CLOUDMADE])
	{
		tileSource = [[[RMCloudMadeMapSource alloc] initWithAccessKey:CLOUDMADE_ACCESS_KEY
														  styleNumber:CLOUDMADE_CYCLE_STYLE]
					  autorelease];
	}
	 */
	else if ([mapStyle isEqualToString:MAPPING_BASE_OPENCYCLEMAP])
	{
		//open cycle map
		tileSource = [[[RMOpenCycleMapSource alloc] init] autorelease];
	}
	else
	{
		//default to MAPPING_BASE_OSM.
		tileSource = [[[RMOpenStreetMapSource alloc] init] autorelease];
	}
	return tileSource;
}

+ (void)zoomMapView:(RMMapView *)mapView toLocation:(CLLocation *)newLocation {
	CLLocationAccuracy accuracy = newLocation.horizontalAccuracy;
	if (accuracy < 0) {
		accuracy = 2000;
	}
	int wantZoom = MAX_ZOOM_LOCATION;
	CLLocationAccuracy wantAccuracy = MAX_ZOOM_LOCATION_ACCURACY;
	while (wantAccuracy < accuracy) {
		wantZoom--;
		wantAccuracy = wantAccuracy * 2;
	}
	DLog(@"accuracy %f zoom %d", accuracy, wantZoom);
	[mapView moveToLatLong: newLocation.coordinate];
	[mapView.contents setZoom:wantZoom];
}

- (id)init {
	if (self = [super init]) {
		firstTimeStart = YES;
		firstTimeFinish = YES;
	}
	return self;
}

- (void)logState {
	switch (self.planningState) {
		case stateStart:
			NSLog(@"stateStart");
			break;
		case stateEnd:
			NSLog(@"stateEnd");
			break;
		case stateLocatingStart:
			NSLog(@"stateLocatingStart");
			break;
		case stateLocatingEnd:
			NSLog(@"stateLocatingEnd");
			break;
		case statePlan:
			NSLog(@"statePlan");
			break;
		case stateRoute:
			NSLog(@"stateRoute");
			break;
	}
}

- (void)gotoState:(PlanningState)newPlanningState {
	
	NSLog(@"gotoState... before");
	[self logState];

	self.planningState = newPlanningState;
	
	NSLog(@"gotoState... after");
	[self logState];
	
	switch (self.planningState) {
		case stateStart:
			DLog(@"stateStart");
			self.routeButton.title = @"Set start";
			self.routeButton.style = UIBarButtonItemStylePlain;
			self.routeButton.enabled = NO;
			self.deleteButton.enabled = NO;
			self.nameButton.enabled = YES;
			break;
		case stateLocatingStart:
			DLog(@"stateLocatingStart");
			self.routeButton.title = @"Locating..";
			self.routeButton.style = UIBarButtonItemStylePlain;
			self.routeButton.enabled = NO;
			self.deleteButton.enabled = NO;
			self.nameButton.enabled = NO;
			break;
		case stateEnd:
			DLog(@"stateEnd");
			self.routeButton.title = @"Set finish";
			self.routeButton.enabled = NO;
			self.routeButton.style = UIBarButtonItemStylePlain;
			self.deleteButton.enabled = YES;
			self.nameButton.enabled = YES;
			break;
		case stateLocatingEnd:
			DLog(@"stateLocatingEnd");
			self.routeButton.title = @"Locating..";
			self.routeButton.enabled = NO;
			self.routeButton.style = UIBarButtonItemStylePlain;
			self.deleteButton.enabled = YES;
			self.nameButton.enabled = NO;
			break;
		case statePlan:
			DLog(@"statePlan");
			self.routeButton.title = @"Plan route!";
			self.routeButton.enabled = YES;
			self.routeButton.style = UIBarButtonItemStyleDone;
			self.deleteButton.enabled = YES;
			self.nameButton.enabled = NO;
			break;
		case stateRoute:
			DLog(@"stateRoute");
			self.routeButton.title = @"New route";
			self.routeButton.enabled = YES;
			self.routeButton.style = UIBarButtonItemStyleBordered;
			self.deleteButton.enabled = NO;
			self.nameButton.enabled = NO;
			break;
	}
}

- (void) clearMarkers {
	if ([[mapView.markerManager markers] containsObject:self.end]) {
		[mapView.markerManager removeMarker:self.end];
	}
	if ([[mapView.markerManager markers] containsObject:self.start]) {
		[mapView.markerManager removeMarker:self.start];
	}
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
	DLog(@">>>");
	
	self.mapView.hidden = YES;
	
	self.activeLocationView = [[[CustomButtonView alloc] initWithImage:[UIImage imageNamed:@"74-location.png"]
																target:self
															  selector:@selector(didActiveLocation)]
								autorelease];
	self.activeLocationView.animationImages = [NSArray arrayWithObjects:
											   [UIImage imageNamed:@"white_arrow_0.png"],
											   [UIImage imageNamed:@"white_arrow_45.png"],
											   [UIImage imageNamed:@"white_arrow_90.png"],
											   [UIImage imageNamed:@"white_arrow_135.png"],
											   [UIImage imageNamed:@"white_arrow_180.png"],
											   [UIImage imageNamed:@"white_arrow_225.png"],
											   [UIImage imageNamed:@"white_arrow_270.png"],
											   [UIImage imageNamed:@"white_arrow_315.png"],
											   nil];
	self.activeLocationView.animationDuration = 2.0;
	self.activeLocationButton = [[[UIBarButtonItem alloc] initWithCustomView:self.activeLocationView] autorelease];
	self.activeLocationButton.style	= UIBarButtonItemStyleBordered;
	
	self.locationButton = [[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"74-location.png"]
															style:UIBarButtonItemStyleBordered
														   target:self
														   action:@selector(didLocation)]
						   autorelease];
	self.locationButton.width = 26;
	
	NSMutableArray *items = [NSMutableArray arrayWithArray:self.toolBar.items];
	[items insertObject:self.locationButton atIndex:0];
	self.toolBar.items = items;
	
	cycleStreets = (CycleStreets *)[CycleStreets sharedInstance:[CycleStreets class]];
	[cycleStreets retain];
	
	//Don't do the first time alert if we've already planned a route.
	if (firstTimeStart || firstTimeFinish) {
		NSMutableDictionary *misc = [NSMutableDictionary dictionaryWithDictionary:[cycleStreets.files misc]];
		if ([misc objectForKey:@"experienced"] != nil) {
			firstTimeStart = NO;
			firstTimeFinish = NO;
		}
	}
	
	if (firstTimeStart || firstTimeFinish) {
		self.firstAlert = [[[UIAlertView alloc]
							initWithTitle:@"CycleStreets"
							message:nil
							delegate:self
							cancelButtonTitle:nil
							otherButtonTitles:nil] autorelease];	
	}
	
	self.clearAlert = [[[UIAlertView alloc]
						initWithTitle:@"CycleStreets"
						message:@"Clear current route ?"
						delegate:self
						cancelButtonTitle:@"Cancel"
						otherButtonTitles:@"OK", nil] autorelease];
	
	//Necessary to start route-me service
	[RMMapView class];
	
	//get the configured map source.
	[[[RMMapContents alloc] initWithView:mapView tilesource:[Map tileSource]] autorelease];

	
	// Initialize
	[mapView setDelegate:self];
	if (initialLocation == nil) {
		initialLocation = [[InitialLocation alloc] initWithMapView:mapView withController:self];
	}
	[initialLocation performSelector:@selector(query) withObject:nil afterDelay:0.0];
	
	//clear up from last run.
	[self clearMarkers];
	
	//provide the points the line overlay needs, when it needs them, in screen co-ordinates
	[lineView setPointListProvider:self];
	
	[blueCircleView setLocationProvider:self];
	
	//set up the location manager.
	locationManager = [[CLLocationManager alloc] init];
	doingLocation = NO;
	
	self.programmaticChange = NO;
	NSLog(@"programmatic <-- NO");
	avoidAccidentalTaps = NO;
	
	self.attributionLabel.text = [Map mapAttribution];
	
	[self gotoState:stateStart];

	NSString *selectedRoute = [cycleStreets.files miscValueForKey:@"selectedroute"];
	if (selectedRoute != nil) {
		Route *useRoute = [cycleStreets.appDelegate.favourites routeWithIdentifier:[selectedRoute intValue]];
		[cycleStreets.appDelegate selectRoute:useRoute];
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didNotificationMapStyleChanged)
												 name:@"NotificationMapStyleChanged"
											   object:nil];	
	
	
	DLog(@"<<<");
}

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

/*
- (void) beforeMapMove: (RMMapView*) map {
}
*/

- (void) didNotificationMapStyleChanged {
	mapView.contents.tileSource = [Map tileSource];
	self.attributionLabel.text = [Map mapAttribution];
}

- (void) cancelAvoidAccidentalTaps {
	avoidAccidentalTaps = NO;
}

- (void) afterMapChanged: (RMMapView*) map {
	[lineView setNeedsDisplay];
	[blueCircleView setNeedsDisplay];
	
	if (!self.programmaticChange) {
		DLog(@"afterMapChanged, autolocating=NO, [self stopDoingLocation]");
		if (self.planningState == stateLocatingStart || self.planningState == stateLocatingEnd) {
			[self stopDoingLocation];
		}
		avoidAccidentalTaps = YES;
		[self performSelector:@selector(cancelAvoidAccidentalTaps) withObject:nil afterDelay:ACCIDENTAL_TAP_DELAY];
	} else {
		DLog(@"afterMapChanged, autolocating=YES");
	}
}

- (void) afterMapMove: (RMMapView*) map {
	[self afterMapChanged:map];
}

/*
- (void) beforeMapZoom: (RMMapView*) map byFactor: (float) zoomFactor near:(CGPoint) center {
}
 */

- (void) afterMapZoom: (RMMapView*) map byFactor: (float) zoomFactor near:(CGPoint) center {
	[self afterMapChanged:map];
}

- (void)saveLocation:(CLLocationCoordinate2D)location {
	NSMutableDictionary *misc = [NSMutableDictionary dictionaryWithDictionary:[cycleStreets.files misc]];
	[misc setValue:[NSString stringWithFormat:@"%f", location.latitude] forKey:@"latitude"];
	[misc setValue:[NSString stringWithFormat:@"%f", location.longitude] forKey:@"longitude"];
	[cycleStreets.files setMisc:misc];	
}

- (BOOL)locationInBounds:(CLLocationCoordinate2D)location {
	CGRect bounds = mapView.contents.screenBounds;
	CLLocationCoordinate2D nw = [mapView pixelToLatLong:bounds.origin];
	CLLocationCoordinate2D se = [mapView pixelToLatLong:CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height)];
	
	if (nw.latitude < location.latitude) return NO;
	if (nw.longitude > location.longitude) return NO;
	if (se.latitude > location.latitude) return NO;
	if (se.longitude < location.longitude) return NO;
	
	return YES;
}

- (void)cancelAlert:(UIAlertView *)alert {
	DLog(@">>>");
	[alert dismissWithClickedButtonIndex:0 animated:YES];
}

- (void) firstAlert:(NSString *)message {
	self.firstAlert.message = message;
	[self.firstAlert show];
	[self performSelector:@selector(cancelAlert:) withObject:self.firstAlert afterDelay:2.0];
}

- (void) showStartFinishAlert {
	if (self.startFinishAlert == nil) {
		self.startFinishAlert = [[[UIAlertView alloc] initWithTitle:@"CycleStreets"
															message:@"Move the map to set a finish point further away."
														   delegate:self
												  cancelButtonTitle:nil
												  otherButtonTitles:nil]
								 autorelease];
	}
	[self stopDoingLocation];
	[self.startFinishAlert show];
	[self performSelector:@selector(cancelAlert:) withObject:self.startFinishAlert afterDelay:2.0];
}

- (CLLocationDistance) distanceFromStart:(CLLocationCoordinate2D)locationLatLon {
	CLLocationCoordinate2D fromLatLon = [[mapView markerManager] latitudeLongitudeForMarker:start];
	CLLocation *from = [[[CLLocation alloc] initWithLatitude:fromLatLon.latitude
												   longitude:fromLatLon.longitude] autorelease];
	CLLocation *to = [[[CLLocation alloc] initWithLatitude:locationLatLon.latitude
												 longitude:locationLatLon.longitude] autorelease];
	CLLocationDistance distance = [from getDistanceFrom:to];
	return distance;
}

- (void) startMarker:(CLLocationCoordinate2D)location {
	if (!self.start) {
		self.start = [Markers markerStart];
	}
	if ([[self.mapView.markerManager markers] containsObject:self.start]) {
		[self.mapView.markerManager moveMarker:self.start AtLatLon:location];
	} else {
		[self.mapView.markerManager addMarker:self.start AtLatLong:location];
	}
}

- (void) endMarker:(CLLocationCoordinate2D)location {
	if (!self.end) {
		self.end = [Markers markerEnd];
	}
	if ([[self.mapView.markerManager markers] containsObject:self.end]) {
		[self.mapView.markerManager moveMarker:self.end AtLatLon:location];
	} else {
		[self.mapView.markerManager addMarker:self.end AtLatLong:location];
	}
}

// Use stateXXX and the existence of a marker, to decide whether we should be moving the marker,
// or adding a new one.
- (void) addLocation:(CLLocationCoordinate2D)location {
	NSLog(@"addLocation");
	
	//end is too near start, and is being done by autolocation.
	if (self.programmaticChange && self.planningState == stateLocatingEnd) {
		CLLocationDistance distanceFromStart = [self distanceFromStart:location];
		if (distanceFromStart < MIN_START_FINISH_DISTANCE) {
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showStartFinishAlert) object:nil];
			[self performSelector:@selector(showStartFinishAlert) withObject:nil afterDelay:2.0];
			return;
		}
	}
	
	//explicit click while autolocation was happening. Turn off auto, accept click.
	if (!self.programmaticChange) {
		if (self.planningState == stateLocatingEnd || self.planningState == stateLocatingStart) {
			[self performSelector:@selector(stopDoingLocation) withObject:nil afterDelay:0.0];
		}
	}
	
	//endpoint, whether autolocated or not.
	if (self.planningState == stateEnd || self.planningState == stateLocatingEnd) {
		[self endMarker:location];
		if (firstTimeFinish) {
			//[self firstAlert:@"Finish point (F) set."];
			[self performSelector:@selector(firstAlert:) withObject:@"Finish point (F) set." afterDelay:0.5];
			firstTimeFinish = NO;
		}
		if (self.planningState == stateEnd) {
			[self gotoState:statePlan];
		}		
	}
	
	//startpoint, whether autolocated or not.
	if (self.planningState == stateStart || self.planningState == stateLocatingStart) {
		[self startMarker:location];
		if (firstTimeStart) {
			[self performSelector:@selector(firstAlert:) withObject:@"Start point (S) set." afterDelay:0.5];
			firstTimeStart = NO;
		}
		if (self.planningState == stateStart) {
			[self gotoState:stateEnd];
		}
	}
	
	[self saveLocation:location];
}

- (void) singleTapOnMap: (RMMapView*) map At: (CGPoint) point {
	DLog(@"singletap");
	if (!avoidAccidentalTaps) {
		CLLocationCoordinate2D location = [map pixelToLatLong:point];
		[self addLocation:location];
	} else {
		DLog(@"avoided accidental tap.");
	}
}

- (BOOL) mapView:(RMMapView *)map shouldDragMarker:(RMMarker *)marker withEvent:(UIEvent *)event {
	DLog(@"shoulddrag");
	if (marker == start || marker == end) {
		return YES;
	}
	return NO;
}
 
- (void) mapView:(RMMapView *)map didDragMarker:(RMMarker *)marker withEvent:(UIEvent *)event {
	DLog(@"dragafter");
	NSSet *touches = [event touchesForView:map];
	for (UITouch *touch in touches) {
		CGPoint point = [touch locationInView:map];
		CLLocationCoordinate2D location = [map pixelToLatLong:point];
		[[map markerManager] moveMarker:marker AtLatLon:location];
	}
}

/*
- (void) afterMapTouch: (RMMapView*) map {
	DLog(@"after");
}
 */

#pragma mark toolbar actions

- (void)zoomUpdate {
	[lineView setNeedsDisplay];
	[blueCircleView setNeedsDisplay];
	[self stopDoingLocation];
}

- (IBAction) didZoomIn {
	DLog(@"zoomin");
	if ([mapView.contents zoom] < MAX_ZOOM) {
		[mapView.contents setZoom:[mapView.contents zoom] + 1];
	}
	[self zoomUpdate];
}

- (IBAction) didZoomOut {
	DLog(@"zoomout");
	if ([mapView.contents zoom] > MIN_ZOOM) {
		[mapView.contents setZoom:[mapView.contents zoom] - 1];
	}
	[self zoomUpdate];
}

- (void) didLocation {
	[self startDoingLocation];
}

- (void) didActiveLocation {
	[self stopDoingLocation];
}

- (IBAction) didSearch {
	DLog(@"search");
	if (namefinder == nil) {
		namefinder = [[Namefinder2 alloc] initWithNibName:@"Namefinder2" bundle:nil];
	}
	namefinder.locationReceiver = self;
	namefinder.centreLocation = [[mapView contents] mapCenter];
	[self presentModalViewController:namefinder	animated:YES];
}

//delete the last point, either start or end.
- (IBAction) didDelete {
	
	RMMarkerManager *markerManager = [mapView markerManager];

	if ([[markerManager markers] containsObject:self.end]) {
		[markerManager removeMarker:self.end];
		[self gotoState:stateEnd];
	} else {
		[markerManager removeMarker:self.start];
		[self gotoState:stateStart];
	}
}

- (IBAction) didRoute {
	DLog(@"route");
	
	if (self.planningState == statePlan) {
		RMMarkerManager *markerManager = [mapView markerManager];
		if (![[markerManager markers] containsObject:self.end] || ![[markerManager markers] containsObject:self.start]) {
			DLog(@"not enough locations.");
			[cycleStreets.appDelegate.errorAlert setMessage:@"Need start and end markers to calculate a route."];
			[cycleStreets.appDelegate.errorAlert show];
		}
		
		CLLocationCoordinate2D fromLatLon = [markerManager latitudeLongitudeForMarker:start];
		CLLocation *from = [[[CLLocation alloc] initWithLatitude:fromLatLon.latitude longitude:fromLatLon.longitude] autorelease];
		CLLocationCoordinate2D toLatLon = [markerManager latitudeLongitudeForMarker:end];
		CLLocation *to = [[[CLLocation alloc] initWithLatitude:toLatLon.latitude longitude:toLatLon.longitude] autorelease];
		Query *query = [[[Query alloc] initFrom:from to:to] autorelease];
		[cycleStreets.appDelegate runQuery:query];
	} else if (self.planningState == stateRoute) {
		[self.clearAlert show];
	}
}

#pragma mark utility

// all the things that need fixed if we have asked (or been forced) to stop doing location.
- (void)stopDoingLocation {
	DLog(@">>>");
	if (!doingLocation) {
		DLog(@"not! doing location.");
	}
	if (doingLocation) {
		DLog(@"doing location. stop.");
		doingLocation = NO;
		locationButton.style = UIBarButtonItemStyleBordered;
		[locationManager stopUpdatingLocation];
		blueCircleView.hidden = YES;
		
		[self.activeLocationView stopAnimating];
		NSMutableArray *items = [NSMutableArray arrayWithArray:self.toolBar.items];
		[items removeObjectAtIndex:0];
		[items insertObject:self.locationButton atIndex:0];
		self.toolBar.items = items;
		
		//Don't affect the state if we "just wanted to know our location".
		if (self.planningState == statePlan || self.planningState == stateRoute) {
			return;
		}
		
		//We used the location to find an endpoint, so now tidy up the state.
		if (self.planningState == stateLocatingEnd) {
			if (self.end) {
				[self gotoState:statePlan];
			} else {
				[self gotoState:stateEnd];
			}
		}
		
		if (self.planningState == stateLocatingStart) {
			if (self.start) {
				[self gotoState:stateEnd];
			} else {
				[self gotoState:stateStart];
			}
		}
	}
}

// all the things that need fixed if we have asked (or been forced) to start doing location.
- (void)startDoingLocation {
	if (!doingLocation) {
		doingLocation = YES;
		locationButton.style = UIBarButtonItemStyleDone;
		locationManager.delegate = self;
		locationManager.distanceFilter = LOC_DISTANCE_FILTER;
		[locationManager startUpdatingLocation];
		blueCircleView.hidden = NO;
		
		[self.activeLocationView startAnimating];
		NSMutableArray *items = [NSMutableArray arrayWithArray:self.toolBar.items];
		[items removeObjectAtIndex:0];
		[items insertObject:self.activeLocationButton atIndex:0];
		self.toolBar.items = items;
		
		if (self.planningState == stateStart) {
			[self gotoState:stateLocatingStart];
		}
		if (self.planningState == stateEnd) {
			[self gotoState:stateLocatingEnd];
		}
	}
}

- (void) clearRoute {
	route = nil;
	[self clearMarkers];
	[self stopDoingLocation];
	
	[lineView setNeedsDisplay];
	[blueCircleView setNeedsDisplay];
	
	[self gotoState:stateStart];
}

- (void) newRoute {
	[mapView zoomWithLatLngBoundsNorthEast:(CLLocationCoordinate2D)[route northEast]
								 SouthWest:(CLLocationCoordinate2D)[route southWest]];
	
	[self clearMarkers];
	[self stopDoingLocation];
	
	CLLocationCoordinate2D startLocation = [[route segmentAtIndex:0] segmentStart];
	[self startMarker:startLocation];
	CLLocationCoordinate2D endLocation = [[route segmentAtIndex:[route numSegments] - 1] segmentEnd];
	[self endMarker:endLocation];
	
	[lineView setNeedsDisplay];
	[blueCircleView setNeedsDisplay];
	[self gotoState:stateRoute];
}

// A new route has successfully been calculated.
// Plot it, and replace the current stuff.
- (void) showRoute:(Route *)newRoute {
	[newRoute retain];
	[route release];
	route = newRoute;
	
	if (route == nil || [route numSegments] == 0) {
		[self clearRoute];
	} else {
		[self newRoute];
	}
}

// List of points in display co-ordinates for the route highlighting.
+ (NSArray *) pointList:(Route *)route withView:(RMMapView *)mapView {
	
	NSMutableArray *points = [[[NSMutableArray alloc] initWithCapacity:10] autorelease];
	if (route == nil) {
		return points;
	}
	
	for (int i = 0; i < [route numSegments]; i++) {
		if (i == 0)
		{	// start of first segment
			CSPoint *p = [[[CSPoint alloc] init] autorelease];
			Segment *segment = [route segmentAtIndex:i];
			CLLocationCoordinate2D coordinate = [segment segmentStart];
			CGPoint pt = [mapView.contents latLongToPixel:coordinate];
			p.p = pt;
			[points addObject:p];			
		}
		// remainder of all segments
		Segment *segment = [route segmentAtIndex:i];
		NSArray *allPoints = [segment allPoints];
		for (int i = 1; i < [allPoints count]; i++) {
			CSPoint *latlon = [allPoints objectAtIndex:i];
			CLLocationCoordinate2D coordinate;
			coordinate.latitude = latlon.p.y;
			coordinate.longitude = latlon.p.x;
			CGPoint pt = [mapView.contents latLongToPixel:coordinate];
			CSPoint *screen = [[[CSPoint alloc] init] autorelease];
			screen.p = pt;
			[points addObject:screen];
		}
	}	
	/*
	for (int i = 0; i < [route numSegments]; i++) {
		if (i == 0)
		{	// start of first segment
			CSPoint *p = [[[CSPoint alloc] init] autorelease];
			Segment *segment = [route segmentAtIndex:i];
			CGPoint pt = [mapView.contents latLongToPixel:[segment segmentStart]];
			p.p = pt;
			[points addObject:p];			
		}
		// end of all segments
		CSPoint *p = [[[CSPoint alloc] init] autorelease];
		Segment *segment = [route segmentAtIndex:i];
		CGPoint pt = [mapView.contents latLongToPixel:[segment segmentEnd]];
		p.p = pt;
		[points addObject:p];
	}
	 */
	return points;
}

- (NSArray *) pointList {
	return [Map pointList:route withView:mapView];
}

#pragma mark handle alert dismissal

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (alertView == self.clearAlert) {
		if (buttonIndex == self.clearAlert.cancelButtonIndex) {
			//Cancelled. Keep state the same.
		} else {
			//OK
			[cycleStreets.appDelegate selectRoute:nil];
		}

	}
	
	if (alertView == self.noLocationAlert) {
		[self stopDoingLocation];
	}
}

#pragma mark location provider

- (float)getX {
	CGPoint p = [mapView.contents latLongToPixel:lastLocation.coordinate];
	return p.x;
}

- (float)getY {
	CGPoint p = [mapView.contents latLongToPixel:lastLocation.coordinate];
	return p.y;
}

- (float)getRadius {
	double metresPerPixel = [mapView.contents metersPerPixel];
	return (lastLocation.horizontalAccuracy / metresPerPixel);
}

#pragma mark location delegate

- (void)locationManager:(CLLocationManager *)manager
	didUpdateToLocation:(CLLocation *)newLocation
		   fromLocation:(CLLocation *)oldLocation
{
	DLog(@">>>");

	//so that callee can decide the context.
	self.programmaticChange = YES;
	DLog(@"programmaticChange <-- YES");
	
	//turn off geolocation automatically in 10s if we're already within 100 metres, in 1s if within 20
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stopDoingLocation) object:nil];
	NSTimeInterval delay = LOC_OFF_DELAY_BAD;
	if (newLocation.horizontalAccuracy < ACCURACY_OK) {
		delay = LOC_OFF_DELAY_OK;
	}
	if (newLocation.horizontalAccuracy < ACCURACY_BEST) {
		delay = LOC_OFF_DELAY_BEST;
	}
	DLog(@"accuracy %f, delay %f", newLocation.horizontalAccuracy, delay);
	[self performSelector:@selector(stopDoingLocation) withObject:nil afterDelay:delay];
	
	//carefully replace the location.
	CLLocation *oldLastLocation = lastLocation;
	[newLocation retain];
	lastLocation = newLocation;
	[oldLastLocation release];
	
	[Map zoomMapView:mapView toLocation:newLocation];
	[self addLocation:newLocation.coordinate];
	[blueCircleView setNeedsDisplay];
	
	self.programmaticChange = NO;
}

- (void)locationManager:(CLLocationManager *)manager
	   didFailWithError:(NSError *)error
{
	if (self.noLocationAlert == nil) {
		self.noLocationAlert = [[[UIAlertView alloc] initWithTitle:@"CycleStreets"
														   message:@"Unable to retrieve location."
														  delegate:self
												 cancelButtonTitle:@"OK"
												 otherButtonTitles:nil]
								autorelease];
	}
	[self.noLocationAlert show];
}

#pragma mark search response

- (void) didMoveToLocation:(CLLocationCoordinate2D)location {
	NSLog(@"didMoveToLocation");
	[mapView moveToLatLong: location];
	[self addLocation:location];
	[lineView setNeedsDisplay];
	[blueCircleView setNeedsDisplay];
	[self stopDoingLocation];
}

#pragma mark generic class cleanup

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

- (void)nullify {
	self.locationButton = nil;
	self.activeLocationButton = nil;
	self.activeLocationView = nil;
		
	self.nameButton = nil;
	self.routeButton = nil;
	self.deleteButton = nil;
	
	self.attributionLabel = nil;
	
	[cycleStreets release];
	cycleStreets = nil;
	[mapView release];
	mapView = nil;
	
	self.lineView = nil;
	self.blueCircleView = nil;
	
	[locationManager release];
	locationManager = nil;
	[lastLocation release];
	lastLocation = nil;
	
	[namefinder release];
	namefinder = nil;
	[route release];
	route = nil;
	
	[initialLocation release];
	initialLocation = nil;
	
	self.firstAlert = nil;
	self.clearAlert = nil;
	self.startFinishAlert = nil;
	
	[self clearMarkers];
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
