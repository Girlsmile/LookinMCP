//
//  LKMCPStatusPopoverController.m
//  Lookin
//

#import "LKMCPStatusPopoverController.h"
#import "LKMCPHostManager.h"

@interface LKMCPStatusPopoverController ()

@property(nonatomic, strong) NSTextField *statusValueLabel;
@property(nonatomic, strong) NSTextField *summaryLabel;
@property(nonatomic, strong) NSTextField *addressValueLabel;
@property(nonatomic, strong) NSTextField *snapshotValueLabel;
@property(nonatomic, strong) NSTextField *requestValueLabel;
@property(nonatomic, strong) NSTextField *errorValueLabel;
@property(nonatomic, strong) NSButton *toggleButton;
@property(nonatomic, strong) NSButton *refreshButton;
@property(nonatomic, strong) NSButton *reconnectButton;

@end

@implementation LKMCPStatusPopoverController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 250)];
    self.view.wantsLayer = YES;

    NSStackView *stackView = [[NSStackView alloc] initWithFrame:self.view.bounds];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeading;
    stackView.spacing = 10;
    [self.view addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14],
        [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [stackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-14]
    ]];

    NSTextField *titleLabel = [self _label:@"Lookin MCP"];
    titleLabel.font = [NSFont boldSystemFontOfSize:14];
    [stackView addArrangedSubview:titleLabel];

    self.statusValueLabel = [self _label:@""];
    [stackView addArrangedSubview:self.statusValueLabel];

    self.summaryLabel = [self _wrapLabel:@""];
    [stackView addArrangedSubview:self.summaryLabel];

    self.addressValueLabel = [self _wrapLabel:@""];
    [stackView addArrangedSubview:[self _rowWithTitle:@"地址" valueLabel:self.addressValueLabel]];

    self.snapshotValueLabel = [self _wrapLabel:@""];
    [stackView addArrangedSubview:[self _rowWithTitle:@"Snapshot" valueLabel:self.snapshotValueLabel]];

    self.requestValueLabel = [self _wrapLabel:@""];
    [stackView addArrangedSubview:[self _rowWithTitle:@"最近请求" valueLabel:self.requestValueLabel]];

    self.errorValueLabel = [self _wrapLabel:@""];
    [stackView addArrangedSubview:[self _rowWithTitle:@"最近错误" valueLabel:self.errorValueLabel]];

    NSStackView *buttonsRow = [[NSStackView alloc] init];
    buttonsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonsRow.spacing = 10;

    self.toggleButton = [NSButton buttonWithTitle:@"启动" target:self action:@selector(_handleToggle)];
    self.toggleButton.bezelStyle = NSBezelStyleRounded;
    [buttonsRow addArrangedSubview:self.toggleButton];

    self.refreshButton = [NSButton buttonWithTitle:@"刷新状态" target:self action:@selector(_handleRefresh)];
    self.refreshButton.bezelStyle = NSBezelStyleRounded;
    [buttonsRow addArrangedSubview:self.refreshButton];

    self.reconnectButton = [NSButton buttonWithTitle:@"重连" target:self action:@selector(_handleReconnect)];
    self.reconnectButton.bezelStyle = NSBezelStyleRounded;
    [buttonsRow addArrangedSubview:self.reconnectButton];

    NSButton *copyButton = [NSButton buttonWithTitle:@"复制地址" target:self action:@selector(_handleCopy)];
    copyButton.bezelStyle = NSBezelStyleRounded;
    [buttonsRow addArrangedSubview:copyButton];

    [stackView addArrangedSubview:buttonsRow];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_render) name:LKMCPHostManagerDidUpdateNotification object:nil];
    [self _render];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)contentSize {
    return NSMakeSize(360, 250);
}

#pragma mark - Private

- (void)_render {
    LKMCPHostManager *manager = [LKMCPHostManager sharedInstance];

    NSMutableAttributedString *status = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"● %@", manager.statusText]];
    [status addAttribute:NSForegroundColorAttributeName value:manager.statusColor range:NSMakeRange(0, status.length)];
    [status addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13] range:NSMakeRange(0, status.length)];
    self.statusValueLabel.attributedStringValue = status;

    self.summaryLabel.stringValue = manager.statusSummaryText ?: @"";
    self.addressValueLabel.stringValue = manager.serverAddress ?: @"-";
    self.snapshotValueLabel.stringValue = manager.capturedAtText.length > 0 ? manager.capturedAtText : (manager.snapshotAvailable ? @"-" : @"无可用 snapshot");
    self.requestValueLabel.stringValue = manager.lastRequestAtText.length > 0 ? manager.lastRequestAtText : @"暂无";
    self.errorValueLabel.stringValue = manager.lastErrorText.length > 0 ? manager.lastErrorText : @"暂无";
    self.toggleButton.title = (manager.enabled || manager.state == LKMCPHostStateStarting) ? @"停止" : @"启动";
    self.refreshButton.enabled = YES;
    self.reconnectButton.enabled = YES;
}

- (NSTextField *)_label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.textColor = [NSColor labelColor];
    return label;
}

- (NSTextField *)_wrapLabel:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSView *)_rowWithTitle:(NSString *)title valueLabel:(NSTextField *)valueLabel {
    NSTextField *titleLabel = [self _label:[NSString stringWithFormat:@"%@:", title]];
    titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];

    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.spacing = 2;
    [row addArrangedSubview:titleLabel];
    [row addArrangedSubview:valueLabel];
    return row;
}

- (void)_handleToggle {
    [[LKMCPHostManager sharedInstance] toggleHost];
}

- (void)_handleCopy {
    [[LKMCPHostManager sharedInstance] copyAddressToPasteboard];
}

- (void)_handleRefresh {
    [[LKMCPHostManager sharedInstance] refreshStatus];
}

- (void)_handleReconnect {
    [[LKMCPHostManager sharedInstance] reconnectHost];
}

@end
