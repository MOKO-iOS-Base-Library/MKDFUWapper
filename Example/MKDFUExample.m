// 导入头文件
#import <MKDFUWapper/MKDFUWapper-Swift.h>

// 遵循代理
@interface MyViewController () <MKDFUWrapperDelegate>
@property (nonatomic, strong) MKDFUWrapper *dfuWrapper;
@end

// 开始 DFU
- (void)startDFU {
    NSData *firmwareData = [NSData dataWithContentsOfFile:firmwarePath];
    self.dfuWrapper = [[MKDFUWrapper alloc] init];
    self.dfuWrapper.delegate = self;
    [self.dfuWrapper startDFUWithPeripheral:connectedPeripheral
                               firmwareData:firmwareData];
}

// 实现代理方法（回调已在主线程，可直接更新 UI）
- (void)dfuProgressDidChange:(float)progress {
    self.progressView.progress = progress;  // 直接更新 UI
}
- (void)dfuDidComplete { /* 升级完成 */ }
- (void)dfuDidFailWithError:(NSString *)error { /* 升级失败 */ }
