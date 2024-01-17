#!/bin/bash

# ----------- Overview of this code -----------
# This code should be called with the name of a repository that should be migrated
# from one remote git repository to another, and with all of the commit messages
# anonymized in certain ways.
# This script is designed to be called from the accompanying 'main.bash' script
# which iterates over an array of repository names.

#---------------
#-- Functions --
#---------------
function logging_setup(){
    #---
    #Purpose: Set up logging. This is done on a repo basis rather than for the
    #entire script so that concurrent executions still produce in-order logs for
    #each processed repo.
    #---
    #Setting up logging specific to this repo:
    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    #Creating log file
    log_file_path="$BASE_PATH/../logs/log_$1.out"
    #NOTE: Purposefully overwriting rather than appending to logs. Script will
    #run infrequntly and only the last log is relevant (for debugging).
    exec 1>$log_file_path 2>&1
}

#---------------
function log_outcome(){
    #---
    #Purpose: Function logging the success of this script to a specific output.
    #---
    overall_log_path="$BASE_PATH/../logs/_log_overall.out"
    echo $1 >> $overall_log_path
}

#---------------
function initial_setup(){
    #---
    #Purpose: Read in configuration and otherwise set up global variables for
    #the remainder of the script.
    #---

    # < CODE HERE TO IMPORT LIST OF REPOS FROM BITBUCKET
    # AND WRITE LIST TO CONFIG FILE >

    #This bash script requires a lot of rapid cloning - increasing the size of the
    #git buffer helps ensure that we don't get errors like "fatal: the remote end
    #hung up unexpectedly"
    git config --project http.postBuffer 500M
    git config --project http.maxRequestBuffer 100M

    # Reading in config
    source ../migrator.cfg

    #For all array objects, split them into an array that bash can use by replacing
    #the comma delimiter with a space:
    branches_to_migrate=${branches_to_migrate//,/ }

    # Reading in secrets
    source ../secrets.cfg
}

#---------------
function check_curl_success() {
    #---
    # Purpose: This code parses an curl response with all of the headers (e.g.,
    # as created by `curl -i`). This code expects that the first line of this
    # output is something like "HTTP/1.1 401 Unauthorized".
    # If the response code is not 200, 201, 202, etc., then '1' is returned.
    #---

    STATUS_CODE_REGEX="HTTP/.{1,4} ([0-9]{3})"
    #Find first match to the above regex:
    [[ $1 =~ $STATUS_CODE_REGEX ]]

    #If the extracted status code is NOT a 200 code (200, 201, 202, etc.),
    #then return '1' to indicate an error.
    MATCHES_200_CODES=$(grep -ci '20[0-9]' <<< ${BASH_REMATCH[1]})
    if [ $MATCHES_200_CODES -lt 1 ] ; then
        return 1
    fi
}

#---------------
function create_new_gh_repo() {
    #---
    # Purpose: This code creates a new repository with a name provided as an argument
    # The code is currently configured to create a new repo in a specified GitHub org.
    # Returns an error code of '1' if the the API call returned with a non-200 status.
    #---

    RES=$(
        curl -i \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_api_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/orgs/$github_organization/repos" \
        -d "{\"name\":\"$1\",\"private\":true}"
    )

    #Logging full API output
    echo "${RES}"

    return $(check_curl_success "${RES}")
}

function add_team_read_access_to_gh_repo(){
    #---
    # Purpose: This code gives a specific team access to the repo. Note that
    # the team must already have been created in the Github org beforehand.
    #$1 == repo name | $2 == team 'slug' (modified team name in Github) | $3 == access type
    #---
    curl \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $sink_api_token" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/$sink_organization/teams/$2/repos/$sink_organization/$1 \
    -d "{\"permission\":\"$3\"}"
}

#---------------
function replace_gh_repo_topics() {
    #---
    # Purpose: This code replaces the topics for a provided Github repo (arg #1)
    # with a formatted list of topics (arg #2)
    # The code is currently configured to work with a specified GitHub org.
    # Arg #2 example: "[\"infrastructure\",\"business-intelligence\"]"
    #---

    curl -L \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $github_api_token" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$github_organization/$1/topics \
    -d "{\"names\":$2}"
}


#---------------
function process_repo() {
    #---
    #Purpose: Complete all steps needed to migrate a local git repository
    #to the configured destination, including any transformations needed.
    #---

    #Iterate over every branch that I need to migrate:
    for branch in $branches_to_migrate
    do
        # sleep 5
        echo "---- Processing branch '$branch' of repo '$1' ----"

        if [ -d $repo ]; then
            rm -rf $repo
        fi

        #Saving output from git clone command (Note that "2>&1" will save the output in the variable, but
	#not print to the console
        CLONE_RESULT=$(git clone --branch $branch git@$source_remote_url/$repo.git 2>&1)
        #If the cloning was a success, proceed with processing:
        if [ $? -eq 0 ] ; then
            cd $repo
            process_branch $repo $branch
            cd ..
            rm -rf $repo
        else
            #Error handling: If the clone command returned with the string
            #'remote <branch> not found in upstream', then this is an error we can
            #ignore. If it is any other error, then we need to log it:
            NOT_FOUND_UPSTREAM=$(grep -ci "not found in upstream" <<< $CLONE_RESULT)
            if [ $NOT_FOUND_UPSTREAM -lt 1 ]; then
                echo $CLONE_RESULT
                log_outcome "$(date) -- ERROR: failed to clone '$branch' branch in repo '$repo'."
            fi
        fi
    done
}

#---------------
function process_branch() {
    #---
    #Purpose: Update target branch with all of the commits in the source branch
    # $1 == repo  $2 == branch
    #---

    #Using filter-repo instead of an interactive rebase to quickly and efficiently edit
    #the git history for this branch
    git filter-repo \
    --message-callback "return re.sub(b'Approved-by: .*?(\n|$)',b'Approved-by: example-dev\n', message)" \
    || { echo 'message edit failed - aborting'; exit 1; }

    git filter-repo \
    --name-callback "return b'$anon_author_name'" \
    --email-callback "return b'$anon_author_email'" \
    || { echo 'author edit failed - aborting'; exit 1; }

    #Re-adding remote - somehow this is removed by filter-repo:
    git remote add origin git@$sink_remote_url/$1.git \
    || { echo 'remote origin set failed - aborting'; exit 1; }

    #Look at target git remote repo and determine what its latest commit is.
    git remote set-url origin git@$sink_remote_url/$1.git

    #Checking if the remote origin exists (i.e., is there already a remote repository
    #on the sink git platform?)
    git ls-remote --exit-code origin > /dev/null
    STATUS=$?
    if [ $STATUS -ne 0 ] ; then
        echo "---- No remote repo found for '$1'. Attempting to create... ----"
        #Attempt to create new repository:
        create_new_gh_repo $1
        #If creation fails, we have to abort the migration of this repo:
        if [ $? != 0 ]; then
            log_outcome "$(date) -- ERROR: Creation of repo '$1' failed. Migration of this repo aborted."
            return 1
        fi

        #Giving specific permissions to a team in the sink platform, if a team
        #is specified:
        if [ ! -z ${sink_team_access_name+x} ]; then
            add_team_read_access_to_gh_repo $1 $sink_team_access_name $sink_team_access_type
        fi
    fi

    echo "---- Pushing to remote origin: branch '$2' of repo '$1' ----"
    git push -u git@$sink_remote_url/$1
}

#---------------
function check_for_spaces() {
    #---
    #Purpose: Returns a '1' if a given string has spaces in it.
    #---
    if [[ "${1}" == *" "* ]]; then
        return 1
    fi
}

#----------
#-- Main --
#----------
BASE_PATH=$PWD

#----------
logging_setup "${1}"

#----------
#Timestamp
echo "starting at $(date)"
start_time=`date +%s`

#----------
initial_setup

#----------
# Create 'repos' directory, if it doesn't exist and go to it.
if [ ! -d "../repos" ] ; then
    echo "Making new directory to hold repos..."
    mkdir ../repos
fi
cd ../repos

#----------
#If repo name has spaces, do not process it to avoid errors. Spaces in repo
#names are automatically replaced by '-' in Github and this code cannot (yet) account for this.
check_for_spaces "${1}"
if [ $? -ne 0 ]; then
    log_outcome "$(date) -- ERROR: Repo '${1}' cannot have spaces in its name. Migration of this repo aborted."
    exit 1
fi

#----------
process_repo $1

#----------
#Logging outcome of this repo processing to an overall log file:
log_outcome "$(date) -- DONE: Repo '$1' fully processed"

#Timestamp
echo "finished at $(date)"
end_time=$(date +%s)
echo "Run completed in $((end_time-start_time)) seconds"
#---------------------
