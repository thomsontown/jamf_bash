#!/bin/bash


#    This is a re-write of a script by Patrik Sonestad of Sweden. It uses
#    google's maps api to determine a system's coordinates and approximate 
#    address based on nearby access point information. The goal of this
#    script was to simply output the information to stdout. The script 
#    can easily be modified to display its results in an xml tag to update
#    an extension attribute for JAMF PRO.

#    Patrik's script was perfect, I simply wanted to re-write it to better
#    understand its functionality. Along the way I changed some commands
#    to others I was more familiar with and felt added some efficiencies.
#    I also added more detailed comments along the way to help others more
#    clearly understand how it works. Many thanks go to Patrik for sharing
#    his source with the community.

#    Author:        Andrew Thomson
#    Date:          01-27-2017


#	set base url for location query
URL="https://maps.googleapis.com/maps/api/browserlocation/json?browser=firefox&sensor=false"


#	get wi-fi device
INTERFACE=`/usr/sbin/networksetup -listallhardwareports | /usr/bin/awk '/Wi-Fi/ {getline;print $2;}'`


#	get status of wi-fi device
STATUS=`/usr/sbin/networksetup -getairportpower $INTERFACE | /usr/bin/awk '{print $4}'`


#	enable wi-fi device 
if [ $STATUS = "Off" ] ; then /usr/sbin/networksetup -setairportpower $INTERFACE on; /bin/sleep 5; fi


#	scan for access points and sort according to singal strength
IFS=$'\n' SSIDS=(`/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport -s | /usr/bin/awk '{if(NR>1){print $1, $2, $3 }}' | /usr/bin/sort -k3,3rn`)


#	enumerate scan results 
for INDEX in ${!SSIDS[@]}; do 

	#	split results into separate variables
	IFS=" " read SSID MAC SS <<< ${SSIDS[$INDEX]}

	#	incorporate scan reults into location query
	URL+="&wifi=mac:$MAC&ssid:$SSID&ss:$SS"
done


#	query for location latitude, longitude and accuracy
COORDINATES=`/usr/bin/curl -s -A "Mozilla" "$URL"`


#	parse latitiude, longitude and accuracy from results
LAT=`echo $COORDINATES | /usr/bin/awk '{print $10}'`
LNG=`echo $COORDINATES | /usr/bin/awk '{print $13}'`
ACC=`echo $COORDINATES | /usr/bin/awk '{print $4}'`


#	query for address fro latitude and logitude
ADDRESS=`/usr/bin/curl -s -A "Mozilla" "http://maps.googleapis.com/maps/api/geocode/xml?latlng=$LAT$LNG&sensor=false" | /usr/bin/xpath "/GeocodeResponse/result[1]/formatted_address/text()" 2> /dev/null`


#	display results
echo "APPROX ADDRESS:   $ADDRESS"
echo "LATITUDE:         ${LAT%,}"
echo "LONGITUDE:       ${LNG%,}"
echo "ACCURACY:         ${ACC%,}"