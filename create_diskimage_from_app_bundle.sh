#!/bin/sh


#    This script was written to quickly and easily create disk image files 
#    containing simple application bundles that are typically downloaded 
#    and manually moved into the /Applications folder for use. Using this 
#    script, the application bundles will be added to a JAMF PRO compatible
#    disk image file that can then be used for easy distribution. The scrip
#    must run as root. You can include the path to the application bundle as 
#    a parameter when running the sciprt, or when prompted, enter it manually 
#    or drag and drop into the terminal window and press the ENTER key. 

#    WARNING: The source location you direct the script to for the application
#    bundle will also serve as the destination on target computers. 

#    I've added variables for PREFIX and SUFFIX so as to be able to customize 
#    the name of the newly generated package file.

#    Author: 	Andrew Thomson
#    Date:		02-03-2017
#    GitHub:     https://github.com/thomsontown


SOURCE=${1%/}                       #	application bundle path as command line argument
DESTINATION="/Applications"         #	install destination of application
PREFIX="SW - "                      #	prefix of package file name
SUFFIX=" v"                         #	suffix of package file name before version number
DMGPATH="$HOME/Desktop/"            #	location where package file will be saved


function onExit() {
	ERROR_CODE=$?
	if [ -d "$TMP_SOURCE" ]; then /bin/rm -rf "$TMP_SOURCE"; fi	
	echo  "Exited with code #${ERROR_CODE} after $SECONDS second(s)."
}


#	make sure to cleanup on exit
trap onExit EXIT


# 	make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit $LINENO
fi


#	install script to local bin with short name -- optional
if [ ! -x /usr/local/bin/quickdmg ]; then /usr/bin/install -o 0 -g 0 "$0" /usr/local/bin/quickdmg; fi


#	get the path to the source app to package
if [ -z "$SOURCE" ]; then
	echo "Please enter the path to the application you want to package, or drag and drop it into this window. Then press the enter key."
	read SOURCE
	if [ ! -x "$SOURCE" ]; then 
		echo "ERROR: The application cannot be found."
		exit $LINENO
	fi
fi


#	verify source exists
if [ ! -d "${SOURCE}" ]; then 
	echo "ERROR: Unable to find the specified application bundle."
	exit $LINENO
fi


#	if the source path contains /Applications, prompt with warning
if [[ ${SOURCE} != *"/Applications"* ]]; then 
	echo "WARNING: The specified application bundle is not in the \"/Applications\" folder. Are you sure you want to continue? [y/n]"
	read YES_NO
	if [ $YES_NO != y ]; then exit $LINENO; fi
fi


if ! /usr/bin/rsync -axlR "${SOURCE%/}" "${TMP_SOURCE%/}"; then 
	echo "ERROR: Unable to copy application bundle to temporary location."
	exit $LINENO
fi


#	read info.plist to get source attributes
if [ -f "${TMP_SOURCE%/}${SOURCE}/Contents/Info.plist" ]; then
	
	#	get app bundle name 
	if ! NAME=`/usr/bin/defaults read "${TMP_SOURCE%/}${SOURCE%/}/Contents/Info" CFBundleName 2> /dev/null`; then 
		
		#	as alternate
		NAME=`/usr/bin/basename -a .app "$SOURCE"`
	fi	
	
	#	get app bundle version
	if ! VERSION=`/usr/bin/defaults read "${TMP_SOURCE%/}${SOURCE%/}/Contents/Info" CFBundleShortVersionString 2> /dev/null`; then

		#	as alternate
		VERSION=`/usr/bin/defaults read "${TMP_SOURCE%/}${SOURCE%/}/Contents/Info" CFBundleVersionString 2> /dev/null`
	fi
fi


#	make sure all variables have values
if [[ -z ${NAME} ]] || [[ -z ${VERSION} ]]; then
	echo "ERROR: One or more attributes could not be found."
	exit $LINENO
fi


#	make temp folder
TMP_SOURCE=`/usr/bin/mktemp -d "/tmp/$NAME.XXXX"`


#	display variables
echo Application Name:       $NAME
echo Application Version:    $VERSION
echo Temporary Source:       $TMP_SOURCE


#	set permissions
if ! /bin/chmod -R 755 "${TMP_SOURCE%/}${SOURCE%/}" 2> /dev/null; then
	echo "ERROR: Unable to set permissions."
	exit $LINENO
fi


#	remove any extended attributes
if ! /usr/bin/xattr -rc "${TMP_SOURCE%/}${SOURCE%/}" 2> /dev/null; then 
	echo "ERROR: Unable to remove extended attributes."
	exit $LINENO
fi


#	create disk image file
if ! /usr/bin/hdiutil create -volname "$NAME" -srcfolder "${TMP_SOURCE%/}" -ov -format UDZO "${DMGPATH}${PREFIX}${NAME}${SUFFIX}${VERSION}.dmg" 2> /dev/null; then
	echo "ERROR: Unable to create disk image file."
	exit $LINENO
fi