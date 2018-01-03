#!/bin/bash

#    This script was written to automate the process of converting
#    a local domain account to an active directory domain account. 
#    The script will need to be run from a neutral profile with
#    admin rights. Also, the DOMAIN_USERS (Domain Users group ID)
#    variable is different for each domain and will need to be 
#    specified below. 

#    The section to verify host name can be modifed or removed as
#    desired. 

#    Author:        Andrew Thomson
#    Date:          11-13-2017
#    GitHub:        https://www.github.com/thomsontown


#	variables
DOMAIN_USERS="946772677"
SCRIPT_TITLE="Convert Account"
LOG_FILE=${0##*/}; LOG_FILE=${LOG_FILE%.*}.log


#	redirect output to logfile
exec >> "$HOME/Library/Logs/$LOG_FILE" 2>&1


#	function to display errors 
function displayError() {
	/usr/bin/osascript -e "display dialog \"ERROR: $2\" with text buttons {\"OK\"} default button 1 with title \"$SCRIPT_TITLE\"" &> /dev/null
	echo "$(date): ERROR: $2"
	exit $1
}

 
#	ensure script runs with elevated privileges
if [ $EUID != 0 ]; then
	displayError $LINENO "This script must run with root privileges."
fi


#	get local host name
HOST_NAME=`/usr/sbin/scutil --get HostName`


#	verify host name
if ! echo $HOST_NAME | /usr/bin/grep -E "^[A-Z]{3}\-[A-Z]{3}\-[0-9]{6}$"; then
	displayError $LINENO " Host name does not meet required format.\n\t\tPlease rename before joining to the domain.\n\t\t(LOC-DPT-123456)"
fi


#	get current console user
CURRENT_USERNAME=`/bin/ls -l /dev/console | /usr/bin/awk '{print $3}'`
if [ -z $CURRENT_USERNAME ]; then 
	displayError $LINENO "Unable to determine current username."
fi 


#	verify domain binding
DOMAIN=`/usr/sbin/dsconfigad -show | /usr/bin/awk '/Active Directory Domain/ {print $5}'`
if [ -z $DOMAIN ]; then
	displayError $LINENO "This computer is not joined to the domain."
fi


#	verify domain availability 
SUB_NODES=(`/usr/bin/dscl localhost -list "/Active Directory"`)
if [ -z $SUB_NODES ]; then
	displayError $LINENO "This computer is unable to access the Active Directory."
fi


#	prompt for local target account to convert
LOCAL_USERNAME=`/usr/bin/osascript -e 'get text returned of (display dialog "Enter the local account name to convert." default answer "" with text buttons {"OK"} default button 1)'`
if [ -z "$LOCAL_USERNAME" ]; then
	displayError $LINENO "No username entered."

elif ! /usr/bin/dscl . list /Users/$LOCAL_USERNAME &> /dev/null; then
	displayError $LINENO "The account name provided cannot be found."

elif [ $LOCAL_USERNAME == $CURRENT_USERNAME ]; then
	displayError $LINENO "The account name provided is currently in use."
fi


#	prompt for domain account 
DOMAIN_USERNAME=`/usr/bin/osascript -e 'get text returned of (display dialog "Enter the domain account name to target (account names may be the same)." default answer "" with text buttons {"OK"} default button 1)'`
if [ -z $DOMAIN_USERNAME ]; then
	displayError $LINENO "No username entered."

elif [ $DOMAIN_USERNAME == $CURRENT_USERNAME ]; then
	displayError $LINENO "The account name provided is currently in use."
fi


#	get profile path for local account
LOCAL_PROFILE=`/usr/bin/dscl . read /Users/$LOCAL_USERNAME NFSHomeDirectory | /usr/bin/awk '{print $2}'`
if [ ! -d "$LOCAL_PROFILE" ]; then
	displayError $LINENO "The local profile path cannot be found."
fi


#	remove target account
if ! /usr/bin/dscl . delete /Users/$LOCAL_USERNAME; then
	displayError $LINENO "Unable to delete local target account."
fi


#	rename profile path
if ! /bin/mv "$LOCAL_PROFILE" /Users/LOCAL_TEMP; then
	displayError $LINENO "Unable to rename local profile."
fi


#	create mobile account 
if ! /System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n $DOMAIN_USERNAME &> /dev/null; then
	displayError $LINENO "Unable to create mobile account."
fi


#	get profile path for mobile account
DOMAIN_PROFILE=`/usr/bin/dscl . read /Users/$DOMAIN_USERNAME NFSHomeDirectory | /usr/bin/awk '{print $2}'`
if [ ! -d "$DOMAIN_PROFILE" ]; then
	displayError $LINENO "The domain profile path cannot be found."
fi


#	remove mobile account profile
if ! /bin/rm -rf "$DOMAIN_PROFILE"; then
	displayError $LINENO "Unable to remove mobile profile."
fi


#	rename origial profile to match new mobile profile
if ! /bin/mv "/Users/LOCAL_TEMP" "$DOMAIN_PROFILE"; then
	displayError $LINENO "Unable to rename local profile to match domain account."
fi 


#	change ownership on profile to match domain account
if ! /usr/sbin/chown -R $DOMAIN_USERNAME:$DOMAIN_USERS "$DOMAIN_PROFILE"; then 
	displayError $LINENO "Unable to change ownership."
fi 


#	change permissions on profile 
if ! /bin/chmod -R 755 "$DOMAIN_PROFILE"; then 
	displayError $LINENO "Unable to change permissions."
fi