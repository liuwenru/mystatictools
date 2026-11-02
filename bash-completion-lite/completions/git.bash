# Prefer git's own completion when the system ships it: it follows the
# installed git version and covers far more than this file. It also works
# without the bash-completion package. Set MINI_GIT_OFFICIAL_COMPLETION to a
# space-separated list of files to search, or to an empty value to disable.
for _mini_git_file in ${MINI_GIT_OFFICIAL_COMPLETION-/usr/share/bash-completion/completions/git /usr/share/git-core/contrib/completion/git-completion.bash /etc/bash_completion.d/git}; do
    [ -r "$_mini_git_file" ] || continue
    source "$_mini_git_file"
    if declare -F __git_main >/dev/null; then
        unset _mini_git_file
        return 0
    fi
done
unset _mini_git_file

_MINI_GIT_COMMANDS='add am apply archive bisect blame branch bundle checkout cherry-pick clean clone commit config describe diff fetch format-patch fsck gc grep help init log ls-files ls-remote ls-tree merge mergetool mv notes prune pull push range-diff rebase reflog remote repack reset restore revert rev-parse rm shortlog show show-branch sparse-checkout stash status submodule switch tag worktree'

# Builtins whose `--git-completion-helper` (git >= 2.18) only prints options
# and exits. Older versions reject the unknown option before doing anything.
# Commands that were shell scripts in old releases (pull, stash, bisect,
# submodule) are left out because they might not reject it.
_MINI_GIT_HELPER=' add am apply blame branch checkout cherry-pick clean clone commit config describe diff fetch format-patch gc grep init log merge mv notes push rebase remote reset restore revert rm show sparse-checkout status switch tag worktree '

# Fallback options and subcommands for git versions without the helper.
_MINI_GIT_OPTIONS='
add|--all --update --patch --interactive --force --dry-run --verbose --intent-to-add --ignore-errors
branch|--all --remotes --list --delete --move --copy --force --verbose --track --no-track --set-upstream-to= --unset-upstream --contains --merged --no-merged --show-current
checkout|--force --quiet --merge --patch --track --no-track --orphan --detach --ours --theirs
cherry-pick|--continue --abort --quit --skip --edit --no-commit --signoff --mainline= -x
clean|--dry-run --force --interactive --quiet --exclude= -d -x -X
clone|--bare --mirror --branch= --depth= --single-branch --no-checkout --origin= --recurse-submodules --shallow-submodules --quiet --progress
commit|--all --amend --message= --file= --author= --date= --no-edit --no-verify --signoff --fixup= --squash= --reuse-message= --reedit-message= --allow-empty --verbose --quiet
config|--global --system --local --file= --list --get --get-all --get-regexp --unset --unset-all --add --replace-all --edit --show-origin --name-only
describe|--all --tags --long --always --abbrev= --contains --exact-match --dirty --match=
diff|--cached --staged --stat --name-only --name-status --numstat --shortstat --patch --word-diff --color --no-color --ignore-all-space --ignore-space-change --check --no-index
fetch|--all --prune --prune-tags --tags --no-tags --depth= --unshallow --force --dry-run --quiet --verbose --multiple
format-patch|--stdout --output-directory= --numbered --cover-letter --signoff --subject-prefix=
grep|--cached --untracked --ignore-case --word-regexp --invert-match --line-number --files-with-matches --count --extended-regexp --fixed-strings --perl-regexp
init|--bare --quiet --shared --template= --separate-git-dir=
log|--oneline --graph --decorate --all --stat --name-only --name-status --patch --follow --since= --until= --author= --grep= --format= --pretty= --abbrev-commit --first-parent --no-merges --reverse --max-count=
merge|--no-ff --ff-only --squash --no-commit --edit --no-edit --abort --continue --quit --message= --strategy= --strategy-option= --allow-unrelated-histories
mv|--force --dry-run --verbose
pull|--rebase --no-rebase --ff-only --no-ff --squash --all --prune --tags --depth= --quiet --verbose --autostash
push|--all --tags --follow-tags --delete --dry-run --force --force-with-lease --set-upstream --no-verify --prune --mirror --quiet --verbose --push-option=
rebase|--continue --abort --skip --quit --edit-todo --interactive --onto= --autosquash --autostash --exec= --root --rebase-merges --keep-empty
reset|--soft --mixed --hard --merge --keep --quiet --patch
restore|--source= --staged --worktree --patch --ours --theirs --merge --quiet
revert|--continue --abort --quit --skip --edit --no-edit --no-commit --mainline=
rm|--cached --force --dry-run --quiet --ignore-unmatch -r
show|--stat --name-only --name-status --oneline --format= --pretty= --no-patch --abbrev-commit
status|--short --branch --porcelain --long --untracked-files= --ignored --ignore-submodules
switch|--create= --force-create= --detach --guess --no-guess --discard-changes --merge --orphan --track --no-track
tag|--list --delete --verify --annotate --message= --file= --sign --force --contains --merged --no-merged --sort= --points-at=
bisect|start bad good new old skip reset visualize view log replay run terms help
notes|list add copy append edit show merge remove prune get-ref
remote|add rename remove set-head set-branches get-url set-url show prune update --verbose
sparse-checkout|list init set add reapply disable
stash|list show drop pop apply branch push save clear create store
submodule|add status init deinit update set-branch set-url summary foreach sync absorbgitdirs
worktree|add list lock move prune remove repair unlock
'

_mini_git_query()
{
    # Read-only queries with bin/git_args from the caller; no network access.
    if command -v timeout >/dev/null 2>&1; then
        GIT_OPTIONAL_LOCKS=0 timeout -k 1 2 "$bin" "${git_args[@]}" "$@" 2>/dev/null
    else
        GIT_OPTIONAL_LOCKS=0 "$bin" "${git_args[@]}" "$@" 2>/dev/null
    fi
}

_mini_git_completion()
{
    local line="${COMP_LINE:0:COMP_POINT}" current bin word prev command= subcommand= mode= words= candidate trim= prefix= dashdash= remote= staged= i
    local -a parts git_args=() args=()
    COMPREPLY=()
    # Split on blanks only: ':' in push refspecs and '=' in options also split COMP_WORDS.
    read -r -a parts <<< "$line"
    if [ ${#parts[@]} -eq 0 ] || [[ "$line" == *[[:space:]] ]]; then parts+=(''); fi
    current="${parts[${#parts[@]}-1]}"
    prev="${parts[${#parts[@]}-2]}"
    bin="${parts[0]:-git}"
    [[ "$bin" != '~/'* ]] || bin="$HOME/${bin#'~/'}"

    for ((i=1; i<${#parts[@]}-1; i++)); do
        word="${parts[i]}"
        if [ -z "$command" ]; then
            case "$word" in
                # Queries follow the repository selected on the command line.
                -C|--git-dir|--work-tree) git_args+=("$word" "${parts[i+1]}"); i=$((i + 1)) ;;
                --git-dir=*|--work-tree=*) git_args+=("$word") ;;
                -c|--namespace|--config-env|--super-prefix) i=$((i + 1)) ;;
                -*) ;;
                *) command="$word" ;;
            esac
            continue
        fi
        [ -z "$dashdash" ] || continue
        case "$command $word" in
            *' --') dashdash=yes ;;
            # Options whose value is the next word; skip it when counting arguments.
            'commit -m'|'commit -F'|'commit -c'|'commit -C'|'commit --author'|'commit --date'|'commit --fixup'|'commit --squash'|'commit -t'|\
            'tag -m'|'tag -F'|'tag -u'|'merge -m'|'merge -F'|'merge -s'|'merge -X'|'pull -s'|'pull -X'|\
            'rebase -s'|'rebase -X'|'rebase -x'|'rebase --onto'|'rebase --exec'|'clone -b'|'clone -o'|'clone --depth'|'clone --branch'|\
            'checkout -b'|'checkout -B'|'checkout --orphan'|'switch -c'|'switch -C'|'switch --orphan'|'branch -u'|\
            'fetch --depth'|'pull --depth'|'push -o'|'push --push-option'|'restore -s'|'restore --source'|\
            'log -n'|'stash -m'|'remote -t'|'remote -m'|'worktree -b'|'worktree -B'|'grep -e'|'grep -f'|'config -f'|'config --file'|'format-patch -o')
                i=$((i + 1)) ;;
            'restore --staged'|'restore -S') staged=yes ;;
            *' -'*) ;;
            *) args+=("$word") ;;
        esac
    done

    # Values of --option=value use the option's mode and keep the prefix.
    if [[ "$current" == --*=* ]]; then
        prev="${current%%=*}"; prefix="$prev="; current="${current#*=}"
    fi
    subcommand="${args[0]}"

    if [ -z "$command" ]; then
        case "$prev" in
            -C|--git-dir|--work-tree) mode=directory ;;
            -c|--namespace|--config-env) return ;;
            *)
                case "$current" in
                    -*) words='-C -c -p -P --paginate --no-pager --git-dir= --work-tree= --namespace= --bare --exec-path --html-path --man-path --info-path --no-replace-objects --literal-pathspecs --version --help' ;;
                    *) words="$_MINI_GIT_COMMANDS $(_mini_git_query config --get-regexp '^alias\.' | while read -r word candidate; do printf '%s\n' "${word#alias.}"; done)" ;;
                esac ;;
        esac
    elif [[ "$current" == -* && -z "$dashdash" && -z "$prefix" ]]; then
        case "$current" in
            --*=*) ;;
            *)
                # The helper misses some options (e.g. diff --cached); add the fallback list too.
                [[ "$_MINI_GIT_HELPER" != *" $command "* ]] || words="$(_mini_git_query "$command" --git-completion-helper)"
                words="$words $(printf '%s\n' "$_MINI_GIT_OPTIONS" | while IFS='|' read -r word candidate; do [ "$word" != "$command" ] || printf '%s\n' "$candidate"; done)" ;;
        esac
    else
        case "$command $prev" in
            *' --output-directory'|*' --separate-git-dir'|*' --template'|'format-patch -o') mode=directory ;;
            *' -F'|*' --file'|'grep -f'|'config -f'|*' --pathspec-from-file') mode=path ;;
            'commit -c'|'commit -C'|'restore -s'|*' --source'|*' --onto'|*' --fixup'|*' --squash'|*' --reuse-message'|*' --reedit-message'|\
            *' --contains'|*' --no-contains'|*' --merged'|*' --no-merged'|*' --points-at') mode=ref ;;
            'branch -u'|'branch --set-upstream-to') mode=remote-branch ;;
            'merge -s'|'pull -s'|'rebase -s'|*' --strategy') words='ort recursive resolve octopus ours subtree' ;;
            'merge -X'|'pull -X'|'rebase -X'|'cherry-pick -X'|'revert -X'|*' --strategy-option')
                words='ours theirs patience diff-algorithm= ignore-space-change ignore-all-space renormalize no-renames subtree=' ;;
            *' --cleanup') words='strip whitespace verbatim scissors default' ;;
            *' --untracked-files') words='no normal all' ;;
            # Free text, numbers or new names: nothing to suggest.
            'commit -m'|'tag -m'|'merge -m'|'stash -m'|'remote -m'|*' --message'|'commit -t'|'tag -u'|'remote -t'|\
            'checkout -b'|'checkout -B'|'switch -c'|'switch -C'|'worktree -b'|'worktree -B'|'clone -b'|'clone -o'|*' --orphan'|*' --branch'|\
            'push -o'|*' --push-option'|'log -n'|*' --max-count'|*' --depth'|*' --date'|*' --author'|*' --since'|*' --until'|\
            *' --grep'|*' --format'|*' --pretty'|*' --trailer'|*' --sort'|*' --match'|*' --abbrev'|*' --unified'|'grep -e'|'rebase -x'|*' --exec')
                return ;;
            *)
                # Unknown --option=value: leave it to the default completion.
                [ -z "$prefix" ] || return ;;
        esac
        [ -n "$mode$words" ] || case "$command" in
            help) words="$_MINI_GIT_COMMANDS" ;;
            add) mode=changed ;;
            restore) if [ -n "$staged" ]; then mode=staged; else mode=modified; fi ;;
            checkout)
                if [ -n "$dashdash" ]; then mode=modified; else mode=ref-guess; fi ;;
            switch) mode=ref-guess ;;
            branch)
                case " ${parts[*]} " in
                    *' -d '*|*' -D '*|*' --delete '*|*' -m '*|*' -M '*|*' --move '*|*' -c '*|*' --copy '*) mode=branch ;;
                    *' -r '*|*' --remotes '*) mode=remote-branch ;;
                    *) mode=ref ;;
                esac ;;
            tag)
                case " ${parts[*]} " in
                    *' -d '*|*' --delete '*|*' -v '*|*' --verify '*) mode=tag ;;
                    *) [ ${#args[@]} -eq 0 ] || mode=ref ;;
                esac ;;
            reset)
                if [ -n "$dashdash" ]; then mode=staged; else mode=ref; fi ;;
            log|show|diff|shortlog|whatchanged|range-diff|format-patch|cherry-pick|revert|merge|rebase|describe|cherry|reflog|show-branch|rev-parse|rev-list|archive|ls-tree)
                if [ -n "$dashdash" ]; then mode=path; else mode=ref; fi ;;
            push|fetch|pull|ls-remote)
                if [ ${#args[@]} -eq 0 ]; then mode=remote
                elif [ "$command" = push ]; then
                    # src:dst completes the destination from the remote's tracked branches.
                    if [[ "$current" == *:* ]]; then remote="${args[0]}"; mode=remote-of; else mode=branch; fi
                else remote="${args[0]}"; mode=remote-of
                fi ;;
            remote)
                case "${#args[@]}:$subcommand" in
                    0:) words="$(printf '%s\n' "$_MINI_GIT_OPTIONS" | while IFS='|' read -r word candidate; do [ "$word" != remote ] || printf '%s\n' "$candidate"; done)" ;;
                    1:rename|1:remove|1:rm|1:set-head|1:set-branches|1:get-url|1:set-url|1:show|1:prune|*:update) mode=remote ;;
                esac ;;
            stash)
                case "${#args[@]}:$subcommand" in
                    0:) words='list show drop pop apply branch push save clear create store' ;;
                    1:show|1:drop|1:pop|1:apply|2:branch) mode=stash ;;
                    *:push|*:save) [ -z "$dashdash" ] || mode=changed ;;
                esac ;;
            bisect|notes|sparse-checkout|submodule|worktree)
                if [ ${#args[@]} -eq 0 ]; then
                    words="$(printf '%s\n' "$_MINI_GIT_OPTIONS" | while IFS='|' read -r word candidate; do [ "$word" != "$command" ] || printf '%s\n' "$candidate"; done)"
                else
                    case "$command $subcommand" in
                        'bisect start'|'bisect bad'|'bisect good'|'bisect new'|'bisect old'|'bisect skip'|'bisect reset') mode=ref ;;
                        'worktree add') [ ${#args[@]} -eq 1 ] && mode=directory || mode=ref ;;
                        'worktree '*|'submodule '*) mode=path ;;
                    esac
                fi ;;
            config)
                # The first name, or the name after get/set/unset/--get/--unset...
                case "$prev" in
                    config|get|set|unset|--get|--get-all|--get-regexp|--unset|--unset-all|--replace-all|--add) mode=config-key ;;
                    -*) [ ${#args[@]} -gt 0 ] || mode=config-key ;;
                esac ;;
        esac
    fi

    case "$mode" in
        ref|ref-guess)
            # A..B and A...B complete the part after the dots.
            if [[ "$current" == *..* ]]; then prefix="$prefix${current%..*}.."; current="${current##*..}"; fi
            words="HEAD $(_mini_git_query for-each-ref --format='%(refname:short)' refs/heads refs/tags refs/remotes)"
            # checkout/switch create a local branch from a unique remote branch name.
            if [ "$mode" = ref-guess ]; then
                words="$words $(_mini_git_query for-each-ref --format='%(refname:strip=3)' refs/remotes | while read -r word; do [ "$word" = HEAD ] || printf '%s\n' "$word"; done)"
            fi ;;
        branch) words="$(_mini_git_query for-each-ref --format='%(refname:short)' refs/heads)" ;;
        tag) words="$(_mini_git_query for-each-ref --format='%(refname:short)' refs/tags)" ;;
        remote-branch) words="$(_mini_git_query for-each-ref --format='%(refname:short)' refs/remotes)" ;;
        remote) words="$(_mini_git_query remote)" ;;
        remote-of)
            # Branch names from local remote-tracking refs; never contacts the remote.
            if [[ "$current" == *:* ]]; then prefix="$prefix${current%%:*}:"; current="${current#*:}"; fi
            [[ "$current" == +* ]] && { prefix="$prefix+"; current="${current#+}"; }
            words="$(_mini_git_query for-each-ref --format='%(refname)' "refs/remotes/$remote" | while read -r word; do word="${word#refs/remotes/"$remote"/}"; [ "$word" = HEAD ] || printf '%s\n' "$word"; done)" ;;
        stash) words="$(_mini_git_query stash list --format=%gd)" ;;
        config-key)
            words="user.name user.email core.editor core.autocrlf core.filemode core.quotepath init.defaultBranch pull.rebase push.default credential.helper http.proxy https.proxy http.sslVerify color.ui merge.tool diff.tool alias. $(_mini_git_query config --name-only --list)" ;;
        changed|modified|staged)
            # Files git knows are changed (null-separated, so no quoting issues).
            word="${COMP_WORDS[COMP_CWORD]}"; word="${word//\\/}"; word="${word#[\"\']}"
            if [ "$mode" = staged ]; then
                set -- diff --cached --name-only --relative -z
            elif [ "$mode" = modified ]; then
                set -- ls-files -z --modified --deleted
            else
                set -- ls-files -z --exclude-standard --modified --others --deleted --directory --no-empty-directory
            fi
            while IFS= read -r -d '' candidate; do
                [[ "$candidate" != "$word"* ]] || COMPREPLY+=("$candidate")
            done < <(_mini_git_query "$@")
            compopt -o filenames 2>/dev/null || true
            # Outside a repository, or nothing changed: fall back to local paths.
            [ ${#COMPREPLY[@]} -eq 0 ] && mode=path || return ;;
    esac
    case "$mode" in
        directory)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "${COMP_WORDS[COMP_CWORD]}")
            compopt -o filenames 2>/dev/null || true; return ;;
        path)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "${COMP_WORDS[COMP_CWORD]}")
            compopt -o filenames 2>/dev/null || true; return ;;
    esac

    # Readline replaces only the text after the last ':' or '=' (COMP_WORDBREAKS).
    word="$prefix$current"
    if [[ "$COMP_WORDBREAKS" == *[:=]* && "$word" == *[:=]* ]]; then trim="${word%"${word##*[:=]}"}"; fi
    for candidate in $words; do
        [[ "$candidate" == "$current"* ]] || continue
        candidate="$prefix$candidate"
        COMPREPLY+=("${candidate#"$trim"}")
    done
    # Options such as --format= expect a value right after '='.
    if [ ${#COMPREPLY[@]} -eq 1 ] && [[ "${COMPREPLY[0]}" == *= || "${COMPREPLY[0]}" == *. ]]; then
        compopt -o nospace 2>/dev/null || true
    fi
}
complete -o bashdefault -o default -F _mini_git_completion git
