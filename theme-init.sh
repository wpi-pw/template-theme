#!/bin/bash

# WPI Theme
# by DimaMinka (https://dima.mk)
# https://github.com/wpi-pw/app

# Get config files and put to array
wpi_confs=()
for ymls in wpi-config/*
do
  wpi_confs+=("$ymls")
done

# Get wpi-source for yml parsing, noroot, errors etc
source <(curl -s https://raw.githubusercontent.com/wpi-pw/template-workflow/master/wpi-source.sh)

zip="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/([^\/:]+)\/([^\/:]+)\/(.+).zip$"
cur_env=$(cur_env)
version=""
package=$(wpi_yq themes.parent.name)
package_ver=$(wpi_yq themes.parent.ver)
repo_name=$(echo ${package} | cut -d"/" -f2)
no_dev="--no-dev"
dev_commit=$(echo ${package_ver} | cut -d"#" -f1)
ver_commit=$(echo ${package_ver} | cut -d"#" -f2)
setup_name=$(wpi_yq themes.parent.setup)
# Check the workflow type
content_dir=$([ "$(wpi_yq init.workflow)" == "bedrock" ] && echo "app" || echo "wp-content")

# Switch package to theme release for specific environment
if [[ "$(wpi_yq themes.parent.symlink.env)" == "$cur_env" ]]; then
  theme_release && exit
fi

# Get the theme and run install by type
printf "${GRN}=============================================${NC}\n"
printf "${GRN}Installing theme $(wpi_yq themes.parent.name)${NC}\n"
printf "${GRN}=============================================${NC}\n"

# Running theme install via wp-cli
if [ "$(wpi_yq themes.parent.package)" == "wp-cli" ]; then
  # Install from zip
  if [[ $(wpi_yq themes.parent.zip) =~ $zip ]]; then
    wp theme install $(wpi_yq themes.parent.zip) --quiet
  else
    # Get theme version from config
    if [ "$package_ver" != "null" ] && [ "$package_ver" ] && [ "$package_ver" != "*" ]; then
      version="--version=$package_ver --force"
    fi
    # Default plugin install via wp-cli
    wp theme install $package --quiet ${version}
  fi

  # Run renaming process
  if [ "$(wpi_yq themes.parent.rename)" != "null" ] && [ "$(wpi_yq themes.parent.rename)" ]; then
    # Run rename commands
    mv ${PWD}/web/$content_dir/themes/$package ${PWD}/web/$content_dir/themes/$(wpi_yq themes.parent.rename)
  fi
fi

# Get theme version from config
if [ "$package_ver" != "null" ] && [ "$package_ver" ] && [ "$package_ver" != "*" ]; then
  json_ver=$package_ver
  # check for commit version
  if [ "$dev_commit" == "dev-master" ]; then
    json_ver="dev-master"
  fi
else
  # default versions
  json_ver="dev-master"
  package_ver="dev-master"
  ver_commit="master"
fi

# Running theme install via composer from bitbucket/github
if [ "$(wpi_yq themes.parent.package)" == "bitbucket" ] || [ "$(wpi_yq themes.parent.package)" == "github" ]; then
  # Install plugin from private/public repository via composer
  # Check for setup settings
  if [ "$(wpi_yq themes.parent.setup)" != "null" ] && [ "$(wpi_yq themes.parent.setup)" ]; then
    name=$(wpi_yq themes.parent.setup)

    # OAUTH for bitbucket via key and secret
    if [ "$(wpi_yq themes.parent.package)" == "bitbucket" ] && [ "$(wpi_yq init.setup.$name.bitbucket.key)" != "null" ] && [ "$(wpi_yq init.setup.$name.bitbucket.key)" ] && [ "$(wpi_yq init.setup.$name.bitbucket.secret)" != "null" ] && [ "$(wpi_yq init.setup.$name.bitbucket.secret)" ]; then
      composer config --global --auth bitbucket-oauth.bitbucket.org $(wpi_yq init.setup.$name.bitbucket.key) $(wpi_yq init.setup.$name.bitbucket.secret)
    fi

    # OAUTH for github via key and secret
    if [ "$(wpi_yq themes.parent.package)" == "github" ] && [ "$(wpi_yq init.setup.$name.github-token)" != "null" ] && [ "$(wpi_yq init.setup.$name.github-token)" ] && [ "$(wpi_yq init.setup.$name.github-token)" != "null" ] && [ "$(wpi_yq init.setup.$name.github-token)" ]; then
      composer config -g github-oauth.github.com $(wpi_yq init.setup.$name.github-token)
    fi
  fi

  # Get parent theme branch keys
  mapfile -t branch < <( wpi_yq "themes.parent.branch" 'keys' )
  # Get parent theme branch by current env
  for i in "${!branch[@]}"
  do
    if [ "${branch[$i]}" == $cur_env ]; then
      ver_commit=$(wpi_yq "themes.parent.branch.$cur_env")
    fi
  done

  # Build package url by package type
  if [ "$(wpi_yq themes.parent.package)" == "bitbucket" ]; then
    package_url="https://bitbucket.org/$package"
    package_zip="https://bitbucket.org/$package/get/$ver_commit.zip"
  elif [ "$(wpi_yq themes.parent.package)" == "github" ]; then
    package_url="git@github.com:$package.git"
    package_zip="https://github.com/$package/archive/$ver_commit.zip"
  fi

  # Rename the package if config exist
  if [ "$(wpi_yq themes.parent.rename)" != "null" ] && [ "$(wpi_yq themes.parent.rename)" ]; then
      package=$(wpi_yq themes.parent.rename)
  fi

  # Get GIT for local and dev
  if [ "$cur_env" == "local" ] || [ "$cur_env" == "dev" ]; then
    # Reset --no-dev
    no_dev=""

    # Composer config and install - GIT version
    composer config repositories.$package '{"type":"package","package": {"name": "'$package'","version": "'$json_ver'","type": "wordpress-theme","source": {"url": "'$package_url'","type": "git","reference": "master"}}}'
    composer require $package:$package_ver --update-no-dev --quiet
  else
    # Remove the package from composer cache
    if [ -d ~/.cache/composer/files/$package ]; then
      rm -rf ~/.cache/composer/files/$package
    fi

    # Composer config and install - ZIP version
    composer config repositories.$package '{"type":"package","package": {"name": "'$package'","version": "'$package_ver'","type": "wordpress-theme","dist": {"url": "'$package_zip'","type": "zip"}}}'
    composer require $package:$package_ver --update-no-dev --quiet
  fi
fi

# Check if setup exist
if [ "$setup_name" != "null" ] && [ "$setup_name" ]; then
  composer=$(wpi_yq init.setup.$setup_name.composer)
  # Run install composer script in the theme
  if [ "$composer" != "null" ] && [ "$composer" ]  && [ "$composer" == "install" ] || [ "$composer" == "update" ]; then
    composer $composer -d ${PWD}/web/app/themes/$package $no_dev --quiet
  elif [ "$composer" != "null" ] && [ "$composer" ]  && [ "$composer" == "dump-autoload" ]; then
    composer dump-autoload -o -d ${PWD}/web/app/themes/$package --quiet
  elif [ "$composer" != "null" ] && [ "$composer" ]  && [ "$composer" == "install && dump-autoload" ]; then
    composer install -d ${PWD}/web/app/themes/$package $no_dev --quiet
    composer dump-autoload -o -d ${PWD}/web/app/themes/$package --quiet
  fi

  # Run npm scripts
  if [ "$(wpi_yq init.setup.$setup_name.npm)" != "null" ] && [ "$(wpi_yq init.setup.$setup_name.npm)" ]; then
      # run npm install
      npm i &> /dev/null --prefix ${PWD}/web/app/themes/$package
    if [ "$cur_env" == "local" ] || [ "$cur_env" == "dev" ]; then
      eval $(wpi_yq init.setup.$setup_name.npm.dev) --prefix ${PWD}/web/app/themes/$package
    else
      eval $(wpi_yq init.setup.$setup_name.npm.prod) --prefix ${PWD}/web/app/themes/$package
    fi
  fi
fi
