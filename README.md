# motion_with_audio_arecord
Motion Detection with separate arecord process to capture audio and combine them into single video file

---- Prereqs - Install motion, arecord, ffmpeg pgrep, pkill ----
```
sudo apt update && sudo apt install -y motion alsa-utils procps
```
Modify the motionaudio.sh 
1. Update all the variables with your specific configuration
2. arecord command parameters will need YOUR correct hardware for the microphone input you want to use.
You can see what inputs you have with "aplay  --list-devices"
```
/usr/bin/arecord -f cd -r 22050 -D plughw:2,0 <- change these lines to use the right hardware
```
Copy motionaudio.sh to /usr/bin/
```
sudo cp ./motionaudio.sh /usr/bin/
sudo chmod +x /usr/bin/motionaudio.sh
```

Modify the /etc/motion.conf file
```
target_dir /path/to/motion/videos
movie_filename %m-%d-%Y_%H:%M:%S
on_event_start /bin/bash /usr/bin/motionaudio.sh startaudio %m-%d-%Y_%H:%M:%S
on_event_end  /bin/bash /usr/bin/motionaudio.sh stopaudio
on_camera_lost /bin/bash /usr/bin/motionaudio.sh enablecam
```
# To start motion with audio
```
/bin/bash /usr/bin/motionaudio.sh startmotion
```
# To stop motion with audio
```
/bin/bash /usr/bin/motionaudio.sh stopmotion
```
# Works on Ubuntu 18.04 
