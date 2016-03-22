/****************************************************************************
 *                                                                           *
 *  Copyright (C) 2014-2015 iBuildApp, Inc. ( http://ibuildapp.com )         *
 *                                                                           *
 *  This file is part of iBuildApp.                                          *
 *                                                                           *
 *  This Source Code Form is subject to the terms of the iBuildApp License.  *
 *  You can obtain one at http://ibuildapp.com/license/                      *
 *                                                                           *
 ****************************************************************************/

#import "mWebVC.h"
#import "functionLibrary.h"
#import "NSStringPunycodeAdditions.h"
#import "TBXML.h"

#import "reachability.h"
#import "GTMNSString+HTML.h"
#import "mWebVCBehaviour.h"

#import "navigationbar.h"
//#import "uiwidgets.h"//<uiwidgets/uiwidgets.h>
#import "uihboxlayout.h"//<uiwidgets/uihboxlayout.h>


#define webNavBarWidth             300.f
#define webNavBarHeight            44.f
#define webNavBarVerticalPadding   4.f
#define webNavBarHorizontalPadding 10.f


@implementation TWebView
@synthesize centerOnPage;

- (id)init
{
  self = [super init];
  if ( self )
  {
    self.centerOnPage = NO;
  }
  
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  
  if ( !self.centerOnPage )
    return;
  
    // try to align content
  for ( id subview in self.subviews )
    if ([[subview class] isSubclassOfClass: [UIScrollView class]])
    {
      UIScrollView *scView = (UIScrollView *)subview;
      CGSize sz = [scView contentSize];
      CGPoint offset = CGPointMake( (NSInteger)((sz.width  - self.frame.size.width ) / 2.f),
                                   (NSInteger)((sz.height - self.frame.size.height) / 2.f) );
      scView.contentOffset = offset;
      break;
    }
}

@end


static BOOL isVideoAlreadyDisplayed;
static UIView *currentView;

@interface mWebVCViewController()
{
  int starts, stops;
  UILabel *label;
}
@property(nonatomic, strong) UIButton *tbButton;
@property(nonatomic, strong) UIButton *bButton;
@property(nonatomic, strong) UIButton *fButton;
@property(nonatomic, strong) UIButton *srButton;
@property(nonatomic, strong) UIView   *tbView;
@property(nonatomic, assign) UIInterfaceOrientation supportedOrientation;
@property(nonatomic, assign) BOOL     tabBarIsHidden;

@property(nonatomic, strong) UIBarButtonItem *barItem;

/**
 *  Internet reachability
 */
@property (nonatomic, strong) Reachability    *internetReachable;

/**
 *  Presence or absence of network
 */
@property (nonatomic, assign) BOOL             bInet;
@end

@implementation mWebVCViewController
@synthesize tbButton=tbButton, srButton, fButton, bButton;
@synthesize internetReachable = _internetReachable;
@synthesize bInet;
@synthesize centerOnPage = _centerOnPage;
@synthesize webView;
@synthesize appName;
@synthesize URL;
@synthesize content;
@synthesize code;
@synthesize baseURL;
@synthesize widgetType;
@synthesize showLink;
@synthesize withoutTBar;
@synthesize showTBarOnNextStep, scalesPageToFitOnNextStep;
@synthesize scalable;
@synthesize prevScalable;
@synthesize allowChangeScale;
@synthesize supportedOrientation;
@synthesize reloadOnceWhenAppear;
@synthesize bNeedsReloadWhenAppear;
@synthesize showTabBar, tabBarIsHidden;

@synthesize behaviour = _behaviour;


#pragma mark - XML <data> parser
/**
 *  Special parser for processing original xml file
 *
 *  @param xmlElement_ XML node
 *  @param params_     Dictionary with module parameters
 */
+ (void)parseXML:(NSValue *)xmlElement_
     withParams:(NSMutableDictionary *)params_
{
  TBXMLElement element;
  [xmlElement_ getValue:&element];

  NSMutableArray *contentArray = [[[NSMutableArray alloc] init] autorelease];

  NSString *szTitle = @"";
  TBXMLElement *titleElement = [TBXML childElementNamed:@"title" parentElement:&element];
  if ( titleElement )
    szTitle = [TBXML textForElement:titleElement];
  
    // 1. adding a zero element to array
  [contentArray addObject:[NSDictionary dictionaryWithObject:szTitle ? szTitle : @"" forKey:@"title" ] ];
  
    // the next element in array will be a dictionary consisting of keys <content> or <src>
  TBXMLElement *contentElement = [TBXML childElementNamed:@"content" parentElement:&element];
  TBXMLElement *codeElement    = [TBXML childElementNamed:@"code" parentElement:&element];  // case for google calendar
  
  NSString *szContent = nil;
  NSString *szCode    = nil;
  NSString *szUrl     = nil;
  if ( contentElement )
  {
    szUrl     = [[TBXML valueOfAttributeNamed:@"src" forElement:contentElement] gtm_stringByUnescapingFromHTML];
    szContent = [TBXML textForElement:contentElement];
  }
  if ( codeElement )
  {
    szCode = [TBXML textForElement:codeElement];
  }

  NSString *szFacebookURL = nil;
  TBXMLElement *facebookElement = [TBXML childElementNamed:@"fbook_url" parentElement:&element];
  if ( facebookElement )
    szFacebookURL = [[TBXML textForElement:facebookElement] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  
  if ( [szFacebookURL length] )
    szUrl = szFacebookURL;
  
    // 2. adding content or reference to resource
  if ( [szUrl length] )
    [contentArray addObject:[NSDictionary dictionaryWithObject:szUrl forKey:@"src" ] ];
  else if ( [szContent length] )
    [contentArray addObject:[NSDictionary dictionaryWithObject:szContent forKey:@"content" ] ];
  else if ( [szCode length] )
    [contentArray addObject:[NSDictionary dictionaryWithObject:szCode forKey:@"code" ] ];
  
    // adding array to dictionary. Don't fill this dictionary with objects that do not support serialization!
  [params_ setObject:contentArray forKey:@"data"];
}

-(void)setCenterOnPage:(BOOL)centerOnPage_
{
  _centerOnPage = centerOnPage_;
  self.webView.centerOnPage = centerOnPage_;
}

#pragma mark -
#pragma mark  ModuleDataReceiverProtocol methods

- (void)setParams:(NSMutableDictionary *)params
{
  if ( params != nil )
  {
    NSArray *paramList = [params objectForKey:@"data"];
    if ( !paramList || ![paramList count] )
      return;
    
      // 1. The first element of the array is a dictionary with title
    [self.navigationItem setTitle:[[paramList objectAtIndex:0] objectForKey:@"title"]];
    self.widgetType = [params objectForKey:@"widgetType"];
    
    self.content = nil;
    self.appName = nil;
    self.URL     = nil;
    self.baseURL = [NSURL URLWithString:@""]; // URL scheme by default (http://)
    self.appName    = [params objectForKey:@"appName"];
    
      // 2. All other parameters are stored in the last element of array
    
    self.URL        = [[paramList lastObject] objectForKey:@"src"];
    self.content    = [[paramList lastObject] objectForKey:@"content"];
    self.code       = [[paramList lastObject] objectForKey:@"code"];
    
    if ( self.URL && [self.URL length] )
      self.scalable   = YES;
    
    self.scalesPageToFitOnNextStep = YES;
  }
}

- (NSString*)getWidgetTitle
{
  if ( !self.widgetType )
    return @"HTML";
  if ( [self.widgetType isEqualToString:@"Html"] )
    return @"HTML";
  else if ( [self.widgetType isEqualToString:@"Calendar"] )
    return @"Calendar";
  else if ( [self.widgetType isEqualToString:@"googleform"] )
    return @"GoogleForm";
  else if ( [self.widgetType isEqualToString:@"News"] )
    return @"News";
  else
    return @"HTML";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if ( self )
  {
    self.bInet         = NO;
    self.centerOnPage = NO;
    self.webView    = nil;
    self.widgetType = nil;
    self.baseURL    = [NSURL URLWithString:@""];
    self.content    = nil;
    self.URL        = nil;
    self.tbButton   = nil;
    self.srButton   = nil;
    self.bButton    = nil;
    self.fButton    = nil;
    self.tbView     = nil;
    self.code       = nil;
    self.reloadOnceWhenAppear      = NO;
    self.scalesPageToFitOnNextStep = NO;
    self.bNeedsReloadWhenAppear    = YES;
    self.showTabBar                = YES;  // show tabBar by default
    self.tabBarIsHidden            = NO;
    
    self.internetReachable = nil;
    self.behaviour         = nil;
    self.supportedOrientation = UIInterfaceOrientationMaskAll;
    
    starts = 0;
    stops = 0;
  }
  return self;
}

- (void)dealloc
{
  if ( observerForEnterFullscreen )
  {
    [[NSNotificationCenter defaultCenter] removeObserver:observerForEnterFullscreen];
    observerForEnterFullscreen = nil;
  }
  if ( observerForExitFullscreen )
  {
    [[NSNotificationCenter defaultCenter] removeObserver:observerForExitFullscreen];
    observerForExitFullscreen = nil;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  self.appName    = nil;
	self.URL        = nil;
  self.widgetType = nil;
  self.content    = nil;
  self.baseURL    = nil;
  self.tbButton   = nil;
  self.srButton   = nil;
  self.bButton    = nil;
  self.fButton    = nil;
  self.tbView     = nil;
  self.code       = nil;
  
  self.behaviour = nil;
  
  [self.internetReachable stopNotifier];
  self.internetReachable = nil;
  
  webView.delegate = nil;
  self.webView.delegate = nil;
  [self.webView stopLoading];
  self.webView = nil;
  
  self.barItem = nil;
  
  [super dealloc];
}

#pragma mark -
#pragma mark VIEW LIFECYCLE

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.navigationController.navigationBar.translucent = NO;
  self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
  
  [self.view setBackgroundColor:[UIColor clearColor]];
  
  self.webView.dataDetectorTypes = UIDataDetectorTypeAll;
  
    // Starting notification system for the presence / absence of a network connection
  self.internetReachable = [Reachability reachabilityForInternetConnection];
  [self.internetReachable startNotifier];
  
  
    // Adding observer for network status and video fullscreen events
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(checkNetworkStatus:)
                                               name:kReachabilityChangedNotification
                                             object:nil];
  
  
  observerForExitFullscreen = [[NSNotificationCenter defaultCenter]
                               addObserverForName:@"UIMoviePlayerControllerWillExitFullscreenNotification"
                               object:nil
                               queue:nil
                               usingBlock:^(NSNotification *note) {

                                 if (isVideoAlreadyDisplayed && self.navigationController.view == currentView)
                                 {
                                   self.navigationController.view.hidden = false;
                                   isVideoAlreadyDisplayed = NO;
                                 }
                               }];
  
  observerForEnterFullscreen = [[NSNotificationCenter defaultCenter]
                                addObserverForName:@"UIMoviePlayerControllerDidEnterFullscreenNotification"
                                object:nil
                                queue:nil
                                usingBlock:^(NSNotification *note) {
                                  
                                  if (!isVideoAlreadyDisplayed && !self.navigationController.view.hidden) {
                                    self.navigationController.view.hidden = true;
                                    isVideoAlreadyDisplayed = YES;
                                    currentView = self.navigationController.view;
                                  }
                                }];
  self.withoutTBar = YES;
  self.showTBarOnNextStep = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self.navigationItem setHidesBackButton:NO animated:NO];
  [self.navigationController setNavigationBarHidden:NO animated:animated];
  [[self.navigationController navigationBar] setBarStyle:UIBarStyleDefault];
  [[self.navigationController navigationBar] setOpaque  :YES];
  [[self.navigationController navigationBar] setAlpha   :1.f];
  
    // before hiding / displaying tabBar we must remember its previous state
  self.tabBarIsHidden = [[self.tabBarController tabBar] isHidden];
  [[self.tabBarController tabBar] setHidden:!self.showTabBar];
  
  if ( self.bNeedsReloadWhenAppear )
    [self reload];
  
   // task 4018
   //if ( self.reloadOnceWhenAppear )
    self.bNeedsReloadWhenAppear = NO;
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  
    // restore tabBar state
  [[self.tabBarController tabBar] setHidden:self.tabBarIsHidden];
  
  if ( !withoutTBar ) {
    [self hideTBButton];
  }
  
  [self.webView stopLoading];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
  return self.supportedOrientation && (1 << interfaceOrientation);
}

- (BOOL)shouldAutorotate
{
  return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
  return self.supportedOrientation;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
  return UIInterfaceOrientationPortrait;
}

#pragma mark -
#pragma mark WEBVIEW EVENTS

- (BOOL)           webView:(UIWebView *)webView_
shouldStartLoadWithRequest:(NSURLRequest *)request
            navigationType:(UIWebViewNavigationType)navigationType
{
    // fix for google form: don't change webview settings when user clicks on links
  if ([self.widgetType isEqualToString:@"googleform"])
  {
    self.showTBarOnNextStep = NO;
    return YES;
  }
  
  if([request.URL.scheme isEqual:@"mailto"]) {
    NSArray *address = [NSArray arrayWithObjects:[request.URL.absoluteString stringByReplacingOccurrencesOfString:@"mailto:" withString:@""], nil];
    [functionLibrary callMailComposerWithRecipients:address
                                         andSubject:self.showLink ? NSBundleLocalizedString(@"mWeb_sentFromiBuildApp", @"Sent from iBuildApp") : nil
                                            andBody:@""
                                             asHTML:YES
                                     withAttachment:nil
                                           mimeType:@""
                                           fileName:@""
                                     fromController:self
                                           showLink:self.showLink];
    return NO;
  }
  
    // open links to PayPal in Safari - it's a requirement of "some kind of fruit company" )
  if ([request.URL.host isEqualToString:@"www.paypal.com"])
  {
    NSString *szLink = [request.URL absoluteString];
    if ( [request.HTTPBody length] )
    {
      NSString *str = [[[NSString alloc] initWithData:request.HTTPBody
                                             encoding:NSUTF8StringEncoding] autorelease];
      szLink = [szLink stringByAppendingFormat:@"?%@", str ];
      szLink = [szLink stringByAppendingString:@"&bn=ibuildapp_SP"];
    }
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:szLink]];

    return NO;
  }
  
    // Perform custom behaviour for link clicked
  if ( self.behaviour )
  {
    if ( ![self.behaviour webView:webView_
       shouldStartLoadWithRequest:request
                   navigationType:navigationType] )
      return NO;
  }
  
  prevScalable = scalable;
  
  if ( allowChangeScale && !isReloading && [[[request.URL pathExtension] lowercaseString] isEqualToString:@"pdf"] )
  {
    // prevScalable = scalable;
    scalable = YES;
    self.webView.scalesPageToFit = YES;
  }
  if ( self.scalesPageToFitOnNextStep && (loadsCount > 0)
      && ![[request.URL absoluteString] isEqualToString:@"about:blank"] ) // scalesPageToFit = NO for html pages
  {
    scalable = YES;
    [self.webView setScalesPageToFit:YES];
  }
  
  if ( loadsCount == 0 )
  {
    loadsCount++;
  }
  
  if ( !withoutTBar
      && ((navigationType == UIWebViewNavigationTypeLinkClicked) || (navigationType == UIWebViewNavigationTypeFormSubmitted)) )
    [self.srButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_stop")]
                   forState:UIControlStateNormal];
  
  return YES;
}

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)composeResult
                        error:(NSError *)error
{
  [self dismissModalViewControllerAnimated:YES];
}


- (void)webViewDidStartLoad:(UIWebView *)webView
{
  starts++;
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
}

- (void)webViewDidFinishLoad:(UIWebView *)_webView
{
  stops++;
  
  // perform javaScript function ibuildapp_getAppName(), if it exists:
  NSString *functionAvailable = [_webView stringByEvaluatingJavaScriptFromString:@"typeof ibuildapp_getAppName === 'function'"];
  if ( functionAvailable && [[functionAvailable lowercaseString] isEqualToString:@"true"] )
    [_webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"ibuildapp_getAppName(\'%@\');", self.appName]];
  
  [self stopLoadingIndication];
  
  if ( !withoutTBar || (showTBarOnNextStep && (loadsCount > 0)) )
    [self setButtonsState];
  
  if ( isReloading )
    isReloading = NO;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
  [self stopLoadingIndication];
  if ( !withoutTBar )
    [self setButtonsState];
  
  if ( isReloading )
    isReloading = NO;
}

#pragma mark -
#pragma mark BUTTONS EVENTS

- (void)bButtonClicked:(id)sender
{
  if ( [self webView].canGoBack )
    [self.webView goBack];

  
  if (!prevScalable)
  {
    scalable = NO; //  make setter for "scalable", change there value for webView.scalesPageToFit
    self.webView.scalesPageToFit = NO;
    [self reload];
  }
  
  [self hideTBar];
}

- (void)srButtonClicked:(id)sender
{
  if ( [self webView].loading )
  {
    [self.webView stopLoading];
    [self.srButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_reload")] forState:UIControlStateNormal];
  }
  else
  {
    NSURL *url = self.webView.request.URL;
    if ( url )
    {
      if ( [url.absoluteString isEqualToString:@"about:blank"] )
      {
        NSString *szContent = nil;
        
        if ( self.content )
          szContent = self.content;
        else if ( self.code )
          szContent = self.code;
        
        [self processContentAndModifyBaseUrlIfNeeded:szContent];
        
        if ( szContent )
          [self.webView loadHTMLString:szContent
                               baseURL:self.baseURL];
      }
      else
        [self.webView loadRequest:self.webView.request];
      
      isReloading = YES;
    }
    
    [self.srButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_stop")] forState:UIControlStateNormal];
  }
  [self hideTBar];
}

- (void)fButtonClicked:(id)sender
{
  if ( [self webView].canGoForward )
    [self.webView goForward];

  [self hideTBar];
}

#pragma mark -
#pragma mark UI BEHAVIOR

- (void)setButtonsState
{
  if(showTBarOnNextStep && (loadsCount > 0))
  {
    withoutTBar = NO;
    if ( !self.tbButton )
      [self showTBButton];
  }
  
    // display the back button on the iPad if it was previously hidden. Or hide it if we were on the first page of the module (ie, we are located on the second page of navigation stack)
  if ( [[self.navigationController viewControllers] indexOfObject:self] < 2 )
  {
    if ( [[self.navigationController navigationBar] isKindOfClass:[TNavigationBar class]] )
      [((TNavigationBar *)[self.navigationController navigationBar]) setBackButtonHidden:(!self.webView.canGoBack) animated:YES];
  }
  
  self.bButton.enabled = self.webView.canGoBack;
  self.fButton.enabled = self.webView.canGoForward;
}

- (void)stopLoadingIndication
{
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
  [self.srButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_reload")] forState:UIControlStateNormal];
}

/**
 *  Adding navigation buttons to navigation bar.
 *  The method is used exclusively for iPad version of application
 *
 *  @param button_ UIView* button_
 */
- (void)installNavigationButton:(UIView *)button_
{
  if ( ![self.navigationController.navigationBar isKindOfClass:[TNavigationBar class]] )
    return;
  
  TNavigationBar *navBar = (TNavigationBar *)self.navigationController.navigationBar;
  uiRootWidget *pRootWidget = [[navBar subviews] objectAtIndex:0];
  NSMutableArray *widgets = [[[NSMutableArray alloc] initWithArray:pRootWidget.layout.subWidgets copyItems:YES] autorelease];
  uiWidgetData *wd = [[[uiWidgetData alloc] init] autorelease];
  wd.type = @"WebViewNavigationButton";
  wd.view = button_;
  wd.size = button_.frame.size;
  wd.margin = MarginMake(0, 10.f, 0, 0);
  wd.relSize = WidgetSizeMake(NO, NO);
  wd.align   = WidgetAlignmentCenter;
  [widgets addObject:wd];
  [pRootWidget.layout clear];
  for ( uiWidgetData *widget in widgets )
    [pRootWidget.layout addWidget:widget];
  [pRootWidget addSubview:button_];
  [pRootWidget setNeedsLayout];
}


- (void) showTBButton
{
//  if (!withoutTBar && !self.tbButton)
//  {
//    self.tbButton = [UIButton buttonWithType:UIButtonTypeCustom];
//    
//    self.tbButton.frame = CGRectMake(0, 0, 36.f, 28.f);
//    
//    self.tbButton.autoresizesSubviews = YES;
//    self.tbButton.autoresizingMask    = UIViewAutoresizingFlexibleLeftMargin |
//    UIViewAutoresizingFlexibleTopMargin  |
//    UIViewAutoresizingFlexibleBottomMargin;
//    
//    if([[[UIDevice currentDevice] systemVersion] compare:@"7.0" options:NSNumericSearch] != NSOrderedAscending)
//    {
//      [self.tbButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_arrow")] forState:UIControlStateNormal];
//    }
//    else
//    {
//      [self.tbButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_aup")] forState:UIControlStateNormal];
//      
//      [self.tbButton setBackgroundColor:[UIColor blackColor]];
//      
//      [self.tbButton layer].cornerRadius = 4.0f;
//      [self.tbButton layer].borderWidth  = 1.0f;
//    }
//    
//    [self.tbButton layer].borderColor  = [UIColor whiteColor].CGColor;
//    
//    [self.tbButton addTarget:self
//                      action:@selector(show_hide_TBar)
//            forControlEvents:UIControlEventTouchUpInside];
//    
//    // if application is running on smartphone, we'll add navigation button on the top right of navigation bar (as custom rightBarButton)
//    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone )
//    {
//      //respect the hamburger case
//      NSMutableArray *rightBarButtonItems = [[self.navigationItem.rightBarButtonItems mutableCopy] autorelease];
//      
//      [rightBarButtonItems removeObject:self.barItem];
//      
//      if(!rightBarButtonItems)
//      {
//        rightBarButtonItems = [NSMutableArray array];
//      }
//      
//      self.barItem = [[[UIBarButtonItem alloc] initWithCustomView:self.tbButton] autorelease];
//      
//      [rightBarButtonItems addObject:self.barItem];
//      
//      [self.navigationItem setRightBarButtonItems:rightBarButtonItems animated:NO];
//    }else
//    {
//      // application is running on iPad. Add button to navigation panel
//      [self installNavigationButton:self.tbButton];
//    }
//  }
}

- (void)hideTBButton
{
//  if ( self.tbButton )
//  {
//    [self.tbButton removeFromSuperview];
//    self.tbButton = nil;
//  }
}

- (void)show_hide_TBar
{
  if ( TBarHidden )
  {
    [self showTBar];
    [self.srButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_reload")] forState:UIControlStateNormal];
  } else {
    [self hideTBar];
  }
}

- (void)showTBar
{
  [self.tbView   removeFromSuperview];
  [self.bButton  removeFromSuperview];
  [self.srButton removeFromSuperview];
  [self.fButton  removeFromSuperview];
  
  self.tbView = [[[UIView alloc] init] autorelease];
  
  [self.tbView setBackgroundColor:[UIColor blackColor]];
  [self.tbView setAlpha:0.7f];
  
  [self.tbView layer].cornerRadius = 5.0f;
  [self.tbView layer].borderWidth = 1.0f;
  [self.tbView layer].borderColor = [UIColor whiteColor].CGColor;
  
  self.bButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.bButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_back")]  forState:UIControlStateNormal];
  
  [self.bButton addTarget:self action:@selector(bButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
  
  [self.tbView addSubview:self.bButton];
  
  self.srButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.srButton setTitleShadowColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
  
  [self.srButton addTarget:self action:@selector(srButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
  
  [self.tbView addSubview:self.srButton];
  
  
  self.fButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.fButton setImage:[UIImage imageNamed:resourceFromBundle(@"mWebVC_forward")]  forState:UIControlStateNormal];
  
  [self.fButton addTarget:self
                   action:@selector(fButtonClicked:)
         forControlEvents:UIControlEventTouchUpInside];
  
  [self.tbView addSubview:self.fButton];
  
  self.bButton.frame  = CGRectMake( 0.0f  , 1.0f, 100.0f, 42.0f);
  self.srButton.frame = CGRectMake( 100.0f, 1.0f, 100.0f, 42.0f);
  self.fButton.frame  = CGRectMake( 200.0f, 1.0f, 100.0f, 42.0f);
  
    // activate / deactivate reload button on toolbar
  [self.srButton setEnabled:self.bInet];
  
  [self.webView addSubview:self.tbView];
  
  [self.tbView setFrame:CGRectMake( self.view.bounds.size.width, webNavBarVerticalPadding, webNavBarWidth, webNavBarHeight )];
  self.tbView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
  
  [UIView beginAnimations:nil context:nil];
  [UIView setAnimationDuration:0.5f];
  
  [self.tbView setFrame:CGRectMake( self.view.bounds.size.width - (webNavBarHorizontalPadding + webNavBarWidth),
                                   webNavBarVerticalPadding,
                                   webNavBarWidth,
                                   webNavBarHeight )];
  
  [self.tbButton setTransform:CGAffineTransformRotate(CGAffineTransformMakeScale(-1.0, 1.0), -M_PI)];
  [UIView commitAnimations];
  
  [self.navigationController.navigationBar bringSubviewToFront:self.tbButton];
  
  TBarHidden = NO;
  
  [self setButtonsState];
}

- (void)hideTBar
{
  [UIView animateWithDuration:0.5f animations:^{
    [self.tbView setFrame:CGRectMake( self.view.bounds.size.width, webNavBarVerticalPadding, webNavBarWidth, webNavBarHeight )];
    self.tbView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
    [self.tbButton setTransform:CGAffineTransformMakeRotation(0)];
  } completion:^(BOOL finished) {
    [self.view bringSubviewToFront:self.tbButton];
    TBarHidden = YES;
  }];
}

- (void)setInputTitle:(NSString *)inputTitle
{
  self.title = inputTitle;
}

- (void)setBaseURLfromString:(NSString *) strBaseURL
{
  NSURL *url = [NSURL URLWithString:strBaseURL];
  
  if (!strBaseURL)
    return;
  
  self.baseURL = [NSURL URLWithString: [NSString stringWithFormat: @"%@://%@", url.scheme, url.host]];
}

- (void)reload
{
  [self checkNetworkStatus:nil];
  
  if ( !self.webView )
  {
    self.webView = [[[TWebView alloc] initWithFrame:self.view.bounds] autorelease];
  }
  else
  {
    [self.webView stopLoading];
    self.webView.delegate = nil;
    [self.webView removeFromSuperview];
    self.webView = [[[TWebView alloc] initWithFrame:self.view.bounds] autorelease];
  }
  
  [self.webView setBackgroundColor:[UIColor clearColor]];
  
//  [self hideTBButton];
  
  self.webView.delegate = self;
  self.webView.autoresizesSubviews = YES;
  self.webView.autoresizingMask =  UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  
  self.webView.scalesPageToFit = scalable ? YES : NO;
  self.webView.centerOnPage = self.centerOnPage;
  
  [self.view addSubview:self.webView];
  loadsCount = 0;
  
  if ( withoutTBar != YES )
    withoutTBar = NO;
  TBarHidden = YES;
  
  if (self.URL != nil)
  {
    NSURLRequest *szURLRequest = [self prepareSzUrlRequest];
      // check network connection before open link
    if ( self.bInet )
      [self.webView loadRequest:szURLRequest];
    else
    {
        // show alert
      UIAlertView *noNetwork = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"general_cellularDataTurnedOff",@"Cellular Data is Turned off")
                                                           message:NSLocalizedString(@"general_cellularDataTurnOnMessage",@"Turn on cellular data or use Wi-Fi to access data")
                                                          delegate:nil
                                                 cancelButtonTitle:NSLocalizedString(@"general_defaultButtonTitleOK",@"OK")
                                                 otherButtonTitles:nil] autorelease];
      [noNetwork show];
    }
  }
  else if (self.content != nil)
  {
    [self processContentAndModifyBaseUrlIfNeeded:self.content];
    
    [self.webView loadHTMLString:self.content
                         baseURL:self.baseURL];
  }
  else if ( self.code != nil )
  {
    
    if ([self.widgetType isEqualToString:@"googleform"])
    {
      NSString *srcAttrValue = nil;
      NSError   *xmlError = nil;
      TBXML *tbxml = [[TBXML newTBXMLWithXMLString:self.code
                                             error:&xmlError] autorelease];
      TBXMLElement *rootElement = [tbxml rootXMLElement];
      if ( rootElement && [[[TBXML elementName:rootElement] lowercaseString] isEqualToString:@"iframe"] )
      {
        TBXMLAttribute *attr = rootElement->firstAttribute;
        while( attr )
        {
          if ( [[[TBXML attributeName:attr] lowercaseString] isEqualToString:@"src"] )
          {
            srcAttrValue = [TBXML attributeValue:attr];
            break;
          } else {
            attr = attr->next;
          }
        }
      }
      
      if (srcAttrValue)
      {
        self.URL = srcAttrValue;
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.URL]]];
      }
      else
      {
        NSLog(@"Can not find src attribute!");
      }
    }
    else
    {
        // change width and height for iframe
      NSError   *xmlError = nil;
      NSMutableString  *htmlFrame = [NSMutableString stringWithString:@"<html><meta name=\"viewport\" content=\"width=320\"/><head></head><body style=\"margin:0; padding:0\"><div>"];
      BOOL      bHasHeight = NO;
      BOOL      bHasWidth = NO;
      TBXML *tbxml = [[TBXML newTBXMLWithXMLString:self.code
                                             error:&xmlError] autorelease];
      TBXMLElement *rootElement = [tbxml rootXMLElement];
      if ( rootElement && [[[TBXML elementName:rootElement] lowercaseString] isEqualToString:@"iframe"] )
      {
        [htmlFrame appendString:@"<iframe scrolling=\"no\""];
        
        TBXMLAttribute *attr = rootElement->firstAttribute;
        while( attr )
        {
          [htmlFrame appendString:@" "];
          [htmlFrame appendString:[TBXML attributeName:attr]];
          
          
          NSString *attrValue = [TBXML attributeValue:attr];
          if ( [[[TBXML attributeName:attr] lowercaseString] isEqualToString:@"width"] )
          {
            bHasWidth = YES;
            attrValue = [NSString stringWithFormat:@"%.0f", self.webView.bounds.size.width];
              //            attrValue = @"100%";
          }
          else if ( [[[TBXML attributeName:attr] lowercaseString] isEqualToString:@"height"] )
          {
            bHasHeight = YES;
            attrValue = [NSString stringWithFormat:@"%.0f", self.webView.bounds.size.height];
              //            attrValue = @"100%";
          }
          [htmlFrame appendFormat:@"=\"%@\"", attrValue];
          attr = attr->next;
        }
        if ( !bHasHeight )
        {
            //          htmlFrame = [htmlFrame stringByAppendingFormat:@" height=\"%.0f\"", self.webView.bounds.size.height ];
          [htmlFrame appendString:@" height=\"400\"" ];
        }
        if ( !bHasWidth )
        {
            //          htmlFrame = [htmlFrame stringByAppendingFormat:@" width=\"%.0f\"", self.webView.bounds.size.width];
          [htmlFrame appendString:@" width=\"300\"" ];
        }
        [htmlFrame appendString:@"></iframe>"];
      }
      [htmlFrame appendString:@"</div></body></html>"];
      
      self.code = htmlFrame;
      self.webView.scalesPageToFit = YES; //scale nicely
      [self.webView setContentMode:UIViewContentModeScaleAspectFit];

      self.supportedOrientation = UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
      
      [self.webView loadHTMLString:htmlFrame
                           baseURL:nil];
      
    }
  
    
  }
  [self showTBButton];
}

#pragma mark -
#pragma mark checkNetworkStatus

/**
 *  Check connection notification callback
 *
 *  @param notice NSNotification* notice
 */
- (void)checkNetworkStatus:(NSNotification *)notice
{
  NetworkStatus internetStatus = [self.internetReachable currentReachabilityStatus];
  self.bInet = internetStatus != NotReachable;
  [self.srButton setEnabled:self.bInet];
}


-(void)processContentAndModifyBaseUrlIfNeeded:(NSString *)contentToProcess
{
  if ([self.content rangeOfString:@"www.powr.io/powr.js"].location != NSNotFound) {
    [self setBaseURLfromString:@"http://www.powr.io"];
  }
  
  //workaround for а bug(?), where javascript required itself to be loaded with current "//" protocol only
  //and refused to load with our default @"http://" baseURL
  static NSString *currentProtocolPattern = @"\\s*src\\s*=\\s*('|\")\\s*\\/\\/";
  
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:currentProtocolPattern options:0 error:NULL];
  if([regex firstMatchInString:contentToProcess options:0 range:NSMakeRange(0, contentToProcess.length)]){
    [self setBaseURLfromString:@"http://localhost/"];
  }
}

-(NSURLRequest*)prepareSzUrlRequest
{
  NSURL *url = [NSURL URLWithString:self.URL];
  NSString *host = [url.host lowercaseString];
  
  if(host.length)
  {
    self.URL = [self.URL stringByReplacingOccurrencesOfString:url.host withString:host];
  } else {
    self.URL = url.absoluteString;
  }
  
  NSString *szURL = [[self.URL encodedURLString]
                     stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  
  NSURLRequest *szURLRequest = nil;
  
  //User complained that online chat could not be loaded after the first attempt.
  //Second (third and so on) time you open the Web Widget you get cached artifact.
  if ([self.URL rangeOfString:@"rumbletalk.net"].location != NSNotFound) {
    szURLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:szURL]];
    
    //Remove cached response. Note this is only a half-measure, works fine on iOS6,
    //but loads chat only at 1st, 3rd, 5th... attempt on iOS7+.
    //Probably some UIWebView caching bug.
    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:szURLRequest];
  } else {
    //Chat URL encoded string had # sign replaced with %23 and the chat could not be opened because of that too.
    //So we do the raplacement only in other cases
    
    //AddingPercentEscapes already done in method "encodedURLString"
    //szURL = [szURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    szURLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:szURL]];
  }
  
  return szURLRequest;
}

@end