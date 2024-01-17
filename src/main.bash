#!/bin/bash

# ----------- Overview of this code -----------
# This code is intended to migrate git history from a source remote repository
# (e.g., a Bitbucket account) to a sink remote repository (e.g., a Github account).
# See the README.md and config file accompanying this file for more information.
#

function notify_slack_if_error_logs(){
    #---
    #Purpose: Notify the dev team if there were any error logs in the past run.
    #---
    ERROR_COUNT=$(grep -ci "ERROR" ../logs/_log_overall.out)
    if [ $ERROR_COUNT -gt 0 ]; then
        msg="<!channel> :warning: *Bitbucket Migration Script finished with errors. *ERRORS: $ERROR_COUNT*.\nSSH into \`my.remote.server.com\` to see logs."
    else
        msg=":white_check_mark: *Bitbucket Migration Script finished successfully.\nSSH into \`my.remote.server.com\` to see logs."
    fi

    curl -X POST $slack_notification_webhook -d "{\"text\":\"$msg\"}"
}

#----------
#-- Main --
#----------

#---------------------
echo "starting at $(date)"
start_time=`date +%s`
#---------------------

# Reading in config
source ../migrator.cfg

# Reading in secrets
source ../secrets.cfg

# Adding SSH keys to this shell instance:
eval $(ssh-agent -s)
ssh-add $source_ssh_key_local_path
ssh-add $sink_ssh_key_local_path

#Cleaning out old log files (only necessary to look at logs from the past run)
rm -rf ../logs/_log_overall.out


#Max number of repos to process concurrently
batch_size=3

for repo in "${repos_to_migrate[@]}"
do
    #Processing repos in batches
    #code source: https://unix.stackexchange.com/questions/103920/parallelize-a-bash-for-loop
    ((i=i%batch_size)); ((i++==0)) && wait
    echo "Processing ${repo}..."
    source migrate.bash "${repo}" &
done

wait
notify_slack_if_error_logs

#---------------------
echo "finished at $(date)"
end_time=$(date +%s)
echo "Run completed in $((end_time-start_time)) seconds"
#---------------------
