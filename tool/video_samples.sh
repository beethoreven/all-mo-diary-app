#!/bin/sh
# Makes the sample videos the emulator video test needs (integration_test/video_channel_test.dart)
# and copies them into the debug app's files/video_samples/ folder on an emulator.
#
# Needs ffmpeg and adb on the PATH, and the debug app installed on the emulator
# (flutter build apk --debug, then adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk).
#
#   tool/video_samples.sh [emulator-serial]
#
# Emulators only: the test this prepares removes the app (and with it every diary) when it ends,
# so a real phone is refused here, before anything is copied.
set -eu

PKG=tw.com.tutorarthur.allmodiary
ADB="adb${1:+ -s $1}"
if [ "$($ADB shell getprop ro.kernel.qemu | tr -d '\r')" != "1" ]; then
  echo "This device is not an emulator; stopping. Name an emulator: tool/video_samples.sh emulator-5554" >&2
  exit 1
fi
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
cd "$DIR"

gen() { ffmpeg -hide_banner -loglevel error -y "$@"; }
sine() { echo "sine=frequency=$1:sample_rate=$2"; }

# 1080p at 60 frames a second with stereo sound; written as QuickTime so that it carries where it
# was "filmed" the way phone cameras write it (the ©xyz box).
gen -f lavfi -i "testsrc2=size=1920x1080:rate=60" -f lavfi -i "$(sine 440 48000)" -t 10 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -b:v 12M -c:a aac -b:a 256k -ac 2 \
  -metadata location="+25.0330+121.5654/" -metadata creation_time="2026-11-01T08:00:00Z" -f mov land60.mp4
# Filmed upright: stored sideways with a rotation mark, as phones do.
gen -f lavfi -i "testsrc2=size=1920x1080:rate=30" -f lavfi -i "$(sine 660 44100)" -t 6 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac upright_src.mp4
gen -display_rotation 90 -i upright_src.mp4 -c copy portrait_rot.mp4
rm upright_src.mp4
# No sound.
gen -f lavfi -i "testsrc2=size=1280x720:rate=30" -t 5 -c:v libx264 -preset veryfast -pix_fmt yuv420p -an silent.mp4
# Longer than a diary video may be.
gen -f lavfi -i "testsrc2=size=640x360:rate=30" -f lavfi -i "$(sine 330 44100)" -t 150 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 96k long150.mp4
# Smaller than a diary video is stored at.
gen -f lavfi -i "testsrc2=size=320x240:rate=30" -f lavfi -i "$(sine 330 44100)" -t 4 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac small.mp4

$ADB shell "run-as $PKG mkdir -p files/video_samples"
for f in *.mp4; do
  $ADB push "$f" "/data/local/tmp/$f" >/dev/null
  # The app can't read /data/local/tmp itself: the shell reads the file and hands it over.
  $ADB shell "cat /data/local/tmp/$f | run-as $PKG sh -c 'cat > files/video_samples/$f'"
  $ADB shell "rm /data/local/tmp/$f"
done
$ADB shell "run-as $PKG ls -l files/video_samples"
