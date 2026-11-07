# jexi-ai

iOS 上的本地 AI 超分工具：选一张（或多张）照片，用 Core ML 在设备上放大 4 倍，
顺手把机型、时间、定位等元数据写进结果，另存为新照片——原图不动，全程不联网。

Objective-C + UIKit，程序化界面（无 Swift、无 storyboard、无第三方依赖），
以越狱设备上的 .deb 形式分发，`com.liu.jexiai`。

## 功能

- **AI 超分**：Real-ESRGAN 4×（高质量）与 Fast-SRGAN（快速）两个内置模型，也可导入自备的
  `.mlmodel` / `.mlpackage`。按块推理、32px 重叠 + 线性羽化拼接，输出长边上限 4032。
- **元数据**：写入这台设备的真实机型/系统、按机型匹配的镜头与曝光参数、时间与时区、
  当前定位或附近随机位置；也可选择不写并按需抹掉原有 GPS。
- **输出**：默认 HEIF，可选原格式或 JPEG；文件名留空时按相机规则续号（IMG_0896…）。
- **批量**：一次选多张，逐张处理，进度条 + 总体剩余时间，随时可取消。
- 结果通过 `PHAssetCreationRequest` 另存，原图与原始信息不被修改。

## 模型

| 内置模型 | 输入 | 输出 | 许可 |
| --- | --- | --- | --- |
| Real-ESRGAN 4× | 固定 512×512 | 2048×2048 | BSD-3-Clause（xinntao/Real-ESRGAN） |
| Fast-SRGAN | 固定 256×256 | 1024×1024 | MIT（HasnainRaz/Fast-SRGAN） |

Core ML 转换来自 [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models)。
权重不进仓库（67 MB），首次构建前按 `AGENTS.md` 里的命令下载到 `Models/`。

## 构建

设备上用 [Apelin](https://github.com/owngoal-dev/Apelin)（workspace 项目）：

```sh
apelin_project_build       # 运行 apelin/build.sh：clang → ldid 签名 → dpkg-deb
apelin_package_install     # 装到 /Applications/JexiAI.app
```

`apelin/build.sh` 不依赖 Theos；roothide 编 arm64e，rootless 编 arm64 + arm64e 再 lipo。

## 自测

`Tools/` 下是几个命令行工具（下载器、规格探针、内核自测、EXIF 检查、图标生成），
用法见 [AGENTS.md](AGENTS.md)。内核自测覆盖通道顺序、单块一致性、拼接接缝与大图内存。

## 许可

源码 MIT，见 [LICENSE](LICENSE)。内置模型权重遵循各自原项目的许可，见
[Resources/LICENSES.txt](Resources/LICENSES.txt)。
