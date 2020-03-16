// UIImageView+AFNetworking.m
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

#import "UIImageView+AFNetworking.h"

/* runtime */
#import <objc/runtime.h>

#if TARGET_OS_IOS || TARGET_OS_TV

#import "AFImageDownloader.h"

@interface UIImageView (_AFNetworking)
@property (readwrite, nonatomic, strong, setter = af_setActiveImageDownloadReceipt:) AFImageDownloadReceipt *af_activeImageDownloadReceipt;
@end

@implementation UIImageView (_AFNetworking)

/**
 * 在分类中不能直接使用@property来实现 -- 不会自动创建实例
 * 因此需要动态创建成员属性
 * 手动创建setter方法和getter方法
 */

/* setter方法 */
- (AFImageDownloadReceipt *)af_activeImageDownloadReceipt {
    return (AFImageDownloadReceipt *)objc_getAssociatedObject(self, @selector(af_activeImageDownloadReceipt));
}


/* getter方法 */
- (void)af_setActiveImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt {
    /* OBJC_ASSOCIATION_RETAIN_NONATOMIC -- nonatomic strong */
    objc_setAssociatedObject(self, @selector(af_activeImageDownloadReceipt), imageDownloadReceipt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark -

@implementation UIImageView (AFNetworking)

+ (AFImageDownloader *)sharedImageDownloader {
    return objc_getAssociatedObject([UIImageView class], @selector(sharedImageDownloader)) ?: [AFImageDownloader defaultInstance];
}

+ (void)setSharedImageDownloader:(AFImageDownloader *)imageDownloader {
    objc_setAssociatedObject([UIImageView class], @selector(sharedImageDownloader), imageDownloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* 扩展原来的功能，因此使用了分类 */
#pragma mark -

- (void)setImageWithURL:(NSURL *)url {
    [self setImageWithURL:url placeholderImage:nil];
}

/**
 * 设置图片 -- 网络图片
 * 参数
 * 1.图片的url
 * 2.占位图片 -- 当网络加载延迟或者加载失败时采用占位图片
 */
- (void)setImageWithURL:(NSURL *)url
       placeholderImage:(UIImage *)placeholderImage
{
    /* 将url封装成请求 */
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    /* 如果使用下载，会报错，不是JSON类型，因此需要自己设置NSSet设置，使用此方法可以自动甚至图片类型的下载 */
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];

    /* 设置图片 */
    [self setImageWithURLRequest:request placeholderImage:placeholderImage success:nil failure:nil];
}

- (void)setImageWithURLRequest:(NSURLRequest *)urlRequest
              placeholderImage:(UIImage *)placeholderImage
                       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *image))success
                       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure
{
    /* 如果url为空，则使用占位图 */
    if ([urlRequest URL] == nil) {
        self.image = placeholderImage;
        if (failure) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            failure(urlRequest, nil, error);
        }
        return;
    }
    
    /* 如果当前正在下载，就不处理 */
    if ([self isActiveTaskURLEqualToURLRequest:urlRequest]) {
        return;
    }
    
    /* 先取消下载任务 -- 一进来没有问题就先取消一次下载任务 */
    [self cancelImageDownloadTask];

    
    AFImageDownloader *downloader = [[self class] sharedImageDownloader];
    /* 获得图片缓存 -- 如果下载过了就会有图片缓存 */
    id <AFImageRequestCache> imageCache = downloader.imageCache;

    //Use the image from the image cache if it exists
    UIImage *cachedImage = [imageCache imageforRequest:urlRequest withAdditionalIdentifier:nil];
    if (cachedImage) {
        if (success) {
            success(urlRequest, nil, cachedImage);
        } else {
            self.image = cachedImage;
        }
        [self clearActiveDownloadInformation];
    } else {
        
        /* 先赋值一个占位图 */
        if (placeholderImage) {
            self.image = placeholderImage;
        }

        __weak __typeof(self)weakSelf = self;
        
        /* 通过[NSUUID UUID]生成下载ID */
        NSUUID *downloadID = [NSUUID UUID];
        AFImageDownloadReceipt *receipt;
        receipt = [downloader
                   downloadImageForURLRequest:urlRequest
                   withReceiptID:downloadID
                   success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull responseObject) {
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
                       if ([strongSelf.af_activeImageDownloadReceipt.receiptID isEqual:downloadID]) {
                           if (success) {
                               success(request, response, responseObject);
                           } else if (responseObject) {
                               strongSelf.image = responseObject;
                           }
                           [strongSelf clearActiveDownloadInformation];
                       }

                   }
                   failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
                        if ([strongSelf.af_activeImageDownloadReceipt.receiptID isEqual:downloadID]) {
                            if (failure) {
                                failure(request, response, error);
                            }
                            [strongSelf clearActiveDownloadInformation];
                        }
                   }];

        self.af_activeImageDownloadReceipt = receipt;
    }
}

/* 取消图片下载任务 */
- (void)cancelImageDownloadTask {
    if (self.af_activeImageDownloadReceipt != nil) {
        [[self.class sharedImageDownloader] cancelTaskForImageDownloadReceipt:self.af_activeImageDownloadReceipt];
        /* 清除下载信息 */
        [self clearActiveDownloadInformation];
     }
}

/* 清空 */
- (void)clearActiveDownloadInformation {
    self.af_activeImageDownloadReceipt = nil;
}

/* 判断当前下载的图片的路径和传入的路径是否相等 */
- (BOOL)isActiveTaskURLEqualToURLRequest:(NSURLRequest *)urlRequest {
    /* 采用了链式操作 */
    return [self.af_activeImageDownloadReceipt.task.originalRequest.URL.absoluteString isEqualToString:urlRequest.URL.absoluteString];
}

@end

#endif
