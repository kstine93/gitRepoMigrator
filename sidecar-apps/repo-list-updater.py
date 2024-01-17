"""
repo-list-updater.py

Purpose: This script queries Bitbucket projects and collects the list of repos
within them. It then updates the list of repos to migrate in the accompanying
'../migrator.cfg' file.

This script is meant to run as a helper/utility for the git-repo-migrator
tool, which consumes this '../migrator.cfg' file when it runs.
"""

import requests
from requests.auth import HTTPBasicAuth
from re import compile, sub, DOTALL
from toml import load as tomlload

#---------------
#--USER CONFIG--
#---------------
#filepath of the configuration file we want to edit:
filepath = '../migrator.cfg'

#Edit this list to force this script to ignore certain repos. These repos will
#then not be added to the list of repos to migrate. This is generally done for
#repos which are deprecated, but still kept in Bitbucket for archival purposes.
repos_to_ignore=[
    'test-application',,
    'terraform-in-bitbucket-test',
]

#The project keys in Bitbucket that you want to migrate the repos for.
#All repos in these projects - except those listed in 'repos_to_ignore' above -
#will be added to the list of repos to migrate:
target_bitbucket_project_keys=[
    "PROJ1"
    "OTHERPROJ"
]


#---------------
#--FILE CONFIG--
#---------------
with open('../secrets.cfg', 'r') as file:
    secrets=tomlload(file)


#-------------
#--FUNCTIONS--
#-------------
def getFromAPI(url:str, user:str, apikey:str) -> dict:
    """Generic function to call the AN API with GET"""
    response = requests.get(
        url = url,
        headers = {"Accept": "application/json"},
        auth = HTTPBasicAuth(user, apikey)
    )
    return response

#----------------------
def getRepoNamesFromBitbucketProject(project:str, user:str, apikey:str) -> dict:
    """Function to query the Bitbucket API for repos in a particular project.
    A simple list of these repos is returned."""

    url = f'https://api.bitbucket.org/2.0/repositories/my-bb-org?q=project.key="{project}"'
    repos = []

    while True:
        response = getFromAPI(url=url, user=user, apikey=apikey)

        data = response.json()

        repos += [item['name'] for item in data['values']]
        if 'next' in data.keys():
            url = data['next']
        else:
            break

    return repos


#--------
#--MAIN--
#--------
repo_list=[]

#Collecting the names of repos from all target Bitbucket projects
for proj in target_bitbucket_project_keys:
    repo_list += getRepoNamesFromBitbucketProject(
        project=proj,
        user=secrets['bitbucket_username'],
        apikey=secrets['bitbucket_api_password']
    )

#----------------------
#Removing unwanted repos:
repo_set = set(repo_list) - set(repos_to_ignore)
#Sorting
sorted_repo_list = sorted(repo_set,key=str.lower)

#----------------------
#Reading in existing config file as a string:
with open(filepath, 'r') as f:
    data = f.read()


#----------------------
#Formatting list of repos so that it's compatible with bash scripts:
#EX:
# repos_to_migrate=('repo1'
# 'repo2'
# 'repo3'
# )
#Encasing each element in single quotes & separating with line break:
repo_list_sep = "\n".join(f"'{repo}'" for repo in sorted_repo_list)
#Wrapping list in parentheses
repo_list_string = f"({repo_list_sep})"


#----------------------
#Replacing old list of repos with new list in config string:
regex=compile("repos_to_migrate=\(.*?\)",flags=DOTALL)
new_data = sub(regex,f"repos_to_migrate={repo_list_string}",data)


#----------------------
#Writing new version of config to file:
with open(filepath, 'w') as f:
    f.write(new_data)

