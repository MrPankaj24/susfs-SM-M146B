#!/bin/bash
set -e

# --- CONFIGURATION ---
# 1. Defconfig: Verify this name in arch/arm64/configs/ of your source
DEFCONFIG_NAME="s5e8535_defconfig" 

# 2. Kernel Repo
KERNEL_REPO="https://github.com/MrPankaj24/SM-M146B-Kernel-Source.git"
KERNEL_BRANCH="master" 

# 3. SUSFS Branch for Android 13 GKI (Kernel 5.15)
# Explicitly using the android13-5.15 branch as requested
SUSFS_BRANCH="gki-android13-5.15"
# ---------------------

# Setup Directories
mkdir -p ./builds
cd ./builds
WORK_DIR="android-5.15-M14-A13-$(date +'%Y-%m-%d-%H%M')"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone Repositories
echo "Cloning Kernel Source..."
git clone "$KERNEL_REPO" -b "$KERNEL_BRANCH" android_kernel

echo "Cloning AnyKernel3..."
git clone https://github.com/TheWildJames/AnyKernel3.git -b android12-5.10 AnyKernel3

echo "Cloning SUSFS ($SUSFS_BRANCH)..."
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"

# Enter Kernel Directory
cd android_kernel

# Install KernelSU
echo "Installing KernelSU..."
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

# Patch SUSFS
echo "Applying SUSFS patches for Android 13 GKI..."
# Copy fs and include files
cp ../susfs4ksu/kernel_patches/fs/* ./fs/
cp ../susfs4ksu/kernel_patches/include/linux/* ./include/linux/

# Apply the kernel-side patch (Specifically for android13-5.15)
# We use a wildcard (*) here because the patch name might include version numbers (e.g., v1.5.5)
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch ./
patch -p1 < 50_add_susfs_in_gki-android13-5.15.patch

# Apply the KernelSU-side patch
cp ../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch ./KernelSU/
cd KernelSU
patch -p1 < 10_enable_susfs_for_ksu.patch
cd ..

# Configure Kernel
echo "Configuring Kernel ($DEFCONFIG_NAME)..."
export ARCH=arm64
export SUBARCH=arm64

# Apply defconfig
make "$DEFCONFIG_NAME"

# Enable KSU and SUSFS in .config
echo "Enabling KSU and SUSFS in .config..."
./scripts/config --file .config \
    --enable CONFIG_KSU \
    --enable CONFIG_KSU_SUSFS \
    --enable CONFIG_KSU_SUSFS_SUS_PATH \
    --enable CONFIG_KSU_SUSFS_SUS_MOUNT \
    --enable CONFIG_KSU_SUSFS_SUS_KSTAT \
    --enable CONFIG_KSU_SUSFS_SUS_OVERLAYFS \
    --enable CONFIG_KSU_SUSFS_TRY_UMOUNT \
    --enable CONFIG_KSU_SUSFS_SPOOF_UNAME \
    --enable CONFIG_KSU_SUSFS_ENABLE_LOG \
    --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT \
    --enable CONFIG_KSU_SUSFS_SUS_SU

# Build Kernel
echo "Building Image..."
# Adjust -j$(nproc) to your CPU core count
make -j$(nproc) Image

# Package
echo "Packaging..."
if [ -f "arch/arm64/boot/Image" ]; then
    cp arch/arm64/boot/Image ../AnyKernel3/
    cd ../AnyKernel3
    zip -r9 "../M14-A13-KSU-SUSFS-$(date +'%H%M').zip" *
    echo "Done! Zip file is in the builds directory."
else
    echo "Error: Image not found. Build failed."
    exit 1
fi
