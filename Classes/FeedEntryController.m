#import "FeedEntryController.h"
#import "RepositoryController.h"
#import "UserController.h"
#import "WebController.h"
#import "GHFeedEntry.h"
#import "GHUser.h"
#import "GHRepository.h"
#import "GHCommit.h"
#import "GHIssue.h"
#import "GravatarLoader.h"
#import "CommitController.h"
#import "IssueController.h"
#import "IssuesController.h"
#import "iOctocat.h"
#import "NSDate+Nibware.h"


@implementation FeedEntryController

@synthesize feed;
@synthesize entry;

- (id)initWithFeed:(GHFeed *)theFeed andCurrentIndex:(NSUInteger)theCurrentIndex {
	[super initWithNibName:@"FeedEntry" bundle:nil];
	currentIndex = theCurrentIndex;
	self.feed = theFeed;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (feed) self.navigationItem.rightBarButtonItem = controlItem;
	self.entry = [feed.entries objectAtIndex:currentIndex];
}

- (void)setEntry:(GHFeedEntry *)theEntry {
	if (theEntry == entry) return;
	[theEntry retain];
	[entry release];
	entry = theEntry;
	
	entry.read = YES;
	[entry.user addObserver:self forKeyPath:kUserGravatarKeyPath options:NSKeyValueObservingOptionNew context:nil];
	self.title = [entry.eventType capitalizedString];
	titleLabel.text = entry.title;
	NSString *feedEntry = [NSString stringWithFormat:@"<div class='feed_entry'>%@</div>", entry.content];
	NSString *formatPath = [[NSBundle mainBundle] pathForResource:@"format" ofType:@"html"];
	NSString *format = [NSString stringWithContentsOfFile:formatPath encoding:NSUTF8StringEncoding error:nil];
	NSString *html = [NSString stringWithFormat:format, feedEntry];
	[contentView loadHTMLString:html baseURL:nil];
	// Date
	dateLabel.text = [entry.date prettyDate];
	// Icon
	NSString *icon = [NSString stringWithFormat:@"%@.png", entry.eventType];
	iconView.image = [UIImage imageNamed:icon];
	// Gravatar
	gravatarView.image = entry.user.gravatar;
	if (!gravatarView.image && !entry.user.isLoaded) [entry.user loadUser];
	// Update Toolbar
	NSMutableArray *tbItems = [NSMutableArray arrayWithObjects:webItem, firstUserItem, nil];
	if ([entry.eventItem isKindOfClass:[GHUser class]]) {
		[tbItems addObject:secondUserItem];
	} else if ([entry.eventItem isKindOfClass:[GHRepository class]]) {
		[tbItems addObject:repositoryItem];
	} else if ([entry.eventItem isKindOfClass:[GHIssue class]]) {
		[tbItems addObject:repositoryItem];
		[tbItems addObject:issueItem];
	} else if ([entry.eventItem isKindOfClass:[GHCommit class]]) {
		[tbItems addObject:repositoryItem];
		[tbItems addObject:commitItem];
	}
	[toolbar setItems:tbItems animated:NO];
	// Update navigation control
	[navigationControl setEnabled:(currentIndex > 0) forSegmentAtIndex:0];
	[navigationControl setEnabled:(currentIndex < [feed.entries count]-1) forSegmentAtIndex:1];
}

- (void)dealloc {
	[contentView stopLoading];
	contentView.delegate = nil;
	[contentView release], contentView = nil;
	[toolbar release], toolbar = nil;
	[controlItem release], controlItem = nil;
	[webItem release], webItem = nil;
	[repositoryItem release], repositoryItem = nil;
	[firstUserItem release], firstUserItem = nil;
	[secondUserItem release], secondUserItem = nil;
	[issueItem release], issueItem = nil;
	[commitItem release], commitItem = nil;
	[navigationControl release], navigationControl = nil;
	[entry.user removeObserver:self forKeyPath:kUserGravatarKeyPath];
	[entry release], entry = nil;
	[dateLabel release], dateLabel = nil;
	[titleLabel release], titleLabel = nil;
	[iconView release], iconView = nil;
	[gravatarView release], gravatarView = nil;
	
    [super dealloc];
}

- (void)viewWillDisappear:(BOOL)animated {
	[contentView stopLoading];
	[super viewWillDisappear:animated];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:kUserGravatarKeyPath]) {
		gravatarView.image = entry.user.gravatar;
	}
}

#pragma mark Actions

- (IBAction)segmentChanged:(UISegmentedControl *)segmentedControl {
	currentIndex += (segmentedControl.selectedSegmentIndex == 0) ? -1 : 1;
	[entry.user removeObserver:self forKeyPath:kUserGravatarKeyPath];
	self.entry = [feed.entries objectAtIndex:currentIndex];
}

- (IBAction)showInWebView:(id)sender {
	WebController *webController = [[WebController alloc] initWithURL:entry.linkURL];
	[self.navigationController pushViewController:webController animated:YES];
	[webController release];
}

- (IBAction)showRepository:(id)sender {
	id item = entry.eventItem;
	GHRepository *repository = [item isKindOfClass:[GHIssue class]] ? [(GHIssue *)item repository] : item; 
	RepositoryController *repoController = [[RepositoryController alloc] initWithRepository:repository];
	[self.navigationController pushViewController:repoController animated:YES];
	[repoController release];
}

- (IBAction)showFirstUser:(id)sender {
	UserController *userController = [(UserController *)[UserController alloc] initWithUser:entry.user];
	[self.navigationController pushViewController:userController animated:YES];
	[userController release];
}

- (IBAction)showSecondUser:(id)sender {
	UserController *userController = [(UserController *)[UserController alloc] initWithUser:(GHUser *)entry.eventItem];
	[self.navigationController pushViewController:userController animated:YES];
	[userController release];
}

- (IBAction)showIssue:(id)sender {
	GHIssue *issue = entry.eventItem;
	IssueController *issueController = [[IssueController alloc] initWithIssue:issue andIssuesController:nil];
	[self.navigationController pushViewController:issueController animated:YES];
	[issueController release];
}

- (IBAction)showCommit:(id)sender {
	GHCommit *commit = entry.eventItem;
	CommitController *commitController = [[CommitController alloc] initWithCommit:commit];
	[self.navigationController pushViewController:commitController animated:YES];
	[commitController release];
}

#pragma mark WebView

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	if ([[[request URL] absoluteString] isEqualToString:@"about:blank"]) return YES;
	NSArray *pathComponents = [[[[request URL] relativePath] substringFromIndex:1] componentsSeparatedByString:@"/"];
	DJLog(@"Path: %@", pathComponents);
	if ([pathComponents containsObject:@"commit"]) {
		NSString *sha = [pathComponents lastObject];
		GHCommit *commit = [[GHCommit alloc] initWithRepository:(GHRepository *)entry.eventItem andCommitID:sha];
		CommitController *commitController = [[CommitController alloc] initWithCommit:commit];
		[self.navigationController pushViewController:commitController animated:YES];
		[commitController release];
		[commit release];
	} else if ([entry.eventItem isKindOfClass:[GHRepository class]] && [entry.content rangeOfString:@" is at"].location != NSNotFound) {
		NSString *owner = [pathComponents objectAtIndex:0];
		NSString *name = [pathComponents objectAtIndex:1];
		GHRepository *repo = [[GHRepository alloc] initWithOwner:owner andName:name];
		RepositoryController *repoController = [[RepositoryController alloc] initWithRepository:repo];
		[self.navigationController pushViewController:repoController animated:YES];
		[repoController release];
		[repo release];
	} else if ([pathComponents count] == 1) {
		NSString *username = [pathComponents objectAtIndex:0];
		GHUser *user = [[iOctocat sharedInstance] userWithLogin:username];
		UserController *userController = [(UserController *)[UserController alloc] initWithUser:user];
		[self.navigationController pushViewController:userController animated:YES];
		[userController release];
	}
	return NO;
}

@end
