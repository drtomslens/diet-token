#import <Cocoa/Cocoa.h>

static NSString *const kServerLogPath = @"/tmp/local_shunt_server.log";
static const NSInteger kPort = 8080;

static NSString *resolveAIRoot(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *dietRoot = env[@"DIET_TOKEN_HOME"];
    if (dietRoot.length > 0) return dietRoot;
    NSString *envRoot = env[@"LOCAL_SHUNT_HOME"];
    if (envRoot.length > 0) return envRoot;

    NSString *cfgFile = [NSHomeDirectory() stringByAppendingPathComponent:@".config/local-shunt/root"];
    NSString *cfgRoot = [NSString stringWithContentsOfFile:cfgFile encoding:NSUTF8StringEncoding error:nil];
    if (cfgRoot) {
        NSString *trimmed = [cfgRoot stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) return trimmed;
    }

    NSString *plistRoot = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LocalShuntRoot"];
    if ([plistRoot isKindOfClass:[NSString class]] && plistRoot.length > 0) return plistRoot;

    return [NSHomeDirectory() stringByAppendingPathComponent:@"local-shunt"];
}

static NSColor *dietGreenColor(void) {
    return [NSColor colorWithSRGBRed:0.20 green:0.78 blue:0.35 alpha:1.0];
}

static NSColor *dietRedColor(void) {
    return [NSColor colorWithSRGBRed:1.00 green:0.23 blue:0.19 alpha:1.0];
}

static NSColor *dietAmberColor(void) {
    return [NSColor colorWithSRGBRed:1.00 green:0.62 blue:0.04 alpha:1.0];
}

static NSImage *statusDotImage(NSColor *color, CGFloat diameter) {
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(diameter + 2, diameter + 2)];
    [img lockFocus];
    [color setFill];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1, 1, diameter, diameter)];
    [circle fill];
    [img unlockFocus];
    img.template = NO;
    return img;
}

static NSImage *menuBarLeafIcon(NSColor *badgeColor, BOOL isDarkBar) {
    NSSize sz = NSMakeSize(20, 18);
    NSImage *img = [[NSImage alloc] initWithSize:sz];
    [img lockFocus];

    NSImage *leaf = [NSImage imageWithSystemSymbolName:@"leaf.fill" accessibilityDescription:@"DietToken"];
    if (leaf) {
        NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightMedium];
        leaf = [leaf imageWithSymbolConfiguration:cfg];
        NSImage *tinted = [leaf copy];
        [tinted lockFocus];
        [(isDarkBar ? [NSColor whiteColor] : [NSColor blackColor]) set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
        [tinted unlockFocus];
        tinted.template = NO;
        CGFloat lx = 1.0;
        CGFloat ly = (sz.height - tinted.size.height) / 2.0;
        [tinted drawAtPoint:NSMakePoint(lx, ly) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    // Crisp 6.5px colored status dot in bottom-right corner
    NSRect dotRect = NSMakeRect(sz.width - 7.5, 1.0, 6.5, 6.5);
    [badgeColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];

    [img unlockFocus];
    img.template = NO;
    return img;
}

@interface RoundedCardView : NSView
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *borderColor;
@end

@implementation RoundedCardView
- (void)drawRect:(NSRect)dirtyRect {
    NSRect inset = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:inset xRadius:self.cornerRadius yRadius:self.cornerRadius];
    if (self.fillColor) {
        [self.fillColor setFill];
        [p fill];
    }
    if (self.borderColor) {
        [self.borderColor setStroke];
        p.lineWidth = 1.0;
        [p stroke];
    }
}
@end

@interface AccentBarView : NSView
@property (nonatomic, strong) NSColor *barColor;
@end

@implementation AccentBarView
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:1.2 yRadius:1.2];
    [(self.barColor ?: dietGreenColor()) setFill];
    [p fill];
}
@end

@interface DividerView : NSView
@property (nonatomic, strong) NSColor *lineColor;
@end

@implementation DividerView
- (void)drawRect:(NSRect)dirtyRect {
    [(self.lineColor ?: [NSColor separatorColor]) setFill];
    NSRectFill(self.bounds);
}
@end

@interface DietBarView : NSView
@property (nonatomic, assign) double savedRatio;
@property (nonatomic, assign) BOOL hasData;
@end

@implementation DietBarView
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat radius = bounds.size.height / 2.0;
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    if (!self.hasData) {
        [[NSColor tertiaryLabelColor] setFill];
        [track fill];
        return;
    }
    [dietRedColor() setFill];
    [track fill];

    double clamped = MAX(0.0, MIN(1.0, self.savedRatio));
    CGFloat greenW = bounds.size.width * clamped;
    if (greenW > 0.5) {
        [NSGraphicsContext saveGraphicsState];
        [track addClip];
        [dietGreenColor() setFill];
        NSRectFill(NSMakeRect(0, 0, greenW, bounds.size.height));
        [NSGraphicsContext restoreGraphicsState];
    }
}
@end

@interface HoverRowButton : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, assign) BOOL checked;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL isDark;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, strong) id representedObject;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@implementation HoverRowButton

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *ta in self.trackingAreas) {
        [self removeTrackingArea:ta];
    }
    NSTrackingArea *ta = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                      options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:ta];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!self.enabled) return;
    self.hovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.enabled) return;
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(pt, self.bounds) && self.target && self.action) {
        [NSApp sendAction:self.action to:self.target from:self];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.hovered && self.enabled) {
        NSColor *hoverBg = self.isDark
            ? [NSColor colorWithWhite:1.0 alpha:0.12]
            : [NSColor colorWithWhite:0.0 alpha:0.08];
        [hoverBg setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6.0 yRadius:6.0] fill];
    }

    NSColor *fg = self.enabled
        ? (self.isDark ? [NSColor whiteColor] : [NSColor blackColor])
        : (self.isDark ? [NSColor colorWithWhite:1.0 alpha:0.35] : [NSColor colorWithWhite:0.0 alpha:0.35]);

    CGFloat x = 8.0;
    if (self.symbolName.length > 0) {
        NSImage *sym = [NSImage imageWithSystemSymbolName:self.symbolName accessibilityDescription:nil];
        if (sym) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightMedium];
            sym = [sym imageWithSymbolConfiguration:cfg];
            NSImage *tinted = [sym copy];
            [tinted lockFocus];
            [fg set];
            NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
            [tinted unlockFocus];
            tinted.template = NO;
            CGFloat iy = (self.bounds.size.height - tinted.size.height) / 2.0;
            [tinted drawAtPoint:NSMakePoint(x, iy) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        }
        x += 22.0;
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:(self.checked ? NSFontWeightSemibold : NSFontWeightRegular)],
        NSForegroundColorAttributeName: fg
    };
    NSSize sz = [self.titleText sizeWithAttributes:attrs];
    CGFloat ty = (self.bounds.size.height - sz.height) / 2.0;
    [self.titleText drawAtPoint:NSMakePoint(x, ty) withAttributes:attrs];

    if (self.checked) {
        NSImage *chk = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
        if (chk) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:11.0 weight:NSFontWeightBold];
            chk = [chk imageWithSymbolConfiguration:cfg];
            NSImage *tinted = [chk copy];
            [tinted lockFocus];
            [dietGreenColor() set];
            NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
            [tinted unlockFocus];
            tinted.template = NO;
            CGFloat cx = self.bounds.size.width - tinted.size.width - 10.0;
            CGFloat cy = (self.bounds.size.height - tinted.size.height) / 2.0;
            [tinted drawAtPoint:NSMakePoint(cx, cy) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        }
    }
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@property (nonatomic, copy) NSString *aiRoot;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSViewController *popoverVC;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSString *activeModel;
@property (nonatomic, copy) NSString *serverRAMText;
@property (nonatomic, assign) BOOL isStarting;
@property (nonatomic, copy) NSString *startingPreset;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *installedCache;
@end

@implementation AppDelegate

- (BOOL)isDarkMode {
    NSAppearanceName match = [[NSApp effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)applyAppearance {
    // Follow macOS System Appearance automatically (Light / Dark / Auto at sunset)
    [NSApp setAppearance:nil];
    self.popover.appearance = nil;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.aiRoot = resolveAIRoot();
    self.installedCache = [NSMutableDictionary dictionary];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    self.popoverVC = [[NSViewController alloc] init];
    self.popover = [[NSPopover alloc] init];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = YES;
    self.popover.delegate = self;
    self.popover.contentViewController = self.popoverVC;

    [self applyAppearance];
    [self updateTitle];

    [self pollStatus];
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf pollStatus];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
    } else {
        [self refreshPopoverContent];
        [self.popover showRelativeToRect:self.statusItem.button.bounds
                                  ofView:self.statusItem.button
                           preferredEdge:NSRectEdgeMinY];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (NSString *)pauseFlagPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".config/local-shunt/paused"];
}

- (BOOL)isShuntPaused {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self pauseFlagPath]];
}

- (NSArray<NSString *> *)detectWiredAgents {
    NSMutableArray<NSString *> *agents = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *agRule = [NSHomeDirectory() stringByAppendingPathComponent:@".gemini/config/rules/local-shunt.md"];
    if ([fm fileExistsAtPath:agRule]) [agents addObject:@"Antigravity"];

    NSString *claudeSettings = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"];
    NSString *claudeText = [NSString stringWithContentsOfFile:claudeSettings encoding:NSUTF8StringEncoding error:nil];
    if (claudeText && [claudeText containsString:@"shunt_hook.py"]) [agents addObject:@"Claude Code"];
    return agents;
}

- (BOOL)isPresetInstalled:(NSString *)preset {
    NSNumber *cached = self.installedCache[preset];
    if (cached != nil) return [cached boolValue];

    NSString *envPath = [self.aiRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"configs/%@.env", preset]];
    NSString *text = [NSString stringWithContentsOfFile:envPath encoding:NSUTF8StringEncoding error:nil];
    if (!text) {
        self.installedCache[preset] = @NO;
        return NO;
    }
    if ([text containsString:@"BACKEND=\"mlx\""]) {
        self.installedCache[preset] = @YES;
        return YES;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[@"-c", [NSString stringWithFormat:@"source \"%@\" 2>/dev/null && [[ -f \"$MODEL_FILE\" ]]", envPath]];
    [task launchAndReturnError:nil];
    [task waitUntilExit];
    BOOL ok = (task.terminationStatus == 0);
    self.installedCache[preset] = @(ok);
    return ok;
}

- (NSArray<NSString *> *)discoverPresets {
    NSString *dir = [self.aiRoot stringByAppendingPathComponent:@"configs"];
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (!items) return @[];
    NSMutableArray<NSString *> *presets = [NSMutableArray array];
    for (NSString *name in items) {
        if ([name hasSuffix:@".env"]) [presets addObject:[name substringToIndex:name.length - 4]];
    }
    [presets sortUsingSelector:@selector(compare:)];
    return presets;
}

- (void)readTokenSavingsTotalCalls:(NSInteger *)outCalls
                        totalSaved:(NSInteger *)outSaved
                          totalRaw:(NSInteger *)outRaw
                        todayCalls:(NSInteger *)outTodayCalls
                        todaySaved:(NSInteger *)outTodaySaved
                          todayRaw:(NSInteger *)outTodayRaw {
    NSString *path = [self.aiRoot stringByAppendingPathComponent:@"notes/shunt_usage.jsonl"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *todayPrefix = [df stringFromDate:[NSDate date]];

    NSInteger calls = 0, saved = 0, raw = 0;
    NSInteger tCalls = 0, tSaved = 0, tRaw = 0;
    if (text) {
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (line.length == 0) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (!data) continue;
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![obj isKindOfClass:[NSDictionary class]]) continue;
            calls++;
            NSInteger s = [obj[@"est_gemini_tokens_saved"] respondsToSelector:@selector(integerValue)]
                ? [obj[@"est_gemini_tokens_saved"] integerValue] : 0;
            NSInteger r = [obj[@"est_raw_tokens"] respondsToSelector:@selector(integerValue)]
                ? [obj[@"est_raw_tokens"] integerValue] : 0;
            saved += s;
            raw += r;
            NSString *ts = obj[@"ts"];
            if ([ts isKindOfClass:[NSString class]] && [ts hasPrefix:todayPrefix]) {
                tCalls++;
                tSaved += s;
                tRaw += r;
            }
        }
    }
    if (outCalls) *outCalls = calls;
    if (outSaved) *outSaved = saved;
    if (outRaw) *outRaw = raw;
    if (outTodayCalls) *outTodayCalls = tCalls;
    if (outTodaySaved) *outTodaySaved = tSaved;
    if (outTodayRaw) *outTodayRaw = tRaw;
}

- (NSString *)compactTokens:(NSInteger)tok {
    if (tok >= 1000000000) return [NSString stringWithFormat:@"%.1fB", tok / 1000000000.0];
    if (tok >= 1000000) return [NSString stringWithFormat:@"%.1fM", tok / 1000000.0];
    if (tok >= 1000) return [NSString stringWithFormat:@"%.1fk", tok / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)tok];
}

- (double)ratePerMillionUSD {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"DietTokenRatePerMillion"] != nil) {
        double v = [ud doubleForKey:@"DietTokenRatePerMillion"];
        if (v > 0.0) return v;
    }
    return 3.00;
}

- (NSString *)formatUSDForTokens:(NSInteger)tokens {
    double usd = ((double)tokens / 1000000.0) * [self ratePerMillionUSD];
    return [NSString stringWithFormat:@"%.2f", usd];
}

- (NSArray<NSString *> *)loadMessagesFromFile {
    NSString *path = [self.aiRoot stringByAppendingPathComponent:@"configs/messages.txt"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return @[];
    NSMutableArray<NSString *> *msgs = [NSMutableArray array];
    for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"#"]) continue;
        [msgs addObject:line];
    }
    return msgs;
}

- (NSString *)positiveMessageForTodaySaved:(NSInteger)todaySaved totalSaved:(NSInteger)totalSaved todayKey:(NSString *)todayKey {
    double todayUSD = ((double)todaySaved / 1000000.0) * [self ratePerMillionUSD];
    double totalUSD = ((double)totalSaved / 1000000.0) * [self ratePerMillionUSD];

    // Tiered dollar milestones (only briefly right as you cross each tier, so daily quotes stay fresh)
    if (totalUSD >= 1000.0) {
        return [NSString stringWithFormat:@"Legendary: ~$%@ in cloud API costs kept on your Mac.", [self formatUSDForTokens:totalSaved]];
    }
    if (totalUSD >= 100.0 && totalUSD < 110.0) {
        return [NSString stringWithFormat:@"Triple digits: ~$%@ saved — real money kept off the cloud.", [self formatUSDForTokens:totalSaved]];
    }
    if (totalUSD >= 10.0 && totalUSD < 11.0) {
        return [NSString stringWithFormat:@"Nice milestone: ~$%@ saved — lunch is on your local GPU.", [self formatUSDForTokens:totalSaved]];
    }
    if (totalUSD >= 1.0 && totalUSD < 1.25) {
        return [NSString stringWithFormat:@"First ~$%@ saved — small start, great habit.", [self formatUSDForTokens:totalSaved]];
    }
    if (todaySaved == 0) {
        NSArray<NSString *> *idleMsgs = @[
            @"Ready to put your next big file on a diet.",
            @"Standing by — open a big PDF or file to start saving.",
            @"Local reader armed and ready."
        ];
        return idleMsgs[[todayKey hash] % idleMsgs.count];
    }

    NSArray<NSString *> *allMsgs = [self loadMessagesFromFile];
    NSMutableArray<NSString *> *eligible = [NSMutableArray array];
    for (NSString *m in allMsgs) {
        // Only surface dollar-brag messages once savings are meaningful ($5+ all-time / $1+ today)
        if ([m containsString:@"{usd_all}"] && totalUSD < 5.0) continue;
        if ([m containsString:@"{usd_today}"] && todayUSD < 1.0) continue;
        [eligible addObject:m];
    }
    if (eligible.count == 0) [eligible addObject:@"DietToken working quietly in your corner."];

    NSString *msg = eligible[[todayKey hash] % eligible.count];
    msg = [msg stringByReplacingOccurrencesOfString:@"{usd_today}" withString:[self formatUSDForTokens:todaySaved]];
    msg = [msg stringByReplacingOccurrencesOfString:@"{usd_all}" withString:[self formatUSDForTokens:totalSaved]];
    return msg;
}

- (NSString *)shortNameForModel:(NSString *)model {
    NSString *lower = model.lowercaseString;
    if ([lower containsString:@"nemotron"]) return @"Nemotron";
    if ([lower containsString:@"gemma"]) return @"Gemma";
    if ([lower containsString:@"qwen"]) return @"Qwen3";
    if ([lower containsString:@"inkling"]) return @"Inkling";
    return model.length > 12 ? [model substringToIndex:12] : model;
}

- (NSString *)queryServerRAMText {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    NSString *cmd = [NSString stringWithFormat:
        @"p=$(lsof -tiTCP:%ld -sTCP:LISTEN | head -n 1); "
        @"[ -n \"$p\" ] && ps -o rss= -p \"$p\" 2>/dev/null || true", (long)kPort];
    task.arguments = @[@"-c", cmd];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launchAndReturnError:nil];
    [task waitUntilExit];
    NSData *d = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    long long kb = [out longLongValue];
    if (kb <= 0) return nil;
    double gb = (double)kb / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1f GB RAM", gb];
}

- (void)pollStatus {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/v1/models", (long)kPort]];
    if (!url) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 0.6;
    req.HTTPMethod = @"GET";

    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *foundModel = nil;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)resp).statusCode == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSArray *list = json[@"data"];
                if ([list isKindOfClass:[NSArray class]] && list.count > 0 && [list[0] isKindOfClass:[NSDictionary class]]) {
                    id modelId = list[0][@"id"];
                    if ([modelId isKindOfClass:[NSString class]]) foundModel = modelId;
                }
            }
        }
        NSString *ramText = foundModel ? [self queryServerRAMText] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            BOOL changed = NO;
            if (foundModel) {
                if (![strongSelf.activeModel isEqualToString:foundModel] || strongSelf.isStarting ||
                    (ramText && ![strongSelf.serverRAMText isEqualToString:ramText])) changed = YES;
                strongSelf.activeModel = foundModel;
                strongSelf.serverRAMText = ramText;
                strongSelf.isStarting = NO;
                strongSelf.startingPreset = nil;
            } else if (!strongSelf.isStarting) {
                if (strongSelf.activeModel != nil) changed = YES;
                strongSelf.activeModel = nil;
                strongSelf.serverRAMText = nil;
            }
            [strongSelf updateTitle];
            if (changed && strongSelf.popover.isShown) {
                [strongSelf refreshPopoverContent];
            }
        });
    }] resume];
}

- (void)updateTitle {
    NSStatusBarButton *btn = self.statusItem.button;
    if (!btn) return;
    btn.imagePosition = NSImageOnly;
    btn.title = @"";

    NSColor *badge;
    if (self.isStarting) {
        badge = dietAmberColor();
    } else if (self.activeModel) {
        if ([self isShuntPaused]) {
            badge = dietRedColor();
        } else if ([self detectWiredAgents].count == 0) {
            badge = dietAmberColor();
        } else {
            badge = dietGreenColor();
        }
    } else {
        badge = dietRedColor();
    }

    // Detect menu bar appearance (dark vs light) so the leaf glyph always has crisp contrast
    NSAppearanceName barMatch = [[btn effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]];
    BOOL isDarkBar = [barMatch isEqualToString:NSAppearanceNameDarkAqua];
    btn.image = menuBarLeafIcon(badge, isDarkBar);
}

- (NSTextField *)makeLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color frame:(NSRect)frame {
    NSTextField *tf = [[NSTextField alloc] initWithFrame:frame];
    tf.stringValue = text;
    tf.font = font;
    tf.textColor = color;
    tf.bezeled = NO;
    tf.drawsBackground = NO;
    tf.editable = NO;
    tf.selectable = NO;
    tf.lineBreakMode = NSLineBreakByTruncatingTail;
    return tf;
}

- (NSView *)makePill:(NSString *)text accent:(NSColor *)accent textColor:(NSColor *)textColor frame:(NSRect)frame {
    RoundedCardView *pill = [[RoundedCardView alloc] initWithFrame:frame];
    pill.cornerRadius = frame.size.height / 2.0;
    pill.fillColor = [accent colorWithAlphaComponent:0.22];
    pill.borderColor = [accent colorWithAlphaComponent:0.65];

    NSTextField *lbl = [self makeLabel:text
                                  font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]
                                 color:textColor
                                 frame:NSMakeRect(0, 2, frame.size.width, frame.size.height - 4)];
    lbl.alignment = NSTextAlignmentCenter;
    [pill addSubview:lbl];
    return pill;
}

- (HoverRowButton *)makeRow:(NSString *)title symbol:(NSString *)sym checked:(BOOL)chk enabled:(BOOL)en dark:(BOOL)dark y:(CGFloat)y width:(CGFloat)w pad:(CGFloat)pad action:(SEL)sel obj:(id)obj {
    HoverRowButton *row = [[HoverRowButton alloc] initWithFrame:NSMakeRect(pad - 4, y, w - 2 * pad + 8, 26)];
    row.titleText = title;
    row.symbolName = sym;
    row.checked = chk;
    row.enabled = en;
    row.isDark = dark;
    row.target = self;
    row.action = sel;
    row.representedObject = obj;
    return row;
}

- (void)refreshPopoverContent {
    BOOL dark = [self isDarkMode];
    [self applyAppearance];

    NSColor *fgColor = dark ? [NSColor whiteColor] : [NSColor blackColor];
    NSColor *insetBg = dark
        ? [NSColor colorWithWhite:1.0 alpha:0.07]
        : [NSColor colorWithWhite:0.0 alpha:0.05];
    NSColor *borderCol = dark
        ? [NSColor colorWithWhite:1.0 alpha:0.12]
        : [NSColor colorWithWhite:0.0 alpha:0.10];

    NSFont *heroFont = [NSFont monospacedDigitSystemFontOfSize:18.0 weight:NSFontWeightBold];
    NSFont *bodyBold = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    NSFont *bodyReg  = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    NSFont *bodyMono = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightMedium];

    NSInteger calls = 0, saved = 0, raw = 0, todayCalls = 0, todaySaved = 0, todayRaw = 0;
    [self readTokenSavingsTotalCalls:&calls totalSaved:&saved totalRaw:&raw todayCalls:&todayCalls todaySaved:&todaySaved todayRaw:&todayRaw];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *todayKey = [df stringFromDate:[NSDate date]];

    BOOL paused = [self isShuntPaused];
    NSArray<NSString *> *wired = [self detectWiredAgents];
    NSArray<NSString *> *presets = [self discoverPresets];

    NSColor *accentColor;
    NSString *headerTitle;
    NSString *subText;

    if (self.isStarting && self.startingPreset) {
        accentColor = dietAmberColor();
        headerTitle = self.startingPreset;
        subText = @"Loading model into memory…";
    } else if (self.activeModel) {
        headerTitle = self.activeModel;
        NSString *ramPart = self.serverRAMText ?: [NSString stringWithFormat:@"Port :%ld", (long)kPort];
        if (paused) {
            accentColor = dietRedColor();
            subText = [NSString stringWithFormat:@"Cloud Only · %@", ramPart];
        } else if (wired.count > 0) {
            accentColor = dietGreenColor();
            subText = [NSString stringWithFormat:@"Local · %@", ramPart];
        } else {
            accentColor = dietAmberColor();
            subText = [NSString stringWithFormat:@"Unwired · %@", ramPart];
        }
    } else {
        accentColor = dietRedColor();
        headerTitle = @"Local LLM Off";
        subText = @"Select a model below";
    }

    double todayRatio = (todayRaw > 0) ? ((double)todaySaved / (double)todayRaw) : 0.0;
    NSInteger todayPct = (todayRaw > 0) ? (NSInteger)llround(todayRatio * 100.0) : 0;
    double allRatio = (raw > 0) ? ((double)saved / (double)raw) : 0.0;
    NSInteger allPct = (raw > 0) ? (NSInteger)llround(allRatio * 100.0) : 0;
    NSString *motto = [self positiveMessageForTodaySaved:todaySaved totalSaved:saved todayKey:todayKey];

    CGFloat width = 340.0;
    CGFloat pad = 14.0;
    CGFloat innerW = width - 2 * pad;
    CGFloat presetsH = MAX(1, presets.count) * 26.0;
    CGFloat height = 228.0 + presetsH + 142.0;

    NSVisualEffectView *root = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    root.material = NSVisualEffectMaterialPopover;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateActive;

    CGFloat y = height;

    // 1. Header: Dot + Model Name + Native macOS NSSwitch
    y -= 28;
    NSImageView *dotView = [[NSImageView alloc] initWithFrame:NSMakeRect(pad, y + 3, 12, 12)];
    dotView.image = statusDotImage(accentColor, 10.0);
    [root addSubview:dotView];

    NSTextField *titleLbl = [self makeLabel:headerTitle font:bodyBold color:fgColor frame:NSMakeRect(pad + 18, y, innerW - 70, 18)];
    [root addSubview:titleLbl];

    NSSwitch *dietSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(width - pad - 40, y - 4, 40, 22)];
    dietSwitch.state = paused ? NSControlStateValueOff : NSControlStateValueOn;
    dietSwitch.target = self;
    dietSwitch.action = @selector(switchToggled:);
    [root addSubview:dietSwitch];

    y -= 17;
    NSTextField *subLbl = [self makeLabel:subText font:bodyReg color:fgColor frame:NSMakeRect(pad + 18, y, innerW - 70, 16)];
    [root addSubview:subLbl];

    // 2. Hero Savings Row
    y -= 32;
    NSTextField *heroVal = [self makeLabel:[NSString stringWithFormat:@"$%@", [self formatUSDForTokens:saved]]
                                      font:heroFont color:fgColor frame:NSMakeRect(pad, y, 82, 24)];
    [root addSubview:heroVal];

    NSTextField *todayUsdLbl = [self makeLabel:[NSString stringWithFormat:@"+$%@ today · $%.2f/1M", [self formatUSDForTokens:todaySaved], [self ratePerMillionUSD]]
                                          font:bodyMono color:fgColor frame:NSMakeRect(pad + 72, y + 3, 174, 18)];
    [root addSubview:todayUsdLbl];

    NSView *offPill = [self makePill:[NSString stringWithFormat:@"%ld%% OFF", (long)allPct]
                              accent:dietGreenColor() textColor:fgColor frame:NSMakeRect(width - pad - 70, y + 2, 70, 20)];
    [root addSubview:offPill];

    // 3. Inset Card: Today & All-time Bars
    y -= 92;
    CGFloat boxH = 82.0;
    RoundedCardView *box = [[RoundedCardView alloc] initWithFrame:NSMakeRect(pad, y, innerW, boxH)];
    box.cornerRadius = 8.0;
    box.fillColor = insetBg;
    box.borderColor = borderCol;
    [root addSubview:box];

    CGFloat bxPad = 10.0;
    CGFloat bxInner = innerW - 2 * bxPad;

    NSString *todayUnit = (todayCalls == 1) ? @"call" : @"calls";
    [box addSubview:[self makeLabel:[NSString stringWithFormat:@"Today · %ld %@", (long)todayCalls, todayUnit]
                               font:bodyBold color:fgColor frame:NSMakeRect(bxPad, boxH - 22, 130, 16)]];
    NSTextField *tRight = [self makeLabel:[NSString stringWithFormat:@"%@ / %@ · %ld%%", [self compactTokens:todaySaved], [self compactTokens:todayRaw], (long)todayPct]
                                     font:bodyMono color:fgColor frame:NSMakeRect(bxPad + 115, boxH - 22, bxInner - 115, 16)];
    tRight.alignment = NSTextAlignmentRight;
    [box addSubview:tRight];

    DietBarView *todayBar = [[DietBarView alloc] initWithFrame:NSMakeRect(bxPad, boxH - 34, bxInner, 7)];
    todayBar.savedRatio = todayRatio;
    todayBar.hasData = (todayRaw > 0);
    [box addSubview:todayBar];

    NSString *allUnit = (calls == 1) ? @"call" : @"calls";
    [box addSubview:[self makeLabel:[NSString stringWithFormat:@"All-time · %ld %@", (long)calls, allUnit]
                               font:bodyBold color:fgColor frame:NSMakeRect(bxPad, boxH - 59, 130, 16)]];
    NSTextField *aRight = [self makeLabel:[NSString stringWithFormat:@"%@ / %@ · %ld%%", [self compactTokens:saved], [self compactTokens:raw], (long)allPct]
                                     font:bodyMono color:fgColor frame:NSMakeRect(bxPad + 115, boxH - 59, bxInner - 115, 16)];
    aRight.alignment = NSTextAlignmentRight;
    [box addSubview:aRight];

    DietBarView *allBar = [[DietBarView alloc] initWithFrame:NSMakeRect(bxPad, boxH - 71, bxInner, 7)];
    allBar.savedRatio = allRatio;
    allBar.hasData = (raw > 0);
    [box addSubview:allBar];

    // 4. Editorial Motto Strip
    y -= 42;
    AccentBarView *quoteAccent = [[AccentBarView alloc] initWithFrame:NSMakeRect(pad, y + 3, 2.5, 30)];
    quoteAccent.barColor = accentColor;
    [root addSubview:quoteAccent];

    NSFont *mottoFont = [[NSFontManager sharedFontManager] convertFont:bodyReg toHaveTrait:NSItalicFontMask];
    NSString *quotedMotto = [NSString stringWithFormat:@"“%@”", motto];
    NSTextField *mottoLbl = [self makeLabel:quotedMotto font:mottoFont color:fgColor frame:NSMakeRect(pad + 10, y, innerW - 10, 34)];
    mottoLbl.lineBreakMode = NSLineBreakByWordWrapping;
    mottoLbl.maximumNumberOfLines = 2;
    [root addSubview:mottoLbl];

    // Divider
    y -= 10;
    DividerView *d1 = [[DividerView alloc] initWithFrame:NSMakeRect(pad, y, innerW, 1)];
    d1.lineColor = borderCol;
    [root addSubview:d1];

    // 5. Model Presets
    y -= 6;
    for (NSString *preset in presets) {
        y -= 26;
        BOOL installed = [self isPresetInstalled:preset];
        BOOL active = (self.activeModel && [self.activeModel isEqualToString:preset]);
        NSString *label = installed ? preset : [NSString stringWithFormat:@"%@ (not downloaded)", preset];
        [root addSubview:[self makeRow:label symbol:@"cpu" checked:active enabled:installed dark:dark y:y width:width pad:pad action:@selector(selectPresetRow:) obj:preset]];
    }

    // Divider
    y -= 8;
    DividerView *d2 = [[DividerView alloc] initWithFrame:NSMakeRect(pad, y, innerW, 1)];
    d2.lineColor = borderCol;
    [root addSubview:d2];

    // 6. Controls
    y -= 6;
    y -= 26;
    [root addSubview:[self makeRow:@"Stop Server (Free RAM)" symbol:@"stop.circle" checked:NO enabled:(self.activeModel != nil || self.isStarting) dark:dark y:y width:width pad:pad action:@selector(stopServerAction:) obj:nil]];

    y -= 26;
    NSString *rateTitle = [NSString stringWithFormat:@"Set Your Token Rate ($%.2f/1M)…", [self ratePerMillionUSD]];
    [root addSubview:[self makeRow:rateTitle symbol:@"dollarsign.circle" checked:NO enabled:YES dark:dark y:y width:width pad:pad action:@selector(setTokenRateAction:) obj:nil]];

    y -= 26;
    [root addSubview:[self makeRow:@"Open Server Log" symbol:@"doc.text" checked:NO enabled:YES dark:dark y:y width:width pad:pad action:@selector(openLogAction:) obj:nil]];

    // Divider
    y -= 8;
    DividerView *d3 = [[DividerView alloc] initWithFrame:NSMakeRect(pad, y, innerW, 1)];
    d3.lineColor = borderCol;
    [root addSubview:d3];

    y -= 32;
    [root addSubview:[self makeRow:@"Quit DietToken" symbol:@"power" checked:NO enabled:YES dark:dark y:y width:width pad:pad action:@selector(quitAction:) obj:nil]];

    self.popoverVC.view = root;
    self.popover.contentSize = NSMakeSize(width, height);
}

- (void)killExistingServer {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    NSString *cmd = [NSString stringWithFormat:
        @"lsof -tiTCP:%ld -sTCP:LISTEN | while read -r p; do kill -TERM \"$p\" 2>/dev/null || true; done; "
        @"for i in {1..25}; do [ -z \"$(lsof -tiTCP:%ld -sTCP:LISTEN)\" ] && break; sleep 0.2; done; "
        @"lsof -tiTCP:%ld -sTCP:LISTEN | while read -r p; do kill -9 \"$p\" 2>/dev/null || true; done; "
        @"sleep 0.3", (long)kPort, (long)kPort, (long)kPort];
    task.arguments = @[@"-c", cmd];
    [task launchAndReturnError:nil];
    [task waitUntilExit];
}

- (void)switchToggled:(NSSwitch *)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self pauseFlagPath];
    if (sender.state == NSControlStateValueOn) {
        [fm removeItemAtPath:path error:nil];
    } else {
        NSString *dir = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createFileAtPath:path contents:[NSData data] attributes:nil];
    }
    [self updateTitle];
    [self refreshPopoverContent];
}

- (void)selectPresetRow:(HoverRowButton *)sender {
    NSString *preset = sender.representedObject;
    if (![preset isKindOfClass:[NSString class]]) return;
    if (self.activeModel && [self.activeModel isEqualToString:preset] && !self.isStarting) return;

    self.isStarting = YES;
    self.startingPreset = preset;
    self.activeModel = nil;
    [self updateTitle];
    [self refreshPopoverContent];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf killExistingServer];

        NSString *script = [strongSelf.aiRoot stringByAppendingPathComponent:@"scripts/start_model.sh"];
        NSString *cmd = [NSString stringWithFormat:@"nohup \"%@\" \"%@\" > \"%@\" 2>&1 &", script, preset, kServerLogPath];
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
        task.arguments = @[@"-lc", cmd];
        [task launchAndReturnError:nil];
        [task waitUntilExit];
    });
}

- (void)stopServerAction:(id)sender {
    self.isStarting = NO;
    self.startingPreset = nil;
    self.activeModel = nil;
    [self updateTitle];
    [self refreshPopoverContent];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [weakSelf killExistingServer];
    });
}

- (void)setTokenRateAction:(id)sender {
    [self.popover performClose:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Cloud Input Token Rate";
    alert.informativeText = @"Enter your cloud model's input price in USD per 1M tokens (default: $3.00/1M):";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Reset Default ($3.00)"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
    input.stringValue = [NSString stringWithFormat:@"%.2f", [self ratePerMillionUSD]];
    alert.accessoryView = input;

    NSModalResponse resp = [alert runModal];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (resp == NSAlertFirstButtonReturn) {
        double val = [input.stringValue doubleValue];
        if (val > 0.0) [ud setDouble:val forKey:@"DietTokenRatePerMillion"];
    } else if (resp == NSAlertSecondButtonReturn) {
        [ud removeObjectForKey:@"DietTokenRatePerMillion"];
    }
}

- (void)toggleThemeAction:(id)sender {
    BOOL nextDark = ![self isDarkMode];
    [[NSUserDefaults standardUserDefaults] setBool:nextDark forKey:@"DietTokenDarkMode"];
    [self applyAppearance];
    [self refreshPopoverContent];
}

- (void)openLogAction:(id)sender {
    [self.popover performClose:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:kServerLogPath]) {
        [[NSFileManager defaultManager] createFileAtPath:kServerLogPath contents:[NSData data] attributes:nil];
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:kServerLogPath]];
}

- (void)quitAction:(id)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
