#####################################################################
#   Genymotion Magisk Setup
#####################################################################
#
# Support API level: 23 - 36
#
# For developing Magisk, just use:
# ./build.py emulator
#
# This script will deploy Magisk into Genymotion virtual device.
# It needs that the Genymotion device is running, rooted and adb is connected to it.
#
#####################################################################

mount_tmpfs() {
  # If a file name 'magisk' is in current directory, mount will fail
  mv magisk magisk.tmp
  mount -t tmpfs -o 'mode=0755' magisk $1
  mv magisk.tmp magisk
}

if [ ! -f /system/build.prop ]; then
  # Running on PC
  echo 'Please run `./build.py genymotion` instead of directly executing the script!'
  exit 1
fi

cd /data/local/tmp
chmod 755 busybox

if [ -z "$FIRST_STAGE" ]; then
  export FIRST_STAGE=1
  export ASH_STANDALONE=1
  if [ $(./busybox id -u) -ne 0 ]; then
    # Re-exec script with root
    exec /system/xbin/su 0 /data/local/tmp/busybox sh $0
  else
    # Re-exec script with busybox
    exec ./busybox sh -x $0
  fi
fi

pm install -r -g $(pwd)/magisk.apk

# Extract files from APK
unzip -oj magisk.apk 'assets/util_functions.sh' 'assets/stub.apk'
. ./util_functions.sh

api_level_arch_detect

unzip -oj magisk.apk "lib/$ABI/*" -x "lib/$ABI/libbusybox.so"
for file in lib*.so; do
  chmod 755 $file
  mv "$file" "${file:3:${#file}-6}"
done

if $IS64BIT && [ -e "/system/bin/linker" ]; then
  unzip -oj magisk.apk "lib/$ABI32/libmagisk.so"
  mv libmagisk.so magisk32
  chmod 755 magisk32
fi

if ! mount -o remount,rw /; then
  echo "Failed to remount / as read-write "
  echo "Id $(id -u) $(id -g)"
  exit 1
fi


MAGISKBIN=/data/adb/magisk
MAGISKRC=/vendor/etc/init/magisk.rc

# Magisk stuff
mkdir -p $MAGISKBIN 2>/dev/null
unzip -oj magisk.apk 'assets/*.sh' -d $MAGISKBIN
mkdir /data/adb/modules 2>/dev/null
mkdir /data/adb/post-fs-data.d 2>/dev/null
mkdir /data/adb/service.d 2>/dev/null

for file in magisk magisk32 magiskpolicy stub.apk; do
  chmod 755 ./$file
  cp -af ./$file $MAGISKBIN/$file
done
cp -af ./magiskboot $MAGISKBIN/magiskboot
cp -af ./magiskinit $MAGISKBIN/magiskinit
cp -af ./busybox $MAGISKBIN/busybox

# Create magisk.rc init script to mimic magiskinit boot deployment without patching the boot image
# TODO: this is a workaround for Genymotion, but patching the boot image should be the proper way to do it
cat <<EOF > $MAGISKRC
on post-fs-data
    mkdir /debug_ramdisk/
    mount tmpfs none /debug_ramdisk mode=0755
    copy $MAGISKBIN/magiskpolicy /debug_ramdisk/magiskpolicy
    chmod 755 /debug_ramdisk/magiskpolicy
    symlink /debug_ramdisk/magiskpolicy /debug_ramdisk/supolicy
    copy $MAGISKBIN/magisk /debug_ramdisk/magisk
    chmod 755 /debug_ramdisk/magisk
    copy $MAGISKBIN/magisk32 /debug_ramdisk/magisk32
    chmod 755 /debug_ramdisk/magisk32    
    symlink /debug_ramdisk/magisk /debug_ramdisk/su
    symlink /debug_ramdisk/magisk /debug_ramdisk/resetprop
    mkdir /debug_ramdisk/.magisk
    mkdir /debug_ramdisk/.magisk/device
    mkdir /debug_ramdisk/.magisk/worker
    mount tmpfs none /debug_ramdisk/.magisk/worker mode=0755
    copy $MAGISKBIN/config /debug_ramdisk/.magisk/config
    copy $MAGISKBIN/stub.apk /debug_ramdisk/stub.apk

    start logd
    start magisk-preinit-dev
    start magisk-post-fs

service magisk-preinit-dev /debug_ramdisk/magisk --preinit-device
    disabled
    setenv MAKEDEV 1
    setenv MAGISKTMP /debug_ramdisk
    user root
    seclabel u:object_r:system_file:s0
    oneshot

service magisk-post-fs /debug_ramdisk/magisk --post-fs-data
    disabled
    user root
    seclabel u:object_r:system_file:s0
    oneshot

on property:vold.decrypt=trigger_restart_framework
    start magisk-svc

on nonencrypted
    start magisk-svc

service magisk-svc /debug_ramdisk/magisk --service
    disabled
    user root
    seclabel u:object_r:system_file:s0
    oneshot

on property:sys.boot_completed=1
    start magisk-boot

service magisk-boot /debug_ramdisk/magisk --boot-complete
    disabled
    user root
    seclabel u:object_r:system_file:s0
    oneshot
EOF

chmod 644 $MAGISKRC
