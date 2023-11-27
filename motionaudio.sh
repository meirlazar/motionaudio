#!/bin/bash

set -a ; set -o allexport 

today=$(date +'%Y%m%d')
now=$(date +'%Y%m%d_%H%M%S')

# DIRS
motdir="/etc/motion" # motion dir - do not change
media_bdir="/home/yourusername/motion" # where media will be stored, change this to the location you want media files stored
media_outdir="${media_bdir}/${today}"
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

action=$1   # specify which action to take start, stop, merge, etc  -  do not change
aname="${now}"  # motion will provide 2nd param as timestamp which will be audio filename -  do not change

a_ext="wav" # change if you prefer a different audio format
vin_ext="avi" # change this to what is specified in the motion.conf file for the line ffmpeg_video_codec 
vout_ext="flv" # change this to the video file type that will be created by joining the audio and video files

tz='-0500'  # specify your TZ , ie mine is -0500

############################################################################################################################



# optional function for first time run to make sure all deps are met
function CheckDeps () {
# check deps
reqbins="ffmpeg arecord motion pgrep pkill"
for x in ${reqbins}; do if ! which ${x} > /dev/null 2>&1; then echo "${x} not installed. Please install and run script again"; exit 10; fi ; done

#sed -iE "s|^target_dir.*$|target_dir ${media_bdir}|g" ${motconffile}
#sed -iE "s|^movie_filename.*$|movie_filename %Y%m%d_%H%M%S|g" ${motconffile}
sed -iE "s|^on_event_start.*$|on_event_start /bin/bash ${fullscript} StartCapture|g" ${motconffile}
sed -iE "s|^on_event_end.*$|on_event_end  /bin/bash ${fullscript} StopCapture|g" ${motconffile}
sed -iE "s|^on_camera_lost.*$|on_camera_lost /bin/bash ${fullscript} EnableWebCam|g" ${motconffile}
sed -iE "s|^videodevice.*$|videodevice ${webcam}|g" ${motconffile}
sed -iE "s|^ffmpeg_video_codec.*$|ffmpeg_video_codec ffv1|g" ${motconffile}
#sed -iE "s|^process_id_file.*$|process_id_file ${motpidfile}|g" ${motconffile}


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

function StopCapture () {
test -f "${apidfile}" || return 0

if ! sudo pkill -9 -F "${apidfile}"  > /dev/null 2>&1 ; then sudo pkill -9 -f "arecord" 2> /dev/null ; fi
test -f "${apidfile}" && sudo rm -f "${apidfile}" > /dev/null 2>&1 
return 0
}

########################################################################################################

function StartCapture () {
#nohup /usr/bin/arecord -f cd -r 22050 -D plughw:2,0 "${media_outdir}/${aname}.${a_ext}" --process-id-file "${media_outdir}/${aname}.pid" &
test -f "${apidfile}" && StopCapture 
sudo nohup /usr/bin/arecord -f S16_LE -c2 -r 16000 -D plughw:"${mic}" "${media_bdir}/${aname}.${a_ext}" --process-id-file "${apidfile}" > /dev/null 2>&1 &
# /usr/bin/arecord -f S16_LE -c2 -r 8000 -D plughw:"${mic}" "${media_outdir}/${aname}.${a_ext}" --process-id-file "${apidfile}"   # unbcomment for debugging audio capture
}

########################################################################################################

# USES FFMPEG TO MERGE VIDEO AND AUDIO FILES INTO 1 VIDEO FILE $v_out
function MergeFiles () {
	v_in=$1; a_in=$2; v_out=$3
	ffmpeg -nostdin -y -i "${v_in}" -i "${a_in}" -c:a aac -strict -2 -c:v h264 "${v_out}" 2> /dev/null; 
	if [[ -f "${v_out}" ]]; then  rm -f "${v_in}" "${a_in}" ; return 0 ; fi
	
	ffmpeg -nostdin -y -i "${v_in}" -i "${a_in}" -c:a copy -c:v copy "${v_out}" 2> /dev/null; 
	if [[ -f "${v_out}" ]]; then  rm -f "${v_in}" "${a_in}" ; return 0 ; fi
	
	return 10; 
}

########################################################################################################

# USES FFMPEG TO MERGE VIDEO AND AUDIO FILES INTO 1 VIDEO FILE combined_'%Y%m%d_%H%M%S'.mkv

function MergePreviousVids () {
find "${media_bdir}" -maxdepth 1 -type d  \( -iname "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" ! -iname "${today:=$(date +'%Y%m%d')}" \) -printf "%h/%f\n" | while IFS= read -r x; do
   listfile="${x}/combinelist.txt"
   combfile="${x}/combined_${x##*/}.${vout_ext}"
   
   test -f "${listfile}" && rm -f "${listfile}" 
   test -f "${combfile}" && continue
   
# create a listfile of files to merge into 1 video file for the day
   find "${x}" -maxdepth 1 -type f \( -iname "[0-9]*.${vout_ext}" ! -iname "*combine*" \) -printf "file '%h/%f'\n" | sort -n >> "${listfile}" ;  
      

  # if listfile only has 1 file or none, dont bother combining 
   if [[ $(grep -vc "^$" <"${listfile}") -le 1 || ! -s ${listfile} ]]; then rm -f "${listfile}"; continue; fi ;
 
  # use ffmpeg to combine all files
   ffmpeg -nostdin -f concat -safe 0 -i "${listfile}" -c copy "${combfile}" 2> /dev/null 
done 


find "${media_bdir:?}" -maxdepth 1 -type d -empty -delete 
return 0
}

########################################################################################################

# sometimes the audio file and video file have different timestamps off by 1-2 seconds, this will find those offset audio files and merge it with the correct video. 
function GetFilesToProcess () {
	
test -d "${media_outdir}" || mkdir -p "${media_outdir}" # create todays subdir in $media_outdir

find "${media_bdir}" -maxdepth 1 -type f -iname "*.${vin_ext}" | sed -E "s|(^.*/)(.*)(\.[Aa-Zz]+)|\2|g" | sort -u | while IFS= read -r x; do 
  v_in="${media_bdir}/${x}.${vin_ext}"
  a_in="${media_bdir}/${x}.${a_ext}"
  v_out="${media_outdir}/${x}.${vout_ext}"

   if [[ -f "${a_in}" ]]; then MergeFiles "${v_in}" "${a_in}" "${v_out}" ; continue;  fi

   ttc="${x:4:2}/${x:6:2}/${x:0:4} ${x:9:2}:${x:11:2}:${x:13:2} ${tz}"; 
   for ((i=1;i<5;i++)); do  y="$(date --date="${ttc} + $i seconds" +'%Y%m%d_%H%M%S')"; a_in="${media_bdir}/${y}.${a_ext}" ; 
 	   if [[ -f "${a_in}" ]]; then export a_in ; break; fi ; 
   done
 
  MergeFiles "${v_in}" "${a_in}" "${v_out}"
done 
}

########################################################################################################

# MAIN SCRIPT 

case ${action} in
EnableWebCam ) EnableWebCam ;;
StartMotion ) CheckDeps; EnableWebCam & wait ; StartMotion ;;
StopMotion ) 
	StopMotion ; 
	StopCapture ; 
	GetFilesToProcess ;
	MergePreviousVids ;;	
StartCapture ) StopCapture; StartCapture ;;
StopCapture ) StopCapture & wait ; GetFilesToProcess ;;
Merge ) GetFilesToProcess ;;
MergeAll ) MergePreviousVids ;;
esac

########################################################################################################
