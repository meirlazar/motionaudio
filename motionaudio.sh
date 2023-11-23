#!/bin/bash
motdir="/etc/motion" # motion dir
mediadir="/home/yourusername/motion" # where media will be stored, change this 

motconffile="${motdir}/motion.conf" # motion conf file
motlogfile='/var/log/motion/motion.log' # motion log file
motpidfile='/var/run/motion/motion.pid' # motion pid file
apidfile="${mediadir}/arecord.pid" # arecord pidfile created when starting audio capture
blfile='/etc/modprobe.d/blacklist.conf' # blacklist file for dev modules
debuglog="/var/log/motion/motionaudio.log" # debug log for this script if turned on


webcam="$(find /dev -type c -iname "video[0-9]" | head -1)" # or choose your webcam device 
mic="$(aplay -l | grep 'eMeet M0' | sed -E "s/^.*([0-9]):.*,.*([0-9]):.*$/\1,\2/g")" # use keyword for microphone device

action="$1"   # specify which action to take start, stop, merge, etc
aname="$2"  # motion will provide 2nd param as timestamp which will be audio filename

aext="wav" # change if you prefer a different audio format or extension
vinext="avi" # change this to what is specified in the motion.conf file for the line ffmpeg_video_codec
voutext="mkv" #change this to the video file type that will be created by joining the audio and video files

tz='-0500'  # specify your TZ , ie mine is -0500

# motion.conf should have the following if using debug mode
#target_dir /path/to/motion/videos
#movie_filename %Y%m%d_%H%M%S
#on_event_start /bin/bash -x /etc/motion/motionaudio.sh StartAudioCapture %Y%m%d_%H%M%S >> /var/log/motion/motionaudio.log 2>&1 
#on_event_end  /bin/bash -x /etc/motion/motionaudio.sh StopAudioCapture >> /var/log/motion/motionaudio.log 2>&1 
#on_camera_lost /bin/bash -x /etc/motion/motionaudio.sh EnableWebCam >> /var/log/motion/motionaudio.log 2>&1 


# motion.conf should have the following in normal mode
#target_dir /path/to/motion/videos
#movie_filename %Y%m%d_%H%M%S
#on_event_start /bin/bash /etc/motion/motionaudio.sh StartAudioCapture %Y%m%d_%H%M%S
#on_event_end  /bin/bash /etc/motion/motionaudio.sh StopAudioCapture
#on_camera_lost /bin/bash /etc/motion/motionaudio.sh EnableWebCam

########################################################################################################

# optional function for first time run to make sure all deps are met
function CHECKDEPS () {
# check deps
reqbins="ffmpeg arecord motion pgrep pkill"
for x in "${reqbins}"; do
	if ! which ${x} > /dev/null 2>&1; then echo "${x} not installed. Please install and run script again"; exit 10; fi
done
}

########################################################################################################

function EnableWebCam () {
# check webcam is working
	if [[ ! -c ${webcam} ]]; then
		grep -q "^blacklist uvcvideo$" ${blfile} || sudo sed -i 's/blacklist uvcvideo/#blacklist uvcvideo/1' ${blfile}
		sudo modprobe -a uvcvideo; sleep 1
	fi
}

########################################################################################################

# not used but can be used to make sure webcam is completely disabled
function DisableWebCam () {
# check webcam is working
	if [[ -c ${webcam} ]]; then
		grep -q "^#blacklist uvcvideo$" ${blfile} || sudo sed -i 's/#blacklist uvcvideo/blacklist uvcvideo/1' ${blfile}
	fi
}

########################################################################################################

# starts motion process that will use this script for recording audio and merging audio files with video files
function StartMotion () {
# check motion is already running
	if [[ $(pgrep -a -if "motion -c ${motconffile}" 2> /dev/null) ]] || [[ $(pgrep -F ${motpidfile} 2> /dev/null) ]]; then
		echo "FAIL - Motion process already started"; return; 
	fi
# start motion process
	sudo nohup motion -c ${motconffile} > /dev/null 2>&1 & 
	newmotpid=${BASHPID}
	if ! grep -q "${newmotpid}" ${motpidfile} 2> /dev/null; then echo "${newmotpid}" | sudo tee ${motpidfile}; fi
# tail -f ${motlogfile} # uncomment for debugging
}

########################################################################################################

function StopMotion () {
# kill motion
if [[ $(pgrep -F ${motpidfile} 2> /dev/null) ]] || [[ $(pgrep -a -if "motion -c ${motconffile}" 2> /dev/null) ]]; then
	if sudo pkill -9 -F ${motpidfile} 2> /dev/null; then echo "Killed Motion"
	elif sudo pkill -9 -f "motion -c ${motconffile}" 2> /dev/null; then echo "Killed Motion"
	else echo "Motion is not running"  
	fi
sudo rm -f "${motpidfile}"
fi
}

########################################################################################################

function StopAudioCapture () {
if [[ ! -f "${apidfile}" ]]; then return 0; fi

sudo pkill -9 -F "${apidfile}" || sudo pkill -9 -f "arecord" 2> /dev/null 
sudo rm -f "${apidfile}" 2> /dev/null
return 0
}

########################################################################################################

function StartAudioCapture () {
#nohup /usr/bin/arecord -f cd -r 22050 -D plughw:2,0 "${mediadir}/${aname}.${aext}" --process-id-file "${mediadir}/${aname}.pid" &
if [[ -f "${apidfile}" ]]; then StopAudioCapture ; fi
#nohup /usr/bin/arecord -f S16_LE -c2 -r 8000 -D plughw:${mic} "${mediadir}/${aname}.${aext}" --process-id-file "${apidfile}" > /dev/null 2>&1 &
/usr/bin/arecord -f S16_LE -c2 -r 8000 -D plughw:"${mic}" "${mediadir}/${aname}.${aext}" --process-id-file "${apidfile}"   # unbcomment for debugging audio capture
}

########################################################################################################

# USES FFMPEG TO MERGE VIDEO AND AUDIO FILES INTO 1 VIDEO FILE $vidout
function MergeFiles () {
	vidin=$1; audin=$2; vidout=$3
	ffmpeg -y -i "${mediadir}/${vidin}" -i "${mediadir}/${audin}" -c:v copy -c:a copy "${mediadir}/${vidout}" ; 
	if [[ -f "${mediadir}/${vidout}" ]]; then rm -f "${mediadir}/${vidin}" ; rm -f "${mediadir}/${audin}"; fi
	return 0
}

########################################################################################################

# sometimes the audio file and video file have different timestamps off by 1-2 seconds, this will find those offset audio files and merge it with the correct video. 
function GetFilesToProcess () {
find ${mediadir} -maxdepth 1 -type f -iname "*.avi" | sed -E "s|(^.*/)(.*)(\.[a-z]+)|\2|g" | sort -u | while read -r x; do 
  vidin="${x}.${vinext}"
  audin="${x}.${aext}"
  vidout="${x}.${voutext}"

   if [[ -f "${mediadir}/${audin}" ]]; then MergeFiles ${vidin} ${audin} ${vidout} ; continue; fi

   ttc="${x:4:2}/${x:6:2}/${x:0:4} ${x:9:2}:${x:11:2}:${x:13:2} ${tz}"; 
   for ((i=1;i<5;i++)); do  y="$(date --date="${ttc} + $i seconds" +'%Y%m%d_%H%M%S')"; audin="${y}.${aext}" ; 
 	   if [[ -f "${mediadir}/${audin}" ]]; then export audin ; break; fi ; 
   done
 
  MergeFiles ${vidin} ${audin} ${vidout}
done 
}

########################################################################################################

# MAIN SCRIPT 

case ${action} in
EnableWebCam ) EnableWebCam ;;
StartMotion ) EnableWebCam & wait ; StartMotion ;;
StopMotion ) 
	StopMotion & pids="$pids $!" ; 
	StopAudioCapture & pids="$pids $!" ; 
	for pid in $pids; do wait $pid; done ; 
	GetFilesToProcess ;;
StartAudioCapture ) StartAudioCapture ;;
StopAudioCapture ) StopAudioCapture & wait ; GetFilesToProcess ;;
Merge ) GetFilesToProcess ;;
esac

########################################################################################################
