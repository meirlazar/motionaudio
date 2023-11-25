#!/bin/bash

set -a ; set -o allexport 

today=$(date +'%Y%m%d')
now=$(date +'%Y%m%d_%H%M%S')

# DIRS
motdir="/etc/motion" # motion dir - do not change
mediabasedir="/home/yourpath/motion" # where media will be stored, change this to the location you want media files stored
mediadir="${mediabasedir}/${today}"
scriptdir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd) # do not change
basedir=${scriptdir%/*}   # do not change


# FILES
scriptfile=$(basename "$0")  # do not change
fullscript="${scriptdir}/${scriptfile}"
motconffile="${motdir}/motion.conf" # motion conf file -  do not change
motlogfile='/var/log/motion/motion.log' # motion log file -  do not change
motpidfile='/var/run/motion/motion.pid' # motion pid file -  do not change
apidfile="/var/run/motion/arecord.pid" # arecord pidfile created when starting audio capture
blfile='/etc/modprobe.d/blacklist.conf' # blacklist file for dev modules -  do not change
debuglog="/var/log/motion/motionaudio.log" # debug log for this script if turned on


webcam="$(sudo find /dev -type c -iname "video[0-9]" | sort -n | head -1)" # finds the first available webcam, or choose your webcam device 
mic=$(aplay -l | grep 'eMeet M0' | sed -E "s/^.*([0-9]):.*,.*([0-9]):.*$/\1,\2/g") # change the keyword for your microphone device

action="$1"   # specify which action to take start, stop, merge, etc  -  do not change
aname="${now}"  # motion will provide 2nd param as timestamp which will be audio filename -  do not change

aext="wav" # change if you prefer a different audio format
vinext="avi" # change this to what is specified in the motion.conf file for the line ffmpeg_video_codec 
voutext="mkv" # change this to the video file type that will be created by joining the audio and video files

tz='-0500'  # specify your TZ , ie mine is -0500

############################################################################################################################



# optional function for first time run to make sure all deps are met
function CHECKDEPS () {
# check deps
reqbins="ffmpeg arecord motion pgrep pkill"
for x in ${reqbins}; do if ! which ${x} > /dev/null 2>&1; then echo "${x} not installed. Please install and run script again"; exit 10; fi ; done

sed -iE "s|^target_dir.*$|target_dir ${mediabasedir}|g" ${motconffile}
sed -iE "s|^movie_filename.*$|movie_filename %Y%m%d_%H%M%S|g" ${motconffile}
sed -iE "s|^on_event_start.*$|on_event_start /bin/bash ${fullscript} StartAudioCapture|g" ${motconffile}
sed -iE "s|^on_event_end.*$|on_event_end  /bin/bash ${fullscript} StopAudioCapture|g" ${motconffile}
sed -iE "s|^on_camera_lost.*$|on_camera_lost /bin/bash ${fullscript} EnableWebCam|g" ${motconffile}
sed -iE "s|^videodevice.*$|videodevice ${webcam}|g" ${motconffile}
sed -iE "s|^process_id_file.*$|process_id_file ${motpidfile}|g" ${motconffile}
sed -iE "s|^ffmpeg_video_codec.*$|ffmpeg_video_codec mpeg4|g" ${motconffile}


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
test -f "${apidfile}" || return 0

if ! sudo pkill -9 -F "${apidfile}"  > /dev/null 2>&1 ; then sudo pkill -9 -f "arecord" 2> /dev/null ; fi
test -f "${apidfile}" && sudo rm -f "${apidfile}" > /dev/null 2>&1 
return 0
}

########################################################################################################

function StartAudioCapture () {
#nohup /usr/bin/arecord -f cd -r 22050 -D plughw:2,0 "${mediadir}/${aname}.${aext}" --process-id-file "${mediadir}/${aname}.pid" &
test -f "${apidfile}" && StopAudioCapture 
sudo nohup /usr/bin/arecord -f S16_LE -c2 -r 8000 -D plughw:"${mic}" "${mediabasedir}/${aname}.${aext}" --process-id-file "${apidfile}" > /dev/null 2>&1 &
# /usr/bin/arecord -f S16_LE -c2 -r 8000 -D plughw:"${mic}" "${mediadir}/${aname}.${aext}" --process-id-file "${apidfile}"   # unbcomment for debugging audio capture
}

########################################################################################################

# USES FFMPEG TO MERGE VIDEO AND AUDIO FILES INTO 1 VIDEO FILE $vidout
function MergeFiles () {
	vidin=$1; audin=$2; vidout=$3
	ffmpeg -y -i "${mediabasedir}/${vidin}" -i "${mediabasedir}/${audin}" -c:v copy -c:a copy "${mediadir}/${vidout}" ; 
	test -f "${mediadir}/${vidout}" || return 10
	rm -f "${mediabasedir}/${vidin}" ; 
	rm -f "${mediabasedir}/${audin}";
	return 0
}

########################################################################################################

# USES FFMPEG TO MERGE VIDEO AND AUDIO FILES INTO 1 VIDEO FILE $vidout

function MergeAllVidOutExceptTodays () {
find "${mediabasedir}" -maxdepth 1 -type d  \( -iname "[0-9]*" ! -iname "${today}" \) -printf "%h %f\n" | while IFS= read -r x y; do
   list="${x}/${y}/combinelist.txt"
   combfile="${x}/${y}/combined_${x}.${voutext}"
   
   test -f "${list}" && rm -f "${list}" 
   test -f "${combfile}" && continue
   
# create a list of files to merge into 1 video file for the day
   find "${x}/${y}" -maxdepth 1 -type f \( -iname "*.${voutext}" ! -iname "*combine*" \) -printf "file '%h/%f'\n"| sort -n >> "${list}" ;  
      

  # if list only has 1 file or none, dont bother combining 
   if [[ $(grep -vc "^$" <"${list}") -le 1 || ! -s ${list} ]]; then rm -f "${list}"; continue; fi ;
 
  # use ffmpeg to combine all files
   ffmpeg -nostdin -f concat -safe 0 -i "${list}" -c copy "${combfile}" > /dev/null 2>&1 
done 

find "${mediabasedir}" -maxdepth 1 -type d -empty -delete 
return 0
}

########################################################################################################

# sometimes the audio file and video file have different timestamps off by 1-2 seconds, this will find those offset audio files and merge it with the correct video. 
function GetFilesToProcess () {
	
test -d "${mediadir}" || mkdir -p "${mediadir}" # create todays subdir in $mediadir
find "${mediabasedir}" -maxdepth 1 -type f -iname "*.${vinext}" | sed -E "s|(^.*/)(.*)(\.[Aa-Zz]+)|\2|g" | sort -u | while IFS= read -r x; do 
  vidin="${x}.${vinext}"
  audin="${x}.${aext}"
  vidout="${x}.${voutext}"

   if [[ -f "${mediabasedir}/${audin}" ]]; then MergeFiles "${vidin}" "${audin}" "${vidout}" ; continue; fi

   ttc="${x:4:2}/${x:6:2}/${x:0:4} ${x:9:2}:${x:11:2}:${x:13:2} ${tz}"; 
   for ((i=1;i<5;i++)); do  y="$(date --date="${ttc} + $i seconds" +'%Y%m%d_%H%M%S')"; audin="${y}.${aext}" ; 
 	   if [[ -f "${mediabasedir}/${audin}" ]]; then export audin ; break; fi ; 
   done
 
  MergeFiles "${vidin}" "${audin}" "${vidout}"
done 
}

########################################################################################################

# MAIN SCRIPT 

case ${action} in
EnableWebCam ) EnableWebCam ;;
StartMotion ) CHECKDEPS; EnableWebCam & wait ; StartMotion ;;
StopMotion ) 
	StopMotion & pids="$pids $!" ; 
	StopAudioCapture & pids="$pids $!" ; 
	for pid in $pids; do wait $pid; done ; 
	GetFilesToProcess ;;
StartAudioCapture ) StartAudioCapture ;;
StopAudioCapture ) StopAudioCapture & wait ; GetFilesToProcess ;;
Merge ) GetFilesToProcess ;;
MergeAll ) MergeAllVidOutExceptTodays ;;
esac

########################################################################################################
