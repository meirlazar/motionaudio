#!/bin/bash

# directories
moviedir=${HOME}/motion/$(date +'%F') # change this to where the motion process stores the video files

# motion files
motionconf=/etc/motion/motion.conf # path to motion config dir
motionpid=/var/run/motion/motion.pid # path to motion pid file (use 'daemon on' setting and process_id_file /path/to/motion.pif in motion.conf)

# Please note the '/etc/motion.conf' should have the following info filled out 
# Make sure they are not commented out in that file, leave them commented in this file
#target_dir /path/to/motion/videos
#movie_filename %m-%d-%Y_%H:%M:%S
#on_event_start /bin/bash /usr/bin/motionaudio.sh startaudio %m-%d-%Y_%H:%M:%S
#on_event_end  /bin/bash /usr/bin/motionaudio.sh stopaudio
#on_camera_lost /bin/bash /usr/bin/motionaudio.sh enablecam

# find your default available video recording device or select manually
webcam=$(v4l-utils --list-devices | head -2 | tail -1)
webcam=${webcam:=/dev/video0} 

# parameters
action=$1   # specify which action to take start, stop, merge, etc
audio=$2  # use this option to specify the audio file format example:

# extensions of files
audioext=wav # change if you prefer a different audio format or extension
vidext=avi # change this to what is specified in the motion.conf file for the line ffmpeg_video_codec
vidoutext=mkv #change this to the video file that will be created by joining the audio and video files



# check deps
reqbins="ffmpeg arecord motion pgrep pkill"
if [[ ! -f ${motionpid:=/var/run/motion/motion.pid} ]]; then motionpid=$(grep "^process_id_file" <"${motionconf:=/etc/motion/motion.conf}" | cut -d" " -f2); fi
for x in "${reqbins}"; do
	if ! which ${x} > /dev/null 2>&1; then 
		echo "${x} not installed. Please install and run script again"; exit 1;	
	fi
done
		

# ALL FUNCTIONS 
		
function EnableCam () {
# check webcam is working
	if [[ ! -c ${webcam:=/dev/video0} ]]; then
		grep -q "^blacklist uvcvideo$" <"/etc/modprobe.d/blacklist.conf" || sudo sed -i 's/^blacklist uvcvideo/#blacklist uvcvideo/1' /etc/modprobe.d/blacklist.conf
	sudo modprobe -a uvcvideo; sleep 1
	fi
}

function StartMotion () {
# check motion is already running
	if [[ $(pgrep -a -if "motion -c ${motionconf:=/etc/motion/motion.conf}" 2> /dev/null) ]] || [[ $(pgrep -F ${motionpid:=/var/run/motion/motion.pid} 2> /dev/null) ]]; then
		echo "FAIL - Motion process already started"; return;
	fi
EnableCam
# start motion process
	sudo nohup motion -c ${motionconf:=/etc/motion/motion.conf} &
	newmotpid=${BASHPID}
	grep -q "${newmotpid}" <"${motionpid}" || echo "${newmotpid}" | sudo tee ${motionpid}
}


function StopMotion () {
# kill motion
	if [[ $(pgrep -F ${motionpid:=/var/run/motion/motion.pid} 2> /dev/null) ]] || [[ $(pgrep -a -if "motion -c ${motionconf:=/etc/motion/motion.conf}" 2> /dev/null) ]]; then
        sudo pkill -9 -F ${motionpid} 2> /dev/null || sudo pkill -9 -f "motion -c ${motionconf}" 2> /dev/null
        else
        echo "Motion is not running"  
        fi
# blacklist the video camera (optional)
	grep -q "^#blacklist uvcvideo$" <"/etc/modprobe.d/blacklist.conf" && sudo sed -i 's/#blacklist uvcvideo/blacklist uvcvideo/1' /etc/modprobe.d/blacklist.conf
}

function StopAudio () {
	pgrep -F ${moviedir:="$HOME/motion/$(date +'%F')"}/*.pid 2> /dev/null && sudo pkill -9 -F ${moviedir}/*.pid
	pgrep -a -if "arecord -f cd -r 22050" 2> /dev/null && sudo pkill -9 -f "arecord -f cd -r 22050"
}

function StartAudio () {
	audio=${audio="$(grep '^movie_filename' <"${motionconf}" | cut -d " " -f2-)"}
	/usr/bin/arecord -f cd -r 22050 "${moviedir:="$HOME/motion/$(date +'%F')"}/${audio}.${audioext:=wav}" --process-id-file "${moviedir}/${audio}.pid" &
	# or use audio record with  a specific device, uncomment this line below and comment out the line above
	# /usr/bin/arecord -f cd -r 22050 -D plughw:2,0 "${moviedir}/${audio}.${audioext}" --process-id-file "${moviedir}/${audio}.pid" &
}


function MergeAudio () {
mediafiles=$(find ${moviedir:="$HOME/motion/$(date +'%F')} -type f -iname "*.${audioext:=wav}" -printf "%f\n" -o -iname "*.${vidext:=avi}" -printf "%f\n" | cut -d. -f1 | sort -u)
	while read -r x; do
		if [[ ! -f "${moviedir}/${x}.${audioext}" || ! -f "${moviedir}/${x}.${vidext}" ]]; then continue; fi
		ffmpeg -y -i "${moviedir}/${x}.${vidext}" -i "${moviedir}/${x}.${audioext}" -c:v copy -c:a copy "${moviedir}/${x}.${vidoutext:=mkv}" &&
		rm -f "${moviedir}/${x}".{$audioext,$vidext,pid} > /dev/null 2>&1
	done <<< "${mediafiles}"
	exit
}

# Main Script
case ${action,,} in
enablecam ) EnableCam ;;
startmotion ) StartMotion ;;
stopmotion ) StopMotion; StopAudio; MergeAudio ;;
startaudio ) StopAudio; StartAudio ;;
stopaudio ) StopAudio; MergeAudio ;;
merge ) MergeAudio ;;
esac
