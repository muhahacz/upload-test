#!/bin/bash

projectsPath=projects.json
schemaPath=schema.json

set -xe

_logMessage () {
  type=$1
  message=$2
  date=$(date -I'seconds')

  printf '%s [%s] %s\n' "$date" "$type" "$message"
}

_validate () {

  local fail=false

  if ! yajsv -q -s "$schemaPath" "$projectsPath" ; then
    _logMessage error "Invalid schema."
    fail=true
  fi
  
  echo "$fail"

  for i in .name .path; do
    if ! jq --arg type $i -c '(unique_by($type)|length) as $unique | length == $unique' "$projectsPath" > /dev/null 2>&1 ; then
      _logMessage error "Name and Path must be unique."
      fail=true
    fi
  done
  
  echo "$fail"

  jq -r  '.[] | "" + .name + " " + .path' "$projectsPath" | while read -r name path; do

    _logMessage info "Validating project: $name ."

    if ! [ -d "$path" ] || ! [ -f "$path/terragrunt.hcl" ]; then
      _logMessage error "Project $name must contain terragrunt.hcl file."
      fail=true
    fi
  done
  
  echo "$fail"

  if $fail; then
    _logMessage error "Failed."
    exit 1
  else
    _logMessage info "Validation done."
    exit 0
  fi
}

_getCommitRange () {
  if [ -z "$CI_BUILD_BEFORE_SHA" ] || [ -z "$CI_COMMIT_SHA" ]; then
    _logMessage error "CI_COMMIT_SHA and CI_BUILD_BEFORE_SHA must be set."
    exit 1
  elif [ "$CI_BUILD_BEFORE_SHA" == "0000000000000000000000000000000000000000" ]; then
    range="HEAD"
  else
    range="$CI_BUILD_BEFORE_SHA...$CI_COMMIT_SHA"
  fi
}


_getProjectsToChange () {
  action=$1

  declare -a pnames
  declare -a ppaths
  declare -a pmethods

  if [ -n "$PROJECT" ]; then
    projects=( "$(jq -r  '.[].name' "$projectsPath")" )
    if [[ ! " ${projects[*]} " =~ $PROJECT ]]; then
      _logMessage error "Project not found: $PROJECT"
      exit 1
    else
      _logMessage info "Project: $PROJECT will be changed."

      ppath=$(jq --arg pname "$PROJECT" -r  '.[] |  select(.name == $pname ).path' "$projectsPath")
      pmethod=$(jq --arg pname "$PROJECT" -r  '.[] |  select(.name == $pname ).login' "$projectsPath")

      pnames+=( "$PROJECT" )
      ppaths+=( "$ppath" )
      pmethods+=( "$pmethod" )

    fi
  else
     while read -r pname ppath pmethod ; do
      echo "A: $pname $ppath $pmethod"
      if ! git diff --exit-code --quiet "$range" -- "$ppath"; then
        echo "B: $pname $ppath $pmethod"
        _logMessage info "Project: $pname will be changed."

        pnames+=( "$pname" )
        ppaths+=( "$ppath" )
        pmethods+=( "$pmethod" )
        
        echo "${pnames[@]}"
        echo "${ppaths[@]}"
        echo "${pmethods[@]}"
        echo "${#pnames[@]}"
        echo "${#ppaths[@]}"
        echo "${#pmethods[@]}"
        
        if (( "${#pnames[@]}" > 0 )); then 
          echo zajimave
        else
          echo nezajimave
        fi
        
      fi
    done < <(jq -r  '.[] | "" + .name + " " + .path + " " + .login' "$projectsPath")
  fi

   echo "${#pnames[@]}"
   echo "${pnames[@]}"

  if (( "${#pnames[@]}" > 0 )); then 
    echo zajimave
  else
    echo nezajimave
  fi

}


_cliLogin () {
  cloud=$1
  if [ "$cloud" == "azure" ]; then
    maxtimeout="900"
    regular="^To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code [A-Z0-9]{9} to authenticate."

    exec 3< <( timeout --preserve-status -k 1 "$maxtimeout" az login --use-device-code --output none 2>&1 ) ; pid=$!
    while IFS= read -r line <&3
    do
        if [[ $line =~ $regular ]]; then
            printf '%s' "$line"
            _logMessage info "Login invoked. Will timeout in $maxtimeout"
            wait $pid
        else
            _logMessage info "Unknown error. Hint: Check regex vs output"
            #break
            exit 1
        fi
    done
    _logMessage info "Logout from azure."
  elif [ "$cloud" == "aws" ]; then
    _logMessage info "todo aws."
    elif [ "$cloud" == "all" ]; then
      _logMessage info "Login to all."
  else
    _logMessage info "No need to login."
  fi
}



_cliLogout () {
  cloud=$1

  if [ "$cloud" == "azure" ]; then
    az logout || true
    _logMessage info "Logout from azure."
  elif [ "$cloud" == "aws" ]; then
    _logMessage info "Logout from aws."
  elif [ "$cloud" == "all" ]; then
    _logMessage info "Logout from all."
  else
    _logMessage info "No need to logout."
  fi
}



case  $MODE  in
      preflight)
          _validate
          ;;
      validate)
          _getCommitRange
          _getProjectsToChange validate
          ;;
      plan)
          _getCommitRange
          _getProjectsToChange plan
          ;;
      apply)
          _getCommitRange
          _getProjectsToChange apply
          ;;
      destroy)
          _getCommitRange
          _getProjectsToChange destroy
          ;;
      *)
          printf 'MODE variable must be one of [preflight, validate, plan, apply, destroy]'
          ;;
esac
