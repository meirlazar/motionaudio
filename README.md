# motion_with_audio_arecord

# Purpose: 
This project uses the popular motion (https://github.com/Motion-Project/motion) (Motion Detection and recording) Linux application. 
This project adds a separate audio recording process using 'arecord', that starts recording when the video recording process is initiated by motion
It also stops recording when the video recording process stops, terminated by motion. 
Then the audio and video files are merged using ffmpeg into a single file (mkv or mp4).

# Prereqs 
1. Install motion, arecord, ffmpeg pgrep, pkill, v4l2-utils 
```
sudo apt update && sudo apt install -y motion alsa-utils procps v4l-utils
```

3. Modify the motionaudio.sh 
  - Update all the variables with your specific configuration
  - To find your available video recording devices, you can use the following command;
```
v4l-utils --list-devices
```

3. Optional: You can specify the microphone input hardware to use for the 'arecord' command line parameters.
   - To find what microphone input hardware you have installed, you can use this command; 
```
aplay  --list-devices
``` 
Then change this line in the motionaudio.sh to use the hardware of your choice;
```
/usr/bin/arecord -f cd -r 22050 -D plughw:2,0
```

5. Download or Copy the file in this project 'motionaudio.sh' file to /usr/bin/ and make it executable
```
sudo cp ./motionaudio.sh /usr/bin/
sudo chmod +x /usr/bin/motionaudio.sh
```

6. Modify the '/etc/motion/motion.conf' file installed from the motion application 
```
  target_dir /path/to/motion/videos
  movie_filename %Y%m%d_%H%M%S
  on_event_start /bin/bash /usr/bin/motionaudio.sh StartAudioCapture %Y%m%d_%H%M%S
  on_event_end  /bin/bash /usr/bin/motionaudio.sh StopAudioCapture
  on_camera_lost /bin/bash /usr/bin/motionaudio.sh EnableWebCam
```
  
7. Then when your ready to start using motion - instead of running motion directly, use the following command; 
```
/bin/bash /usr/bin/motionaudio.sh StartMotion
```

9. To terminate motion (and the audio) - instead of killign motion directly, use the following command; 
```
/bin/bash /usr/bin/motionaudio.sh StopMotion
```

Note: Works on Ubuntu 18.04 - 23.04
