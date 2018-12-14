#!/bin/bash
# purpose of this script is to mark provided image with provided label

###############################################
#                   VARIABLES                 #
###############################################
max_label_id=0
new_label_id=0
start=$(date +%s)
# env variables
# $LABEL
# $IMAGE
# $HARBOR_USERNAME
# $HARBOR_PASSWORD
# $REPOSITORY_DOMAIN
project=$(echo $IMAGE | cut -f1 -d"/")
repository=$(echo $IMAGE | cut -f2 -d"/" | cut -f1 -d":")
tag=$(echo $IMAGE | cut -f2 -d":")
url="https://$REPOSITORY_DOMAIN/api"
#echo colors
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'

###############################################
# Check existence of mandatory env vars       #
# On failure -> exit 1                        #
###############################################
missing_env=false
if [[ -z $LABEL ]]; then
    echo -e "${RED}ERROR: Env variable 'LABEL' was not set. Please provide wanted labels in comma separated format."
    missing_env=true
    if [[ -z $IMAGE ]]; then 
        echo -e "${RED}ERROR: Env variable 'IMAGE' was not set. Please provide image information in format {project}/{repository}:{tag}."
        missing_env=true
        if [[ -z $HARBOR_USERNAME ]]; then 
            echo -e "${RED}ERROR: Env variable 'HARBOR_USERNAME' was not set. Please provide an username with write access to wanted repository."
            missing_env=true
            if [[ -z $HARBOR_PASSWORD ]]; then
                echo -e "${RED}ERROR: Env variable 'HARBOR_PASSWORD' was not set. Please provide correct password for HARBOR_USERNAME."
                missing_env=true
                if [[ -z $EPOSITORY_DOMAIN ]]; then 
                    echo -e "${RED}ERROR: Env variable 'REPOSITORY_DOMAIN' was not set. Please provide correct domain of wanted Harbor instance."
                    missing_env=true
                fi
            fi
        fi
    fi
fi

if $missing_env; then
    exit 1
fi
###############################################
# Check existence of Project                  #
# On failure -> exit 1                        #
###############################################
echo -ne "${NC}Checking existence of project '$project' ... "
project_id=$(curl -sX GET "$url/projects?name=$project" -H "accept: application/json" | jq '.[].project_id' 2> /dev/null)
if [[ -z $project_id ]]; then
    echo -e "${RED}ERROR: Project '$project' is not visible in registry, please check again whether it was correctly spelled and if the project exists. Terminating the sript now ..."
    exit 1
else
    echo -e "${GREEN}OK: Project exists."
fi

###############################################
# Check existence of Repository               #
# On failure -> exit 1                        #
###############################################
echo -ne "${NC}Checking existence of repository "\"$project/$repository\"" ... "
curl_for=$(curl -sX GET "$url/repositories?project_id=$project_id" -H  "accept: application/json" | jq '.[].name' 2> /dev/null)
for i in $curl_for
do
    if [[ "\"$project/$repository\"" = "$i" ]]; then
        exists='true'
        break
    else
        exists='false'
    fi
done
if $exists; then 
    echo -e "${GREEN}OK: Repository exists."
else
    echo -e "${RED}ERROR: Repository is not visible in project '$project', please check again whether it was correctly spelled and if the project exists. Terminating the sript now ..."
    exit 1
fi

###############################################
# Check existence of Image in Repository      #
# On failure -> exit 1                        #
###############################################
echo -ne "${NC}Checking existence of tag '$tag' in '$project/$repository' ... "
curl_if=$(curl -sX GET "$url/repositories/$project%2F$repository/tags/$tag" -H "accept: application/json" | jq -r '.name' 2> /dev/null)
if [[ "$tag" = "$curl_if" ]]; then
    echo -e "${GREEN}OK: Tag exists. "
else
    echo -e "${RED}ERROR: Tag '$tag' is not visible in '$project/$repository', please check again whether it was correctly pushed and stored. Terminating the sript now ..."
    exit 1
fi

#############################################################################################################################################
# MAIN PART                                                                                                                                 #
# 1. fetches all labels (provided in env var $LABEL, in comma separated structure)                                                          #
# 2. for each label it performs:                                                                                                            #
#   1. check if it exists in global labels (if yes, moving to label phase) (if not, switching to next if)                                   #
#   2. check if it exists in project labels (if yes, moving to label phase) (if not, switching to create label)                             #
#   3. creates label (if it does not exists) and catches the http_code response as a confirmation of success / failure                      #
#   4. marking image with the label and catches the http_code response as a confirmation of success / failure                               #
#############################################################################################################################################
for i in $(echo $LABEL | sed 's/,/ /g')
do
    error=false
    echo -ne "${NC}Checking existence of label '$i' in repository ... "

    curl_if=$(curl -sX GET "$url/labels?scope=g&name=$i" -H "accept: application/json" | jq -r '.[].name' 2> /dev/null | grep -x $i)
    curl_elif=$(curl -sX GET "$url/labels?name=$i&scope=p&project_id=$project_id" -H "accept: application/json" | jq -r '.[].name' 2> /dev/null | grep -x $i)

    if [[ "$i" = "$curl_if" ]]; then
        echo -e "${GREEN}OK: Label '$i' exists in global labels."
        label_id=$(curl -sX GET "$url/labels?scope=g&name=$i" -H "accept: application/json" | jq -r ".[] | select(.name == \"$i\") | .id" 2> /dev/null)
    elif [[ "$i" = "$curl_elif" ]]; then
        echo -e "${GREEN}OK: Label '$i' exists in project '$project' labels."
        label_id=$(curl -sX GET "$url/labels?name=$i&scope=p&project_id=$project_id" -H "accept: application/json" | jq -r ".[] | select(.name == \"$i\") | .id" 2> /dev/null)
    else
        echo -e "${GREEN}INFO: Label '$i' does not exists in whole repository."
        echo -ne "${NC}Creating new label '$i' under project '$project' ... "

        # creating new label
        http_code=$(curl -sX POST -u $HARBOR_USERNAME:$HARBOR_PASSWORD "$url/labels" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{  \"name\": \"$i\",  \"scope\": \"p\",  \"project_id\": $project_id}" -w "%{http_code}" -o /dev/null | sed '/^$/d')
        case $http_code in
            201) 
                echo -e "${GREEN}OK: Create successfully."
                label_id=$(curl -sX GET "$url/labels?name=$i&scope=p&project_id=$project_id" -H "accept: application/json" | jq -r '.[].id' 2> /dev/null)
                ;;
            400) echo -e "${RED}ERROR: $http_code - Request has invalid parameters." ; error=true ;;
            401) echo -e "${RED}ERROR: $http_code - user is not authorized to perform this action." ; error=true ;;
            409) echo -e "${RED}ERROR: $http_code - Label with the same name and same scope already exists." ; error=true ;;
            415) echo -e "${RED}ERROR: $http_code - The Media Type of the request is not supported, it has to be application/json" ; error=true ;;
            500) echo -e "${RED}ERROR: $http_code - Unexpected internal errors." ; error=true ;;
            *) echo -e "${RED}ERROR: $http_code - description is not available." ; error=true ;;
        esac
    fi

    # marking an image with label
    if ! $error; then 
        echo -ne "${NC}Marking '$IMAGE' with label '$i' ... "
        http_code=$(curl -sX POST -u $HARBOR_USERNAME:$HARBOR_PASSWORD "$url/repositories/$project%2F$repository/tags/$tag/labels" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{ \"id\": $label_id, \"name\": \"$i\",  \"scope\": \"p\",  \"project_id\": $project_id}" -w "%{http_code}" -o /dev/null | sed '/^$/d')
        case $http_code in
            200) echo -e "${GREEN}OK: Image '$IMAGE' successfully labeled with '$i'." ;;
            401) echo -e "${RED}ERROR: $http_code - user is not authorized to perform this action." ;;
            403) echo -e "${RED}ERROR: $http_code - Forbidden. User should have write permisson for the image to perform the action." ;;
            404) echo -e "${RED}ERROR: $http_code - Resource not found." ;;
            409) echo -e "${GREEN}INFO: $http_code - Image '$IMAGE' is already marked with label '$i'" ;;
            *) echo -e "${RED}ERROR: $http_code - description is not available." ;;
        esac 
    fi
done

end=$(date +%s)
echo -e "${NC}Runtime: $((end-start)) seconds ..."