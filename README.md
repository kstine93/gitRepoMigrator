# git-repo-migrator

## Why was this project created?
This project was originally created to build a solution that would allow remote repository contents of Bitbucket to be mirrored in GitHub.
The use case for this ticket was specifically exporting a specific codebase from Bitbucket to Github so that a client could have access to the codebase without needing direct access to our live Bitbucket account.

Additionally, this code was required to anonymize the commits in Bitbucket before uploading them to Github, so there is additionally code in this repository to edit the commits (anonymizing author names, etc.).

**WARNING: This code can and will overwrite commits locally and upload these overwritten commits (with different commit hashes) to a remote repository. BE CAREFUL.**

> **NOTE:** The branch `full-history-version` of this code represents a version of the code that is capable of migrating the *entire git history*. Make sure you are using that branch if you need that functionality.

## What does this project do?
The code within this file pulls the latest commits from the source git repository, makes edits to the commits (e.g., renaming the authors in order to anonymize the code base), and then pushes the commits to the sink git repository.
This code can be run on almost all environments (see dependencies below), and can be set up to run on any schedule from hypothetically any source and any sink git repository.
This code is **idempotent** in that git is idempotent: this code is basically just a wrapper for `git clone` and `git push` commands (with some minor editing of commits between those two tasks). As long as the code you are pushing to the target repo has the same git history as the code already on the remote repo, you should face no issues in re-running the migration as often as you like.

## Current implementation details
As of Oct. 17, 2023 this code is set up to run on `my.remote.server.com` within the `/apps/git-repo-migrator` directory. A crontab was set up under the root user (`sudo -u root crontab -e` to edit this) which runs the migrator code the first day of every month according to this command: `00 21 1 * * cd /apps/git-repo-migrator/src && sudo bash main.bash`


## How do I get started with this code?

### Installing dependencies
- This code uses first and foremost `bash`
  - This should be natively available on all unix systems (additionally installable on Windows machines as part of the 'Windows subsystem for Linux').
- This code additionally uses `git` as the primary tool to retrieve, manipulate, and push code and version history between remote repositories.
  - You can install git using [these instructions](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- This code also uses an external package [git-filter-repo](https://github.com/newren/git-filter-repo), which is actually a single Python file
  - You will need to have Python installed to run the file. Install Python using [these instructions](https://www.python.org/downloads/)
  - You can then install this Python file with `pip install git-filter-repo` or by using the install instructions in the [README for this package](https://github.com/newren/git-filter-repo#readme).

### Adding all dependencies to the $PATH
By default, installing 'git' and 'bash' should automatically add these executables to the system path (so that these executables can be found from the shell).

'git-filter-repo', however, is not by default added to the command line, so it will most likely not be able to run it until you add it to the system path.
> **TIP:** Try to run `git filter-repo` in the shell. If you get the response `No arguments specified`, then it's installed and on the system path.
>
> This package should be installed somewhere like `C:\Users\<USER>\AppData\Local\Programs\Python\Python311\Scripts`. Find out where it is installed and add this to the system path if this command fails instead.

### Setting up SSH keys
This code requires that SSH keys be set up and stored locally to enable 'git' to access the remote repositories.
Please follow the guidelines on how to set up SSH keys in the documentation of the remote platform (e.g., [Github's docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent), [Bitbucket's docs](https://support.atlassian.com/bitbucket-cloud/docs/configure-ssh-and-two-step-verification/)).
Once you have created the SSH keys and stored them locally, see the '`migrator.cfg` configuration document and change the location path of the `source_ssh_key_local_path` and `sink_ssh_key_local_path` variables.

### Setting up API access tokens
#### Github
If Github is your *sink* remote repository (i.e., where you want the code to be migrated *to*), then you'll need to follow these steps:
1. Create a *personal access token* on the Github account where you want the repos migrated to
2. Give the token the following permissions:
   1. Repository Permissions:
      1. **Administration - Read & Write**
      2. **Metadata - Read**
   2. Organization permissions
      1. **Administration - Read & Write**
      2. **Members - Read & Write**

---

### Running the code
Once you have completed the steps above, you can run this code with `/bin/bash main.bash` from the command line. You will start to see output on the console and the `logs` directory will have logs for each repo that is processed, as well as an overall log file `_log_overall.out`.


## How do I configure this code to work differently?
There are 2 configuration files included in this repo to enable easier configuration.
`migrator.cfg` handles most of the configuration- including what the source and sink (target) git remote repositories should be (originally set up with a Bitbucket organization as the source and a Github organization as the sink).

See the comments in this file for more information about each configuration option.

`secrets.cfg` holds secrets-level data. Many values here will be blank by default. The best place to look for where these values are used is within the `migrate.bash` file, where they are primarily used for calling APIs / webhooks.

## Sidecar app: repo-list-updater.py
As of Jan. 11, 2024 there is a script `repo-list-updater.py` set up to run alongside the main script for this tool.
This script's purpose is to query Bitbucket to find the current list of repositories from specific Bitbucket projects, and then update the `repos_to_migrate` list in the `migrator.cfg` file, so that this updated list can be consumed by the main script when it runs.
A crontab was set up under the root user (`sudo -u root crontab -e` to edit this) which runs this script the first day of every month according to this command: `00 19 1 * * cd /apps/git-repo-migrator/sidecar-apps && sudo python3 repo-list-updater.py`

## Troubleshooting

### `'\r': command not found`
This code was originally developed on a Windows machine - which uses carriage return and line feed characters that are incompatible with Unix systems and can produce the error `'\r': command not found`.
You can test if this affects your version of the code by running `cat -v <name_of_file>`. If you see `^M` characters at the end of lines, you have this issue.
You can solve this issue by removing the carriage return using 'sed' with `sed -i 's/\r$//' <name_of_file>`

### Other troubleshooting:
This code will create a log file for each repository which is migrated. These log files can be found in the `logs` directory.
Note that the `_log_overall.out` file in this directory contains a quick-look at if any errors occurred, however the individual log files themselves are still the best source for all information on what happened in the processing of a specific repository **(bash does not halt execution by default if there are errors - so there may be errors logged in these individual log files which are NOT recorded in `_log_overall.out`).**