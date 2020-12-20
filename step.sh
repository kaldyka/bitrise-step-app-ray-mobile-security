#!/bin/bash
set -ex

#------------------------------------------1 find app

app=$(find ${app_path} -type f -name "*.apk")
if [ -z "$app"]
then
 app=$(find ${app_path} -type f -name "*.ipa")
 if [ -z "$app"]
 then
  echo "No app found in ${app_path}, exiting"
  exit 1
 else
  echo "iOS app file found at:" $app
 fi
else
 echo "Android app file found at:" $app
fi

#------------------------------------------2 sanity check

filesize=$(wc $app | awk '{print $3}')
if [ "$filesize" -gt 524288000 ]
then
 echo "File size is bigger than 500MB, exiting..."
 exit 1
fi

#------------------------------------------3 auth

auth_token=$(curl -d "username=${appray_user}&password=${appray_passwd}&grant_type=password" -X POST ${base_url}api/v1/authentication | awk '/"access_token":/{token=$2}END{print token}'  | cut -d\" -f2)

if [ -z "$auth_token" ]
then
 echo "Bad login, exiting..."
 exit 1
fi

auth_header="Authorization: Bearer $auth_token"

#------------------------------------------4 upload, get job id

jobid=""
upload_response=$(curl -w "%{http_code}" -H "$auth_header" -F "app_file=@$app" -X POST ${base_url}api/v1/jobs)
upload_response=$(echo ${upload_response} | grep "\<202\>" | cut -d\" -f2)

if [ -z "$upload_response" ]
then
 echo "Upload error"
 echo "Exiting..."
 exit 1
else
 jobid=$upload_response
fi

#------------------------------------------5 check job loop

jobdone=0

while [ $jobdone -ne 1 ]
do
 sleep 30
 pending=$(curl -H "$auth_header" ${base_url}api/v1/jobs?status=done | { grep "$jobid" || :; })
if [ -z "$pending" ]
 then
  jobdone=0
  echo "Scan running"
 else
  jobdone=1
  echo "Scanning finished"
 fi
done

#------------------------------------------6 xunit save

if [ -z ${result_path} ]
then
 echo "result_path was left empty"
 echo "Saving results interrupted"
else
 echo "Saving results to ${result_path}app_ray_results.xml"
 curl -H "$auth_header" ${base_url}api/v1/jobs/"$jobid"/junit --output "${result_path}"app_ray_result.xml
fi

#------------------------------------------7 treshold check

risk=$(curl -H "$auth_header" ${base_url}api/v1/jobs/"$jobid" | awk '/"risk_score":/{riskscore=$2}END{print riskscore}' | cut -d\, -f1)
envman add --key APP_RAY_RISK_SCORE --value "$risk"
if [ "$risk" -gt "${score_treshold}" ]
then
 echo "Analysis risk is greater than set treshold"
 exit 1
else
 echo "Analysis risk score is whitin treshold"
fi

exit 0
