#!/bin/bash

# ## crontab -e
# # 0 2 * * * /path/to/backup.sh

## backup
container_id="ec7f66a79aaa" # fix to real container_id
cur_date=$(date +%Y%m%d%H%M)
/usr/bin/docker commit -p=false $container_id vpot-bak:$cur_date

# Clean up expired vpot-bak images, keep last 7 days
# Image tag format: vpot-bak:YYYYMMDDHHmm
current_timestamp=$(date +%s)
seven_days_seconds=$((7 * 24 * 3600))
docker images --format "{{.Repository}}:{{.Tag}}" | grep "^vpot-bak:" | while read image_name; do
    tag_time=$(echo "$image_name" | sed 's/^vpot-bak://')
    if ! echo "$tag_time" | grep -qE '^[0-9]{12}$'; then
        echo "Skip: $image_name (invalid format)"
        continue
    fi
    # Convert YYYYMMDDHHmm to timestamp
    year=$(echo "$tag_time" | cut -c1-4)
    month=$(echo "$tag_time" | cut -c5-6)
    day=$(echo "$tag_time" | cut -c7-8)
    hour=$(echo "$tag_time" | cut -c9-10)
    minute=$(echo "$tag_time" | cut -c11-12)
    # Build timestamp using date (compatible with busybox and standard date)
    image_timestamp=$(date -u -d "$year-$month-$day $hour:$minute:00" +%s 2>/dev/null)
    # If above fails, try alternative format
    if [ -z "$image_timestamp" ]; then
        image_timestamp=$(date -u -d "$year$month$day $hour:$minute" +%s 2>/dev/null)
    fi
    if [ -z "$image_timestamp" ]; then
        echo "Skip: $image_name (cannot parse time)"
        continue
    fi
    age=$((current_timestamp - image_timestamp))
    if [ $age -gt $seven_days_seconds ]; then
        echo "Delete: $image_name (time: $tag_time, age: $((age / 86400)) days)"
        docker rmi "$image_name"
    else
        echo "Keep: $image_name (time: $tag_time, age: $((age / 86400)) days)"
    fi
done
echo "Cleanup completed!"
