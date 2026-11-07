#!/bin/sh
# Builds jexi-ai.app into a .deb for the target bootstrap.
# Run by apelin_project_build, which sets the APELIN_* environment.
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
: "${APELIN_PREFIX-}" # empty on roothide, /var/jb on rootless; may be unset
APELIN_PREFIX="${APELIN_PREFIX-}"
: "${APELIN_CONFIGURATION:=debug}"

PACKAGE_ID="com.liu.jexiai"
VERSION="0.1.0"
APP_NAME="JexiAI"

cd "${APELIN_PROJECT_ROOT:?}"

stage="$(mktemp -d "${TMPDIR:?}stage.XXXXXX")"
trap 'rm -rf -- "${stage:?}"' EXIT
app="${stage}${APELIN_PREFIX}/Applications/${APP_NAME}.app"
mkdir -p "${app:?}" "${stage:?}/DEBIAN"

if [ ! -f Models/RealESRGAN4x.mlmodel ] || [ ! -f Models/FastSRGAN.mlmodel ]; then
    echo "missing model weights in Models/ — see AGENTS.md for the download commands" >&2
    exit 1
fi
if [ ! -f Resources/AppIcon60x60@2x.png ]; then
    echo "missing icons in Resources/ — run Tools/icongen first (see AGENTS.md)" >&2
    exit 1
fi

# ---- compile -------------------------------------------------------------
CFLAGS="-fobjc-arc -O2 -ISources -Wall -Wno-unused-parameter"
if [ "${APELIN_CONFIGURATION}" = "release" ]; then
    CFLAGS="${CFLAGS} -DNDEBUG"
fi
case "${APELIN_BOOTSTRAP:?}" in
    roothide) CFLAGS="${CFLAGS} -DAPELIN_BOOTSTRAP_ROOTHIDE=1" ;;
    rootless) CFLAGS="${CFLAGS} -DAPELIN_BOOTSTRAP_ROOTLESS=1" ;;
esac
CFLAGS="${CFLAGS} -DAPELIN_PACKAGE_ID=\"${PACKAGE_ID}\" -DAPELIN_BUILD_ID=\"${APELIN_BUILD_ID}\""

FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreML -framework CoreVideo \
-framework CoreImage -framework CoreGraphics -framework ImageIO -framework Photos \
-framework PhotosUI -framework UniformTypeIdentifiers -framework Accelerate \
-framework CoreLocation"

build_arch() { # $1 arch, $2 output
    clang -arch "$1" ${CFLAGS} -o "$2" Sources/*.m ${FRAMEWORKS}
}

case "${APELIN_BOOTSTRAP:?}" in
    roothide)
        build_arch arm64e "${app:?}/${APP_NAME}"
        ;;
    rootless)
        tmpbin="${stage:?}/bin.$$"
        mkdir -p "${tmpbin:?}"
        build_arch arm64 "${tmpbin:?}/${APP_NAME}.arm64"
        build_arch arm64e "${tmpbin:?}/${APP_NAME}.arm64e"
        lipo -create "${tmpbin:?}/${APP_NAME}.arm64" "${tmpbin:?}/${APP_NAME}.arm64e" \
             -output "${app:?}/${APP_NAME}"
        rm -rf -- "${tmpbin:?}"
        ;;
    *)
        echo "unknown bootstrap ${APELIN_BOOTSTRAP}" >&2
        exit 1
        ;;
esac

chmod 0755 "${app:?}/${APP_NAME}"
ldid -S"${APELIN_PROJECT_ROOT:?}/apelin/App.entitlements" "${app:?}/${APP_NAME}"

# ---- bundle --------------------------------------------------------------
cp Resources/Info.plist "${app:?}/Info.plist"
cp Resources/AppIcon*.png "${app:?}/"
cp Resources/LICENSES.txt "${app:?}/"
cp Models/RealESRGAN4x.mlmodel Models/FastSRGAN.mlmodel "${app:?}/"
chmod 0644 "${app:?}"/*.png "${app:?}"/*.plist "${app:?}"/*.txt "${app:?}"/*.mlmodel

# ---- package -------------------------------------------------------------
cat > "${stage:?}/DEBIAN/control" <<EOF
Package: ${PACKAGE_ID}
Version: ${VERSION}
Architecture: ${APELIN_ARCHITECTURE:?}
Name: jexi-ai
Author: liu
Maintainer: liu
Section: Applications
Priority: optional
Depends: firmware (>= 16.0)
Description: 本地 AI 照片超分
 jexi-ai 用 Core ML 把照片放大 4 倍，全部在设备上完成，不上传任何东西。
 照片经 PHPicker 选取，分块推理，结果按相机口径另存为新照片（默认 HEIF）。
 .
 内置模型
  · Real-ESRGAN 4x —— 原项目 xinntao/Real-ESRGAN，BSD-3-Clause 许可
  · Fast-SRGAN —— 原项目 HasnainRaz/Fast-SRGAN，MIT 许可
 两者的 Core ML 转换来自 john-rocky/CoreML-Models。
 .
 Real-ESRGAN 许可（BSD-3-Clause）：
 Copyright (c) 2021, Xintao Wang
 All rights reserved.
 .
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.
 3. Neither the name of the copyright holder nor the names of its contributors
    may be used to endorse or promote products derived from this software
    without specific prior written permission.
 .
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 .
 Fast-SRGAN 许可（MIT）：
 Copyright (c) 2019 Hasnain Raza
 .
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOF

dpkg-deb -b --root-owner-group "${stage:?}" "${APELIN_PACKAGE_DIR:?}/"
