source ~/.devrc

if [[ -z $DEV_HOME ]]; then
  echo "DEV_HOME must be defined as the root of your groups"
  exit 1
fi

DEV_CACHE_PATH=~/.devcache

# How long to cache a github api response
# user behavior suggests that once presented with the full list, they may
# trigger a few more completion runs before settling on the full completed
# name of something, so having the cache is useful
DEV_CACHE_TTL=30 # seconds

_dev_init_cache() {
  if [[ ! -d $DEV_CACHE_PATH ]]; then
    mkdir $DEV_CACHE_PATH
  fi
}

_dev_github() {
  local ENDPOINT=$1
  shift
  local SHA256SUM=($(echo "$ENDPOINT $@" | sha256sum))
  local CACHE_ID=${SHA256SUM[0]}
  local CACHE_FILE=$DEV_CACHE_PATH/$CACHE_ID

  if [[ -e $CACHE_FILE ]]; then
    local NOW=$(date +%s)
    local CACHE_MTIME=$(date -r $CACHE_FILE +%s)
    if [[ $((NOW - CACHE_MTIME)) -lt $DEV_CACHE_TTL ]]; then
      cat $CACHE_FILE
      return
    else
      rm $CACHE_FILE
    fi
  fi

  if http --auth="$GITHUB_USER:$GITHUB_TOKEN" \
    --timeout=5 \
    --check-status --ignore-stdin \
    --download --output=$CACHE_FILE \
    --pretty=none \
    https://api.github.com/$ENDPOINT \
    "$@" 2>/dev/null 1>/dev/null; then

    cat $CACHE_FILE
  else
    echo "[]"
  fi
}

_dev_github_org_repos() {
  local ORG=$1
  _dev_github orgs/$ORG/repos per_page==1000
}

_dev_github_search() {
  _dev_github search/repositories q=="$*"
}

_dev_github_repo_exists() {
  local ORG=$1
  local REPO=$2

  http --auth="$GITHUB_USER:$GITHUB_TOKEN" \
    --timeout=3 \
    --check-status --ignore-stdin \
    --pretty=none \
    https://api.github.com/repos/$ORG/$REPO 2>/dev/null 1>/dev/null
}

_dev_completer() {
  local DEBUG=${DEBUG:-false}
  local COMP_WORDCOUNT=${#COMP_WORDS[@]}
  local CURRENT=${COMP_WORDS[COMP_CWORD]}
  local ENTRY=$1
  $DEBUG && echo
  $DEBUG && echo "ENTRY [$ENTRY]"
  $DEBUG && echo "COMP_WORDCOUNT [$COMP_WORDCOUNT]"
  $DEBUG && echo "COMP_LINE [$COMP_LINE]"
  $DEBUG && echo "COMP_WORDS [${COMP_WORDS[@]}]"
  $DEBUG && echo "COMP_CWORD [$COMP_CWORD]"


  if [[ $ENTRY == "dev" ]]; then
    $DEBUG && echo "Invoked by default name 'dev'"
  else
    $DEBUG && echo "Invoked by group name '$ENTRY'"
  fi

  # We are trying to complete a group name
  if [[ $ENTRY == "dev" ]] && [[ $COMP_WORDCOUNT -eq 2 ]]; then
    DEV_GROUPS="$(find -L ~/dev -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"
    $DEBUG && echo "DEV_GROUPS [$DEV_GROUPS]"
    COMPREPLY=( $(compgen -W "$DEV_GROUPS" -- $CURRENT ) );

  # We are trying to complete a repo name
  elif [[ $ENTRY != "dev" ]] || [[ $COMP_WORDCOUNT -eq 3 ]]; then
    if [[ $ENTRY == "dev" ]]; then
      GROUP=${COMP_WORDS[1]}
    else
      GROUP=$ENTRY
    fi
    GROUP_PATH=~/dev/$GROUP
    $DEBUG && echo "GROUP_PATH [$GROUP_PATH]"

    # If we have a value for a repo it exists as a path then we have no more to
    # complete. TODO: allow deeper cd'ing into repo?
    if [[ ! -z $CURRENT ]] && [[ -d $GROUP_PATH/$CURRENT ]]; then
      return
    fi
    LOCAL_REPOS="$(find -L $GROUP_PATH -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"
    GITHUB_REPOS="$(_dev_github_org_repos $GROUP | jq '.[].name' -r)"
    REPOS="$(echo -e "$LOCAL_REPOS\n$GITHUB_REPOS" | sort | uniq)"
    $DEBUG && echo "REPOS [$REPOS]"
    COMPREPLY=( $(compgen -W "$REPOS" -- $CURRENT ) );
  fi

  $DEBUG && echo "COMPREPLY set to: [${COMPREPLY[@]}]"
}

_dev_init_cache

dev() {
  local ENTRY=${FUNCNAME[-1]}
  if [[ $ENTRY == "dev" ]]; then
    local GROUP=$1
    shift
  elif [[ -d $DEV_HOME/$ENTRY ]]; then
    local GROUP=$ENTRY
  fi

  if [[ -z $1 ]]; then
    cd $DEV_HOME/$GROUP
  else
    local REPO=$1
    local TARGET=$DEV_HOME/$GROUP/$REPO

    if [[ -d $TARGET ]]; then
      cd $TARGET
    # elif repo exists we should clone it
    elif _dev_github_repo_exists $GROUP $REPO; then
      builtin cd $DEV_HOME/$GROUP
      git clone git@github.com:${GROUP}/${REPO}.git $REPO
      cd $TARGET
    else
      mkdir -p $TARGET
      builtin cd $TARGET
      git init
    fi
  fi
}

for GROUP in $(find -L $DEV_HOME -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do
  eval "$(cat <<EOF
$GROUP() {
  dev "\$@"
}
EOF
)"
  complete -F _dev_completer $GROUP
done

complete -F _dev_completer dev
