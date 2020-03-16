// AFAutoPurgingImageCache.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV 

#import "AFAutoPurgingImageCache.h"

/**
 * 图片自动缓存机制
 * 增删改查图片
 */
@interface AFCachedImage : NSObject

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *identifier; //图片标识 -- 用来标记图片
@property (nonatomic, assign) UInt64 totalBytes;  //图片总大小
@property (nonatomic, strong) NSDate *lastAccessDate; //最后缓存图片的时间结点 -- 时间戳
@property (nonatomic, assign) UInt64 currentMemoryUsage; //当前内存使用情况

@end

@implementation AFCachedImage

/**
 * 初始化图片
 * 传入参数
 * 1.需要初始化的图片
 * 2.图片标识符
 */
- (instancetype)initWithImage:(UIImage *)image identifier:(NSString *)identifier {
    if (self = [self init]) {
        self.image = image;
        self.identifier = identifier;

        /* 缓存图片需要缓存图片的一些属性 */
        CGSize imageSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale); //图片大小
        CGFloat bytesPerPixel = 4.0; //一个像素点的大小为4字节 1024*1024*4 --> 就为1024*1024分辨率的图片的大小
        CGFloat bytesPerSize = imageSize.width * imageSize.height;
        self.totalBytes = (UInt64)bytesPerPixel * (UInt64)bytesPerSize;
        
        //更新最后的时间戳
        self.lastAccessDate = [NSDate date];
    }
    return self;
}

- (UIImage *)accessImage {
    self.lastAccessDate = [NSDate date];
    return self.image;
}

- (NSString *)description {
    NSString *descriptionString = [NSString stringWithFormat:@"Idenfitier: %@  lastAccessDate: %@ ", self.identifier, self.lastAccessDate];
    return descriptionString;

}

@end

@interface AFAutoPurgingImageCache ()
/* 通过字典操作来存储缓存图片 -- <标识符，缓存图片> */
@property (nonatomic, strong) NSMutableDictionary <NSString* , AFCachedImage*> *cachedImages;
@property (nonatomic, assign) UInt64 currentMemoryUsage;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue; //创建一个线程
@end

@implementation AFAutoPurgingImageCache

- (instancetype)init {
    return [self initWithMemoryCapacity:100 * 1024 * 1024 preferredMemoryCapacity:60 * 1024 * 1024];
}

/**
 * 初始化内存大小
 */
- (instancetype)initWithMemoryCapacity:(UInt64)memoryCapacity preferredMemoryCapacity:(UInt64)preferredMemoryCapacity {
    if (self = [super init]) {
        /* 给定的内存上限 -- AFN默认给的是内存大小为100MB */
        self.memoryCapacity = memoryCapacity;
        /* 给定的内存界限 -- AFN默认给的是内存界限为60MB */
        self.preferredMemoryUsageAfterPurge = preferredMemoryCapacity;
        self.cachedImages = [[NSMutableDictionary alloc] init];

        /* [[NSUUID UUID] UUIDString] -- 自动生成一个标识字符串 */
        NSString *queueName = [NSString stringWithFormat:@"com.alamofire.autopurgingimagecache-%@", [[NSUUID UUID] UUIDString]];
        self.synchronizationQueue = dispatch_queue_create([queueName cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);

        /* 需要清除缓存的通知 */
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(removeAllImages)
         name:UIApplicationDidReceiveMemoryWarningNotification
         object:nil];

    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UInt64)memoryUsage {
    __block UInt64 result = 0;
    dispatch_sync(self.synchronizationQueue, ^{
        result = self.currentMemoryUsage;
    });
    return result;
}

/**
 * 添加图片到缓存
 */
- (void)addImage:(UIImage *)image withIdentifier:(NSString *)identifier {
    /* 使用dispath_barrier_async用来创建一个栅栏线程，当图片很多时候可以很好的防止线程相互干扰，因此，使用栅栏起到阻碍作用 */
    dispatch_barrier_async(self.synchronizationQueue, ^{
        AFCachedImage *cacheImage = [[AFCachedImage alloc] initWithImage:image identifier:identifier];

        /* 从缓存中取出原来缓存的图片 */
        AFCachedImage *previousCachedImage = self.cachedImages[identifier];
        if (previousCachedImage != nil) {
            
            /* 删除之前缓存的大小 */
            self.currentMemoryUsage -= previousCachedImage.totalBytes;
        }

        /* 重新赋值，为了更新时间戳 */
        self.cachedImages[identifier] = cacheImage;
        
        /* 当前使用缓存添加上当前缓存图片的大小 */
        self.currentMemoryUsage += cacheImage.totalBytes;
    });

    dispatch_barrier_async(self.synchronizationQueue, ^{
        /* 当前使用的内存 > 用于存储的内存大小 -- 用来释放内存 --> 删除操作做到的是需要将整个图片删除掉 */
        /* 101 > 100 */
        if (self.currentMemoryUsage > self.memoryCapacity) {
            /* 获得要删除的内存大小(当前的内存使用 - 用户限定的内存容限) */
            UInt64 bytesToPurge = self.currentMemoryUsage - self.preferredMemoryUsageAfterPurge;
            
            /* 使用LRU算法对时间进行排序，删除时间较长的图片缓存，对于用户来说，时间越长说明越不需要缓存 */
            NSMutableArray <AFCachedImage*> *sortedImages = [NSMutableArray arrayWithArray:self.cachedImages.allValues];
            
            /* 系统提供的方法 */
            NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastAccessDate"
                                                                           ascending:YES];
            [sortedImages sortUsingDescriptors:@[sortDescriptor]];

            UInt64 bytesPurged = 0;

            /* 遍历需要删除的图片 */
            for (AFCachedImage *cachedImage in sortedImages) {
                [self.cachedImages removeObjectForKey:cachedImage.identifier];
                /* 记录已经删除的内存的大小 */
                bytesPurged += cachedImage.totalBytes;
                if (bytesPurged >= bytesToPurge) {
                    /* 只要删除剩余的内存达到了60MB则退出 */
                    break;
                }
            }
            
            /* 最后更新一下当前内存使用情况 */
            self.currentMemoryUsage -= bytesPurged;
        }
    });
}

/**
 * 删除图片缓存
 */
- (BOOL)removeImageWithIdentifier:(NSString *)identifier {
    __block BOOL removed = NO;
    dispatch_barrier_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        if (cachedImage != nil) {
            [self.cachedImages removeObjectForKey:identifier];
            self.currentMemoryUsage -= cachedImage.totalBytes;
            removed = YES;
        }
    });
    return removed;
}

/**
 * 删除所有图片缓存
 */
- (BOOL)removeAllImages {
    __block BOOL removed = NO;
    dispatch_barrier_sync(self.synchronizationQueue, ^{
        if (self.cachedImages.count > 0) {
            [self.cachedImages removeAllObjects];
            self.currentMemoryUsage = 0;
            removed = YES;
        }
    });
    return removed;
}

- (nullable UIImage *)imageWithIdentifier:(NSString *)identifier {
    __block UIImage *image = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        image = [cachedImage accessImage];
    });
    return image;
}

/**
 * 以下操作通过网络请求来缓存图片
 * 请求的URL作为标识符
 */
- (void)addImage:(UIImage *)image forRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    [self addImage:image withIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (BOOL)removeImageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    return [self removeImageWithIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (nullable UIImage *)imageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    return [self imageWithIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (NSString *)imageCacheKeyFromURLRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)additionalIdentifier {
    NSString *key = request.URL.absoluteString;
    if (additionalIdentifier != nil) {
        key = [key stringByAppendingString:additionalIdentifier];
    }
    return key;
}

- (BOOL)shouldCacheImage:(UIImage *)image forRequest:(NSURLRequest *)request withAdditionalIdentifier:(nullable NSString *)identifier {
    return YES;
}

@end

#endif
