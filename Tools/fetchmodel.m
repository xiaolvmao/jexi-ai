// fetchmodel <url> <dest>
// Downloads one URL to dest with NSURLSession.  Device has no curl/wget.
#import <Foundation/Foundation.h>

@interface JXDownloader : NSObject <NSURLSessionDownloadDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSString *dest;
@property (nonatomic, assign) BOOL done;
@property (nonatomic, assign) BOOL ok;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) int64_t lastBucket;
@end

@implementation JXDownloader
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)written
totalBytesExpectedToWrite:(int64_t)expected
{
    int64_t bucket = expected > 0 ? (written * 20 / expected) : 0;
    if (bucket != self.lastBucket) {
        self.lastBucket = bucket;
        printf("  %3lld%%  %lld / %lld\n", (long long)(written * 100 / (expected ?: 1)),
               (long long)written, (long long)expected);
        fflush(stdout);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)location
{
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)task.response;
    printf("  http status %ld, %lld bytes\n", (long)http.statusCode,
           (long long)task.countOfBytesReceived);
    fflush(stdout);
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.dest error:NULL];
    NSError *err = nil;
    if (![fm copyItemAtURL:location toURL:[NSURL fileURLWithPath:self.dest] error:&err]) {
        self.error = err;
        self.ok = NO;
    } else {
        self.ok = YES;
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    if (error) {
        self.error = error;
        self.ok = NO;
    }
    self.done = YES;
}
@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: fetchmodel <url> <dest>\n");
            return 2;
        }
        NSString *urlString = [NSString stringWithUTF8String:argv[1]];
        NSString *dest = [NSString stringWithUTF8String:argv[2]];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            fprintf(stderr, "bad url\n");
            return 2;
        }
        printf("fetching %s\n  -> %s\n", urlString, dest.UTF8String);
        fflush(stdout);

        JXDownloader *dl = [JXDownloader new];
        dl.dest = dest;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 120;
        cfg.timeoutIntervalForResource = 60 * 30;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg
                                                             delegate:dl
                                                        delegateQueue:nil];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];
        // Optional 3rd argument: a Range header value such as 0-2047, or "probe"
        // (probe = 0-2047 and print every response header, for diagnosing hosts).
        BOOL probe = NO;
        if (argc >= 4) {
            NSString *r = [NSString stringWithUTF8String:argv[3]];
            probe = [r isEqualToString:@"probe"];
            [req setValue:probe ? @"bytes=0-2047" : [@"bytes=" stringByAppendingString:r]
                forHTTPHeaderField:@"Range"];
        }
        (void)probe;
        [[session downloadTaskWithRequest:req] resume];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60 * 30];
        while (!dl.done && [deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            }
        }
        [session invalidateAndCancel];
        if (!dl.done) {
            fprintf(stderr, "timed out\n");
            return 1;
        }
        if (!dl.ok) {
            fprintf(stderr, "failed: %s\n", dl.error.description.UTF8String);
            return 1;
        }
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:dest error:NULL] fileSize];
        printf("done: %llu bytes at %s\n", size, dest.UTF8String);
        return 0;
    }
}
