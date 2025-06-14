#!/bin/bash

# === Usage Check ===
if [ $# -lt 3 ]; then
  echo "Usage: $0 <num_frames> <exposure_time_seconds> <iso> [start_index] [min_temp] [max_temp]"
  echo "Example: $0 20 210 800 [5] [25 27]"
  exit 1
fi

# === Command-line arguments ===
NUM_FRAMES="$1"
EXPOSURE="$2"
ISO="$3"
START_INDEX="${4:-1}"
MIN_TEMP="${5:-15}"
MAX_TEMP="${6:-45}"

# === Constants ===
INTERVAL=5
DATE=$(date +"%Y%m%d")
BASE_DIR="$HOME/Pictures/astro/dark_library/${EXPOSURE}s_ISO${ISO}"
mkdir -p "$BASE_DIR"

echo "📷 Capturing $NUM_FRAMES dark frames at ${EXPOSURE}s, ISO ${ISO}"
echo "📂 Base directory: $BASE_DIR"
echo "🔢 Starting at frame number: $START_INDEX"
echo "🌡 Accepting temperature range: ${MIN_TEMP}–${MAX_TEMP}°C"

# === Configure camera ISO ===
echo "Setting ISO to $ISO..."
gphoto2 --set-config iso=$ISO

# === If exposure > 30, switch to bulb mode ===
USE_BULB=false
if [ "$EXPOSURE" -gt 30 ]; then
  echo "Using BULB mode for $EXPOSURE second exposures..."
  gphoto2 --set-config shutterspeed=bulb
  USE_BULB=true
else
  echo "Setting shutterspeed to $EXPOSURE seconds..."
  gphoto2 --set-config shutterspeed=$EXPOSURE
fi

# === Capture loop ===
END_INDEX=$((START_INDEX + NUM_FRAMES - 1))
for i in $(seq -f "%02g" $START_INDEX $END_INDEX); do
  echo "⏱ Frame $i of $END_INDEX..."

  TMP_FILENAME="dark_tmp_${DATE}_$i.cr2"

  if [ "$USE_BULB" = true ]; then
    echo "Starting BULB exposure for ${EXPOSURE}s..."
    sleep 1
    gphoto2 --set-config eosremoterelease="Immediate" --wait-event="${EXPOSURE}s" > /dev/null 2>&1
    echo "Exposure complete. Downloading image..."

    gphoto2 --get-all-files --force-overwrite --filename "$BASE_DIR/$TMP_FILENAME"
    gphoto2 --delete-all-files --quiet
  else
    gphoto2 --capture-image-and-download --filename "$BASE_DIR/$TMP_FILENAME"
  fi

  sleep "$INTERVAL"
done

# === Initialize counters ===
COUNT_KEPT=0
COUNT_TOO_COLD=0
COUNT_TOO_HOT=0

# === Process files: filter by temperature, organize ===
echo "🌡 Grouping files by temperature..."

for file in "$BASE_DIR"/dark_tmp_${DATE}_*.cr2; do
  RAW_TEMP=$(exiftool -s3 -CameraTemperature "$file" 2>/dev/null)

  if [ -z "$RAW_TEMP" ]; then
    echo "⚠️ Skipping $file (no temperature found)"
    rm "$file"
    continue
  fi

  RAW_TEMP_CLEAN=$(echo "$RAW_TEMP" | sed 's/[^0-9.-]*//g')
  TEMP_VAL=$(printf "%.0f" "$RAW_TEMP_CLEAN")

  if [ "$TEMP_VAL" -lt "$MIN_TEMP" ]; then
    echo "❌ $file discarded (too cold: ${TEMP_VAL}°C)"
    rm "$file"
    ((COUNT_TOO_COLD++))
    continue
  elif [ "$TEMP_VAL" -gt "$MAX_TEMP" ]; then
    echo "❌ $file discarded (too hot: ${TEMP_VAL}°C)"
    rm "$file"
    ((COUNT_TOO_HOT++))
    continue
  fi

  TEMP_CLEAN=${RAW_TEMP// /}
  TEMP_DIR="${BASE_DIR}/${TEMP_CLEAN}"
  mkdir -p "$TEMP_DIR"

  FRAME=$(echo "$file" | grep -oE '[0-9]{2}\.cr2' | cut -d. -f1)
  NEWNAME="dark_${EXPOSURE}s_ISO${ISO}_${TEMP_CLEAN}_${DATE}_${FRAME}.cr2"

  mv "$file" "$TEMP_DIR/$NEWNAME"
  echo "✅ $NEWNAME → $TEMP_DIR"
  ((COUNT_KEPT++))
done

if [ -n "$BASE_DIR" ]; then
	echo "Cleaning up any empty directories..."
  find "$BASE_DIR" -type d -empty -delete
fi

# === Summary ===
echo ""
echo "📊 Summary:"
echo "✅ Kept:        $COUNT_KEPT"
echo "❄️ Too cold:    $COUNT_TOO_COLD"
echo "🔥 Too warm:    $COUNT_TOO_HOT"
echo ""
echo "🎉 Finished capturing and organizing $NUM_FRAMES dark frames."