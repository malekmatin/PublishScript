#!/bin/bash

set -e 

error_print() { 
    local msg=$1
    echo -e "\033[31m$msg\033[0m"
}

warning_print() { 
    local msg=$1
    echo -e "\033[33m$msg\033[0m"
}

success_print() { 
    local msg=$1
    echo -e "\033[32m$msg\033[0m"
}

print() { 
    echo $1
}

handle_sigint() {
echo -e "\nCtrl+C pressed. Stopping input..."
    trap - SIGINT
    input_stopped=true
    printf "\n"
}

navigate_to_repo() { 
    cd ../pubsctest/PubTest
}

check_repo_clean() { 
    git_status=$(git status --porcelain)

    if [[ -z "$git_status" ]]; then
        if [[ "$isverbose" == "true" ]]; then
            print "The repository is clean."
        fi
    else
        error_print "Repository contains uncommited changes"
        exit
    fi
}

check_verbose_flag() {
    for param in "$@"; do
        if [[ "$param" == "-v" ]]; then
            echo true
            return 
        fi
    done
    echo false
}

get_all_tags() { 
    tags=()
    commits=()

    while IFS=" " read -r commit_hash tag_name; do
        clean_tag_name="${tag_name/refs\/tags\//}"

        tags+=("$clean_tag_name")
        commits+=("$commit_hash")
    done < <(git show-ref --tags)

    if [[ "$isverbose" == "true" ]]; then
        echo "Tags and their corresponding commit hashes:"
        for i in "${!tags[@]}"; do
            echo "${tags[$i]} -> ${commits[$i]}"  
        done
    fi
}

find_last_tag() { 
    if [ ${#tags[@]} -gt 0 ]; then
    last_tag="${tags[$((${#tags[@]} - 1))]}"
    last_commit="${commits[$((${#commits[@]} - 1))]}"
    else
        warning_print "No tags found in the repository."
    fi
    print ""

    print "Last tag: $last_tag"
}

parse_last_tag() { 
    if [[ "$last_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"

        last_tag_major=$((major))
        last_tag_minor=$((minor))
        last_tag_patch=$((patch))

        if [[ "$isverbose" == "true" ]]; then
            print "Major: $major, Minor: $minor, Patch: $patch"
        fi
    else
        error_print "Invalid tag format. The tag must be in the format X.Y.Z"
        exit
    fi
}

check_git_repo() { 
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        error_print "Not inside a Git repository."
        exit 1
    fi
}

check_git_pull_needed() {
    LOCAL=$(git rev-parse develop)
    REMOTE=$(git rev-parse origin/develop)
    BASE=$(git merge-base develop origin/develop)

    if [[ "$isverbose" == "true" ]]; then
        print "local last commit: $LOCAL"
        print "remote last commit: $REMOTE"
        print "merge base commit: $BASE"
    fi

    # Compare local and remote
    if [ "$LOCAL" = "$REMOTE" ]; then
        if [[ "$isverbose" == "true" ]]; then
            print "Your branch is up-to-date."
        fi
    elif [ "$LOCAL" = "$BASE" ]; then
        error_print "Your branch is behind the remote. A pull is required."
        exit 0
    elif [ "$REMOTE" = "$BASE" ]; then
        if [[ "$isverbose" == "true" ]]; then
            print "Your branch is ahead of the remote."
        fi
    else
        error_print "Your branch has diverged. A pull is required"
        exit 0
    fi
}

update_patch_version() { 
    new_tag_patch=$((last_tag_patch + 1))
    echo "$last_tag_major.$last_tag_minor.$new_tag_patch"
}

update_minor_version() { 
    new_tag_minor=$((last_tag_minor + 1))
    echo "$last_tag_major.$new_tag_minor.0"
}

update_major_version() { 
    new_tag_major=$((last_tag_major + 1))
    echo "$new_tag_major.0.0"
}

input_new_tag() { 
    update_major_option=$(update_major_version)
    update_minor_option=$(update_minor_version)
    update_patch_option=$(update_patch_version)


    PS3="Please select an option: "

    select option in "$update_major_option (Major)" "$update_minor_option (Minor)" "$update_patch_option (Patch)"; do
        case $option in
            "$update_major_option (Major)")
                echo "You selected $update_major_option"
                new_tag=$update_major_option
                increment_fild="Major"
                break
                ;;
            "$update_minor_option (Minor)")
                echo "You selected $update_minor_option"
                new_tag=$update_minor_option
                increment_fild="Minor"
                break
                ;;
            "$update_patch_option (Patch)")
                echo "You selected $update_patch_option"
                new_tag=$update_patch_option
                increment_fild="Patch"
                break
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}

input_message() { 
    trap handle_sigint SIGINT

    echo "Enter your tag message (press Ctrl+C to finish):"

    input=""
    input_stopped=false

    while IFS= read -r line; do
        if [ "$input_stopped" = true ]; then
            break
        fi
        input+="$line"$'\n'
    done

    tag_msg=$input
}

get_confirmation() { 
    echo -e "Tag: $new_tag ($increment_fild)\nMessage:\n$tag_msg"
    read -p "Do you want to continue? (y/n): " confirm

    if [[ "$confirm" != [Yy] && "$confirm" != [Yy][Ee][Ss] ]]; then
        echo "Bye"
        exit 0
    fi
}

apply_new_tag() { 
    git tag -a "$new_tag" -m "$tag_msg"
}

push_tags() { 
    git push --tags
}

validate_version_header() { 
    file="version.h"
    search_string="#define VERSION \"$last_tag\""
    pwd_res=$(pwd)

    if [ -e "$file" ]; then
        if [[ "$isverbose" == "true" ]]; then
            print "Found version.h"
        fi
    else
        error_print "Can not find version.h at $pwd_res"
        exit 0
    fi

    if grep -q "$search_string" "$file"; then
        if [[ "$isverbose" == "true" ]]; then
            print "Found expected version macro."
        fi
    else
        error_print "Can not find expected version macro. ($search_string)"
        exit 0
    fi
}

change_verion_header() { 
    source_file="version.h"

    old_value="\"$last_tag\""
    new_value="\"$new_tag\""

    sed -i '' "s/#define VERSION $old_value/#define VERSION $new_value/" "$source_file"
}

check_branch() { 
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    if [[ "$current_branch" == "develop" ]]; then
        if [[ "$isverbose" == "true" ]]; then
            print "We are on develop branch"
        fi
    else
        error_print "Must be on develop branch currently we are on $current_branch"
        exit 0
    fi
}

commit_header_change() { 
    git add version.h
    git commit -m "[Publish Script] Updated version header from $last_tag to $new_tag"
    git push origin develop
}


isverbose=$(check_verbose_flag "$@")

navigate_to_repo

check_git_repo

check_repo_clean
git fetch -a 

check_branch

check_git_pull_needed

get_all_tags

find_last_tag

parse_last_tag

validate_version_header

input_new_tag

input_message

# clear

get_confirmation

change_verion_header

commit_header_change

apply_new_tag

push_tags

success_print "Version successfully updated to $new_tag"