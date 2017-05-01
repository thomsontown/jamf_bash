#!/bin/bash


#    This script simply compares a computer's local name with its
#    active directory name and updates the local computer name if
#    there is a mismatch. 


#    Author:        Andrew Thomson
#    Date:          04/03/2017
#    GitHub:        https://github.com/thomsontown


#	get active directory computer name
DIRECTORY_COMPUTER_NAME=`/usr/sbin/dsconfigad -show | /usr/bin/awk '/Computer\ Account/ {print toupper($4)}'`


#	verify active directory computer name
if [ -z "${DIRECTORY_COMPUTER_NAME:=}" ]; then 
	/bin/echo "No Active Directory Computer Name found."
	exit 0
fi


#	get local computer name 
LOCAL_COMPUTER_NAME=`/usr/local/bin/jamf getComputerName | /usr/bin/xpath "//computer_name/text()" 2> /dev/null | /usr/bin/tr '[:lower:]' '[:upper:]'`


#	verify local computer name
if [ -z "${LOCAL_COMPUTER_NAME:=}" ]; then 
	/bin/echo "No local Computer name found."
	exit 0
fi


#	rename local computer if it doesn't match the domain account
if [ "${DIRECTORY_COMPUTER_NAME%?}" != "${LOCAL_COMPUTER_NAME}" ]; then
	if /usr/local/bin/jamf setComputerName -target / -name "${DIRECTORY_COMPUTER_NAME%?}"; then 
		/usr/local/bin/jamf recon
	else
		(>&2 /bin/echo "ERROR: Unable to rename local computer.")
		exit $LINENO
	fi

	#	show mismatched computer names
	/bin/echo "AD:    ${DIRECTORY_COMPUTER_NAME%?}"
	/bin/echo "LOCAL: ${LOCAL_COMPUTER_NAME}"
fi