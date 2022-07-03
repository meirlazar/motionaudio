#!/bin/bash
moviedir=/path/to/motion/video/files # change this to where the motion process stores the video files
motionconf=/etc/motion/motion.conf # path to motion config dir
motionpid=/var/run/motion/motion.pid # path to motion pid file (use 'daemon on' setting and process_id_file /path/to/motion.pif in motion.conf)
webcam=/dev/video0 #webcam
action=$1   # specify which action to take start, stop, merge, etc
audio=$2  # use this option to specify the audio file format example:
aext=wav # change if you prefer a different audio format or extension
vext=avi # change this to what is specified in the motion.conf file for the line ffmpeg_video_codec
voutext=mkv #change this to the video file that will be created by joining the audio and video files

# motion.conf should have the following
#target_dir /path/to/motion/videos
#movie_filename %m-%d-%Y_%H:%M:%S
#on_event_start /bin/bash /etc/motion/motionaudio.sh startaudio %m-%d-%Y_%H:%M:%S
#on_event_end  /bin/bash /etc/motion/motionaudio.sh stopaudio
#on_camera_lost /bin/bash /etc/motion/motionaudio.sh enablecam


# check deps
reqbins="ffmpeg arecord motion pgrep pkill"
if [[ -f ${motionpid} ]] || [[ -z ${motionpid} ]]; then motionpid=$(grep "^process_id_file" ${motionconf} | cut -d" " -f2); fi
for x in "${reqbins}"; do
	if ! which ${x} > /dev/null 2>&1; then echo "${x} not installed. Please install and run script again"; 	exit 1;	fi
done

function enablecam () {
# check webcam is working
	if [[ ! -c ${webcam} ]]; then
		grep -q "^blacklist uvcvideo$" /etc/modprobe.d/blacklist.conf || sudo sed -i 's/blacklist uvcvideo/#blacklist uvcvideo/1' /etc/modprobe.d/blacklist.conf
	sudo modprobe -a uvcvideo; sleep 1
	fi
}

function startmotion () {
# check motion is already running
	if [[ $(pgrep -a -if "motion -c ${motionconf}" 2> /dev/null) ]] || [[ $(pgrep -F ${motionpid} 2> /dev/null) ]]; then
		echo "FAIL - Motion process already started"; return; fi
enablecam
# start motion process
	sudo nohup motion -c ${motionconf} &
	newmotpid=${BASHPID}
	if ! grep -q "${newmotpid}" ${motionpid}; then echo "${newmotpid}" | sudo tee ${motionpid}; fi
}


function stopmotion () {
# kill motion
	pgrep -F ${motionpid} 2> /dev/null && sudo pkill -9 -F ${motionpid}
	pgrep -a -if "motion -c ${motionconf}" && sudo pkill -9 -f "motion -c ${motionconf}"
# blacklist the video camera (optional)
	grep -q "^#blacklist uvcvideo$" /etc/modprobe.d/blacklist.conf && sudo sed -i 's/#blacklist uvcvideo/blacklist uvcvideo/1' /etc/modprobe.d/blacklist.conf
}

function stopaudio () {
	pgrep -F ${moviedir}/*.pid 2> /dev/null && sudo pkill -9 -F ${moviedir}/*.pid
	pgrep -a -if "arecord -f cd -r 22050 -D plughw:2,0" 2> /dev/null && sudo pkill -9 -f "arecord -f cd -r 22050 -D plughw:2,0"
}

function startaudio () {
	if [[ -z ${audio} ]]; then audio="$(grep '^movie_filename' ${motionconf} | cut -d " " -f2-)"; fi
	/usr/bin/arecord -f cd -r 22050 -D plughw:2,0 "${moviedir}/${audio}.${aext}" --process-id-file "${moviedir}/${audio}.pid" &
}


function mergeaudio () {
mediafiles=$(find ${moviedir} -type f -iname "*.${aext}" -printf "%f\n" -o -iname "*.${vext}" -printf "%f\n" | cut -d. -f1 | sort -u)
	while read -r x; do
		if [[ ! -f "${moviedir}/${x}.${aext}" || ! -f "${moviedir}/${x}.${vext}" ]]; then continue; fi
		ffmpeg -y -i "${moviedir}/${x}.${vext}" -i "${moviedir}/${x}.${aext}" -c:v copy -c:a copy "${moviedir}/${x}.${voutext}" &&
		rm -f "${moviedir}/${x}".{$aext,$vext,pid} > /dev/null 2>&1
	done <<< "${mediafiles}"
	exit
}




case ${action,,} in
enablecam ) enablecam ;;
startmotion ) startmotion ;;
stopmotion ) stopmotion; stopaudio; mergeaudio ;;
startaudio ) stopaudio; startaudio ;;
stopaudio ) stopaudio; mergeaudio ;;
merge ) mergeaudio ;;
esac
