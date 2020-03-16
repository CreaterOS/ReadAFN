//
//  ViewController.m
//  ReadAFC
//
//  Created by Bryant Reyn on 2020/3/9.
//  Copyright © 2020 Bryant Reyn. All rights reserved.
//

#import "ViewController.h"
#import "AFNetworking/AFNetworking.h"
#import "UIKit+AFNetworking/UIImageView+AFNetworking.h"


@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    
    UIImageView *imageV = [[UIImage alloc] init];
    [imageV setImageWithURL:<#(nonnull NSURL *)#> placeholderImage:<#(nullable UIImage *)#>];
    
    
    
    
    
    
    
    
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    
    
    /*
    AFNetworkReachabilityManager *reachabilityManager = [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        ;
    }];*/
    
    
    
    NSURLSessionDataTask *task = [manager GET:<#(nonnull NSString *)#> parameters:<#(nullable id)#> headers:<#(nullable NSDictionary<NSString *,NSString *> *)#> progress:<#^(NSProgress * _Nonnull downloadProgress)downloadProgress#> success:<#^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)success#> failure:<#^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)failure#>];
    [manager POST:<#(nonnull NSString *)#> parameters:<#(nullable id)#> headers:<#(nullable NSDictionary<NSString *,NSString *> *)#> progress:<#^(NSProgress * _Nonnull uploadProgress)uploadProgress#> success:<#^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)success#> failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        <#code#>
    }];
    [manager downloadTaskWithRequest:<#(nonnull NSURLRequest *)#> progress:<#^(NSProgress * _Nonnull downloadProgress)downloadProgressBlock#> destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        <#code#>
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        <#code#>
    }];
    [manager uploadTaskWithRequest:<#(nonnull NSURLRequest *)#> fromData:<#(nullable NSData *)#> progress:<#^(NSProgress * _Nonnull uploadProgress)uploadProgressBlock#> completionHandler:<#^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error)completionHandler#>];
}


@end
