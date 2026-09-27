// Since macOS 15.4 MediaRemote only answers Apple's own processes, so Tama
// can't read the system Now Playing itself. `/usr/bin/perl` is one of them:
// Tama runs it with this library loaded, and it relays Now Playing (every
// app, browsers included, with position and artwork) and the transport
// commands. Same approach as ungive/mediaremote-adapter, used by other notch apps.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include "DroppyMediaRemoteAdapter.h"

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef NSString *(*MRClientStringFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn getInfo;
static MRGetIsPlayingFn getIsPlaying;
static MRGetClientFn getClient;
static MRGetPIDFn getPID;
static MRClientStringFn clientBundleID;
static MRClientStringFn clientParentBundleID;
static MRSendCommandFn sendCommand;
static MRSetElapsedFn setElapsed;

static dispatch_queue_t workQueue;
static dispatch_block_t pendingEmit;
static NSUInteger lastArtworkHash;

static void writeLine(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

/// Collects info, playing state and the owning app, then writes one line.
static void emitNow(void) {
    dispatch_group_t group = dispatch_group_create();
    __block NSDictionary *info = nil;
    __block BOOL playing = NO;
    __block BOOL hasPlaying = NO;
    __block NSString *bundleID = nil;
    __block int pid = 0;

    dispatch_group_enter(group);
    getInfo(workQueue, ^(NSDictionary *result) { info = result; dispatch_group_leave(group); });
    if (getIsPlaying) {
        dispatch_group_enter(group);
        getIsPlaying(workQueue, ^(Boolean value) { playing = value; hasPlaying = YES; dispatch_group_leave(group); });
    }
    if (getClient && clientBundleID) {
        dispatch_group_enter(group);
        getClient(workQueue, ^(id client) {
            if (client) {
                // A browser tab reports its helper; the parent is the app itself.
                NSString *parent = clientParentBundleID ? clientParentBundleID(client) : nil;
                bundleID = parent.length ? parent : clientBundleID(client);
            }
            dispatch_group_leave(group);
        });
    }
    if (getPID) {
        dispatch_group_enter(group);
        getPID(workQueue, ^(int value) { pid = value; dispatch_group_leave(group); });
    }

    dispatch_group_notify(group, workQueue, ^{
        NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        if (![title isKindOfClass:NSString.class] || title.length == 0) {
            writeLine(@{ @"empty": @YES });
            return;
        }
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        out[@"title"] = title;
        NSString *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSString *album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
        if ([artist isKindOfClass:NSString.class]) out[@"artist"] = artist;
        if ([album isKindOfClass:NSString.class]) out[@"album"] = album;
        NSNumber *duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
        NSNumber *elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([duration isKindOfClass:NSNumber.class]) out[@"duration"] = duration;
        if ([elapsed isKindOfClass:NSNumber.class]) out[@"elapsed"] = elapsed;
        if ([rate isKindOfClass:NSNumber.class]) out[@"rate"] = rate;
        if ([stamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(stamp.timeIntervalSince1970);
        out[@"playing"] = @(hasPlaying ? playing : rate.doubleValue > 0);

        if (!bundleID.length && pid > 0) {
            bundleID = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
        }
        if (bundleID.length) out[@"bundleID"] = bundleID;
        if (pid > 0) out[@"pid"] = @(pid);

        // Artwork is large: send it only when it changes.
        NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
            NSUInteger hash = artwork.hash ^ artwork.length;
            out[@"artworkID"] = @(hash);
            if (hash != lastArtworkHash) {
                lastArtworkHash = hash;
                out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            }
        }
        writeLine(out);
    });
}

/// Notifications arrive in bursts (info, state and app change together).
static void scheduleEmit(void) {
    dispatch_async(workQueue, ^{
        if (pendingEmit) dispatch_block_cancel(pendingEmit);
        pendingEmit = dispatch_block_create(0, ^{ emitNow(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), workQueue, pendingEmit);
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject;
    // MRCommand values.
    NSDictionary<NSString *, NSNumber *> *commands = @{
        @"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"previous": @5
    };
    if (commands[verb]) {
        if (sendCommand) sendCommand(commands[verb].intValue, nil);
    } else if ([verb isEqualToString:@"seek"] && parts.count > 1) {
        if (setElapsed) setElapsed(parts[1].doubleValue);
    } else if (![verb isEqualToString:@"refresh"]) {
        return;
    }
    scheduleEmit();
}

void droppy_mediaremote_stream(void) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) {
            writeLine(@{ @"error": @"MediaRemote unavailable" });
            return;
        }
        getInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        getIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        getClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        getPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
        clientBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        clientParentBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        sendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        setElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        MRRegisterFn registerForNotifications = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (!getInfo || !registerForNotifications) {
            writeLine(@{ @"error": @"MediaRemote symbols missing" });
            return;
        }

        workQueue = dispatch_queue_create("app.getdroppy.mediaremote", DISPATCH_QUEUE_SERIAL);
        registerForNotifications(workQueue);
        for (NSString *name in @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        ]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                        usingBlock:^(NSNotification *note) { scheduleEmit(); }];
        }

        // Commands arrive one per line; EOF means Tama is gone, so exit with it.
        dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, workQueue);
        NSMutableString *buffer = [NSMutableString string];
        dispatch_source_set_event_handler(input, ^{
            char chunk[1024];
            ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
            if (count <= 0) exit(0);
            NSString *text = [[NSString alloc] initWithBytes:chunk length:count encoding:NSUTF8StringEncoding];
            if (text) [buffer appendString:text];
            NSRange newline;
            while ((newline = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [buffer substringToIndex:newline.location];
                [buffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
                handleCommand([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
            }
        });
        dispatch_resume(input);

        writeLine(@{ @"ready": @YES });
        scheduleEmit();
        // Everything runs on workQueue; this keeps perl's main thread alive and
        // serves anything MediaRemote schedules on the main queue.
        dispatch_main();
    }
}
