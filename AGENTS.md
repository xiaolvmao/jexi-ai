# jexi-ai

An iOS app that does one thing: AI super-resolution of a photo, on device, with
Core ML. Objective-C + UIKit,程序化界面（无 storyboard、无 Swift、无 xib）。

独立于 Melon 项目（那是 EXIF 编辑 App），界面与代码都不共用。

## 布局

```
Sources/            推理内核与 App 源码（App 部分后续加入）
Tools/              命令行工具（下载器、规格探针、内核自测）
Models/             .mlmodel 权重（不提交，见下）
Resources/          Info.plist、图标、许可文本
apelin/build.sh     构建脚本（clang + ldid + dpkg-deb）
```

## 模型

| 内置模型 | 文件 | 输入 | 输出 | 单块耗时（A17 Pro） |
| --- | --- | --- | --- | --- |
| Real-ESRGAN 4x（主） | `Models/RealESRGAN4x.mlmodel` | **固定 512×512** BGRA | 2048×2048 | ≈2.4 s，峰值 +64 MB |
| Fast-SRGAN（快） | `Models/FastSRGAN.mlmodel` | **固定 256×256** BGRA | 1024×1024 | ≈0.06 s，峰值 +16 MB |

两者都来自 [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models)
（README 里 "Image(RGB …)" 那列写的是**输出**尺寸，输入其实是固定的方块，
多一像素都会被 Core ML 拒绝：`Image size 1024 x 1024 not in allowed set of image sizes`）。

- Real-ESRGAN：原始项目 [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)，BSD-3-Clause。
  下载（与 john-rocky 的 Drive 文件字节数一致，66857221 字节）：
  `https://raw.githubusercontent.com/JacopoMangiavacchi/CoreML-Real-ESRGAN/main/realesrgan512.mlmodel`
- Fast-SRGAN：原始项目 [HasnainRaz/Fast-SRGAN](https://github.com/HasnainRaz/Fast-SRGAN)，MIT。
  下载：`https://docs.google.com/uc?export=download&id=1gYXbhcSUm5rhcCAmwLruonAhu8jvyDL8&confirm=t`（642825 字节）

### 下载（设备上没有 curl/wget）

```sh
cd Tools && clang -arch arm64e -fobjc-arc -O2 -o fetchmodel fetchmodel.m -framework Foundation \
  && ldid -STool.entitlements fetchmodel
cd .. && ./Tools/fetchmodel '<url>' "${APELIN_PROJECT_ROOT:?}/Models/<name>.mlmodel"
```

`drive.google.com/uc?...` 在本机网络下返回 Google 的 404 页；换成
`docs.google.com/uc?export=download&id=…&confirm=t` 就可以（206/200 正常）。
小工具跑起来的路径要给**内核视角的真实路径**：shell 的 `$PWD` 在 roothide 上是
vroot 化的，工具用它拼出来的路径打不开；用 `$APELIN_PROJECT_ROOT`。

## 推理内核（`Sources/JXUpscaler.{h,m}`）

- 模型输入固定方块，所以按块处理：块大小即模型输入边长，块间重叠
  `overlapPixels`（默认 32 个**输出**像素，4x 即 8 个源像素），相邻块在重叠带里
  线性羽化后写进目标缓冲区（左/上边缘交叉淡入），只保留「目标图 + 当前块」，
  不累积所有块的输出。
- 输出长边上限 `maxOutputEdge`，默认 **4096**。超过时先用 vImage 高质量降采样
  （`vImageScale_ARGB8888`，无 GPU），再超分；`didPrescale` 告诉界面"已按上限处理"。
- 进度回调给出「已完成块数 / 总块数 / 每块平均秒数」，取消块在块边界轮询。
- 实测：Real-ESRGAN 1024×768 → 4096×3072 用 16.3 s / 6 块；
  3000×2000 → 4096×2732 用 14.3 s，峰值内存 +43 MB。Fast-SRGAN 同一张 0.9 s。

## 自测

```sh
cd Tools && clang -arch arm64e -fobjc-arc -O2 -I../Sources -o selftest selftest.m \
  ../Sources/JXUpscaler.m -framework Foundation -framework CoreML -framework CoreVideo \
  -framework Accelerate && ldid -STool.entitlements selftest
cd .. && ./Tools/selftest Models/FastSRGAN.mlmodel Models/RealESRGAN4x.mlmodel --big
```

覆盖：模型加载与规格、单块输出尺寸、BGRA 通道顺序（源图左蓝/中绿/右红，
输出必须同序）、动态范围、单块分块结果与直接推理逐字节一致（`max diff 0`）、
多块拼接接缝处的平均梯度不超过整图 3 倍、大图按上限降采样、峰值内存。

规格探针：`./Tools/modelprobe <model> --sizes 512,2048 --runs 3` 会打印
`MLModelDescription` 的每个输入输出、`MLImageConstraint` 的枚举尺寸/范围/像素格式，
并实测耗时与 `phys_footprint`。

## 踩过的坑

- 工具链接完必须 `ldid -STool.entitlements`（含 IOKit user client 类），否则
  Core ML 在 GPU/ANE 上起不来或进程直接被杀。
- `sysctl`/`/tmp` 在两个世界里不是同一个目录：工具看到的 `/tmp` 与 shell 的不是一处。
- iOS 17.4 SDK 里没有 `MLFeatureTypeState`；`MLImageSizeConstraint` 没有
  `pixelsWideRangeStep`，只有 `pixelsWideRange` / `pixelsHighRange`。
- 自测里 BGRA 的内存序是 B,G,R,A：源图"左边纯蓝"是我故意画的，判据按这个来。
