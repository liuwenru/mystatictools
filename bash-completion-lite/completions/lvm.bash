# LVM2: lvm and its pv*/vg*/lv* commands.
# Option names, value-taking options, enumerated values (y|n, --type ...) are
# parsed from `<command> --longhelp` of the local LVM. PV/VG/LV names come from
# the read-only report commands pvs/vgs/lvs; candidate disks come from /sys.
# Every per-command file (lvcreate.bash, vgs.bash, ...) is a symlink to this one,
# so on-demand loaders find it under any LVM command name.

_MINI_LVM_TOOLS='lvchange lvconvert lvcreate lvdisplay lvextend lvmconfig lvmdevices lvmdiskscan lvreduce lvremove lvrename lvresize lvs lvscan pvchange pvck pvcreate pvdisplay pvmove pvremove pvresize pvs pvscan vgcfgbackup vgcfgrestore vgchange vgck vgconvert vgcreate vgdisplay vgexport vgextend vgimport vgimportclone vgimportdevices vgmerge vgmknodes vgreduce vgremove vgrename vgs vgscan vgsplit'

# Run an LVM command quietly, with a time limit when timeout(1) is available.
# $_mini_lvm_bin is set by the completion function: the typed `lvm`, or empty
# to run the tool name directly.
_mini_lvm_run()
{
    local -a command=("$@")
    [ -z "$_mini_lvm_bin" ] || command=("$_mini_lvm_bin" "$@")
    if command -v timeout >/dev/null 2>&1; then
        LVM_SUPPRESS_FD_WARNINGS=1 timeout -k 1 2 "${command[@]}"
    else
        LVM_SUPPRESS_FD_WARNINGS=1 "${command[@]}"
    fi
}

_mini_lvm_vgs() { _mini_lvm_run vgs --noheadings -o vg_name 2>/dev/null | awk 'NF {print $1}'; }
_mini_lvm_pvs() { _mini_lvm_run pvs --noheadings -o pv_name 2>/dev/null | awk 'NF {print $1}'; }
_mini_lvm_lvs()
{
    # Without a VG argument print vg/lv; with one print bare LV names of that VG.
    if [ -n "$1" ]; then
        _mini_lvm_run lvs --noheadings -o lv_name "$1" 2>/dev/null | awk 'NF {print $1}'
    else
        _mini_lvm_run lvs --noheadings -o vg_name,lv_name 2>/dev/null | awk 'NF == 2 {print $1 "/" $2}'
    fi
}

# Block devices that can become PVs: skip empty/read-only devices, disks that
# have partitions, devices already used by dm/LVM (holders), mounted or swap
# devices, and LVM's own LVs.
_mini_lvm_disks()
{
    local path name uuid holder entry device used=' ' source
    while read -r source _; do
        case "$source" in /dev/*) used="$used$source $(readlink -f "$source" 2>/dev/null) " ;; esac
    done < <(cat /proc/mounts /proc/swaps 2>/dev/null)
    for path in /sys/class/block/*; do
        [ -e "$path" ] || continue
        name="${path##*/}"
        case "$name" in ram*|zram*) continue ;; esac
        [ "$(cat "$path/size" 2>/dev/null)" != 0 ] || continue
        [ "$(cat "$path/ro" 2>/dev/null)" != 1 ] || continue
        for holder in "$path"/holders/*; do [ ! -e "$holder" ] || continue 2; done
        for entry in "$path"/"$name"*; do [ ! -e "$entry/partition" ] || continue 2; done
        if [ -d "$path/dm" ]; then
            uuid="$(cat "$path/dm/uuid" 2>/dev/null)"
            case "$uuid" in LVM-*) continue ;; esac
            [[ "$used" != *" /dev/$name "* ]] || continue
            name="$(cat "$path/dm/name" 2>/dev/null)"
            device="/dev/mapper/$name"
        else
            device="/dev/$name"
        fi
        [[ "$used" != *" $device "* ]] || continue
        printf '%s\n' "$device"
    done
}

# Parse --longhelp into lines: "<option> <flag|value> <type> <enum values...>".
# A bracketed "[ -x|--opt Arg ]" line is authoritative; in usage lines an option
# followed by VG/LV/PV/Tag counts as taking a value only when another option
# follows, because a trailing VG/LV/PV is the positional argument.
_mini_lvm_parse_help()
{
    awk -v cmd="$1" '
    function add(spec, kind, arg,    n, names, j, k, vals, v) {
        n = split(spec, names, "|")
        for (j = 1; j <= n; j++) {
            if (names[j] !~ /^--?[A-Za-z]/) continue
            if (!(names[j] in seen)) { seen[names[j]] = 1; order[++count] = names[j] }
            if (kind == "value") { val[names[j]] = 1; if (!(names[j] in type) || type[names[j]] ~ /_new$/) type[names[j]] = arg }
            if (arg ~ /\|/ || arg ~ /^[a-z][a-z0-9_-]*$/) {
                k = split(arg, vals, "|")
                for (v = 1; v <= k; v++)
                    if ((vals[v] ~ /^[a-z][a-z0-9_-]*$/ || vals[v] ~ /^[A-Za-z]$/) && index(" " enums[names[j]] " ", " " vals[v] " ") == 0)
                        enums[names[j]] = enums[names[j]] " " vals[v]
            }
        }
    }
    {
        bracket = ($0 ~ /^[ \t]*\[/)
        usage = (index($0, "  " cmd " ") == 1)
        if (!bracket && !usage) next
        n = split($0, t, /[ \t]+/)
        for (i = 1; i <= n; i++) {
            if (t[i] !~ /^--?[A-Za-z]/) continue
            arg = (i < n) ? t[i + 1] : ""
            if (bracket) kind = (arg == "]" || arg == "") ? "flag" : "value"
            else if (arg == "" || arg ~ /^-/) kind = "flag"
            else if (arg ~ /^(VG|LV|PV|Tag)/) kind = (i + 2 <= n && t[i + 2] ~ /^-/) ? "value" : "flag"
            else kind = "value"
            add(t[i], kind, (kind == "value") ? arg : "")
        }
    }
    END {
        for (i = 1; i <= count; i++) {
            o = order[i]
            printf "%s %s %s%s\n", o, (o in val) ? "value" : "flag", (o in type) ? type[o] : "-", enums[o]
        }
    }'
}

_mini_lvm_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous= option= word i start=1 tool help line
    local name kind arg enum words= options= value_options=' ' type= skip=no snapshot=no thin=no
    local _mini_lvm_bin=
    local -a positionals=()
    COMPREPLY=()

    tool="${COMP_WORDS[0]##*/}"
    if [ "$tool" = lvm ]; then
        _mini_lvm_bin="${COMP_WORDS[0]}"
        if ((COMP_CWORD == 1)); then
            COMPREPLY=( $(compgen -W "$_MINI_LVM_TOOLS config devtypes dumpconfig formats fullreport help lastlog lvpoll segtypes systemid tags version" -- "$current") )
            return
        fi
        tool="${COMP_WORDS[1]}"
        start=2
        if [ "$tool" = help ]; then
            ((COMP_CWORD == 2)) && COMPREPLY=( $(compgen -W "$_MINI_LVM_TOOLS" -- "$current") )
            return
        fi
    elif command -v lvm >/dev/null 2>&1; then
        _mini_lvm_bin=lvm
    fi
    ((COMP_CWORD > start)) && previous="${COMP_WORDS[COMP_CWORD-1]}"

    help="$(_mini_lvm_run "$tool" --longhelp 2>/dev/null | _mini_lvm_parse_help "$tool")"
    [ -n "$help" ] || help="$(_mini_lvm_run "$tool" --help 2>/dev/null | _mini_lvm_parse_help "$tool")"
    while read -r name kind arg enum; do
        [ -n "$name" ] || continue
        options="$options $name"
        [ "$kind" != value ] || value_options="$value_options$name "
    done <<< "$help"
    # Minimal fallback when the tool cannot print its help.
    [ -n "$options" ] || options='-h --help -v --verbose -y --yes -t --test --version'

    # Option value: "--opt value", "--opt=value" (Bash splits at '=').
    if [ "$previous" = = ] && ((COMP_CWORD - 2 >= start)); then
        option="${COMP_WORDS[COMP_CWORD-2]}"
    elif [[ "$value_options" == *" $previous "* ]]; then
        option="$previous"
    fi
    if [ -n "$option" ]; then
        line="$(awk -v o="$option" '$1 == o' <<< "$help")"
        read -r name kind arg enum <<< "$line"
        case "$option" in
            -f|--file)
                compopt -o filenames 2>/dev/null || true
                COMPREPLY=( $(compgen -f -- "$current") )
                return ;;
            -o|--options|-O|--sort)
                case "$tool" in
                    pvs|vgs|lvs|fullreport)
                        # Field lists are comma separated; complete the last item.
                        local prefix=
                        [[ "$current" != *,* ]] || prefix="${current%,*},"
                        word="${current##*,}"
                        [[ "$word" != [+-]* ]] || { prefix="$prefix${word:0:1}"; word="${word:1}"; }
                        words="$(_mini_lvm_run "$tool" -o help 2>&1 | awk '$2 == "-" {print $1}')"
                        COMPREPLY=( $(compgen -P "$prefix" -W "$words" -- "$word") )
                        compopt -o nospace 2>/dev/null || true
                        return ;;
                esac ;;
            --units) enum='h H b B s S k K m M g G t T p P e E r R' ;;
            --devices) arg=PV_disk ;;
        esac
        if [ -n "$enum" ]; then
            words="$enum"
        else
            case "$arg" in
                VG|VG\|*) words="$(_mini_lvm_vgs)" ;;
                LV|LV\|*) words="$(_mini_lvm_lvs)" ;;
                PV_disk) words="$(_mini_lvm_pvs; _mini_lvm_disks)" ;;
                PV|PV\|*) words="$(_mini_lvm_pvs)" ;;
            esac
        fi
        COMPREPLY=( $(compgen -W "$words" -- "$current") )
        return
    fi

    if [[ "$current" == -* ]]; then
        COMPREPLY=( $(compgen -W "$options" -- "$current") )
        return
    fi

    # Collect positional arguments, skipping options and their values.
    for ((i=start; i<COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        if [ "$skip" = yes ]; then skip=no; continue; fi
        case "$word" in
            =) skip=yes; continue ;;
            -s|--snapshot) snapshot=yes ;;
            -T|--thin) thin=yes ;;
        esac
        if [[ "$word" == -* ]]; then
            [[ "$value_options" != *" $word "* ]] || skip=yes
            continue
        fi
        positionals+=("$word")
    done

    # Argument types by position (1-based); "+" means the rest of the arguments.
    case "$tool:${#positionals[@]}" in
        pvs:*|pvdisplay:*|pvchange:*|pvck:*|pvremove:*|pvresize:*|pvmove:*) type=pv ;;
        pvcreate:*|vgimportclone:*) type=disk ;;
        vgcreate:0|vgrename:1|vgsplit:1) type= ;;
        vgcreate:*|vgextend:[1-9]*) type=disk ;;
        vgreduce:[1-9]*|vgsplit:[2-9]*) type=pv ;;
        vgcfgrestore:0|vgmerge:[01]|vgsplit:0|vgextend:0|vgreduce:0|vgrename:0) type=vg ;;
        vgs:*|vgdisplay:*|vgchange:*|vgck:*|vgremove:*|vgexport:*|vgimport:*|vgcfgbackup:*|vgmknodes:*|vgconvert:*|vgimportdevices:*) type=vg ;;
        lvs:*|lvdisplay:*) type=vglv ;;
        lvchange:*|lvremove:*|lvconvert:0|lvextend:0|lvreduce:0|lvresize:0) type=lv ;;
        lvconvert:*|lvextend:*|lvreduce:*|lvresize:*) type=pv ;;
        lvrename:0) type=vglv ;;
        lvrename:1) [[ "${positionals[0]}" == */* ]] || type=lvinvg ;;
        lvcreate:0)
            if [ "$snapshot" = yes ]; then type=lv
            elif [ "$thin" = yes ]; then type=vglv
            else type=vg
            fi ;;
        lvcreate:*) [ "$snapshot" = yes ] || type=pv ;;
    esac
    case "$type" in
        pv) words="$(_mini_lvm_pvs)" ;;
        disk) words="$(_mini_lvm_disks)"
              # Paths other than the listed disks, e.g. /dev/disk/by-id/...
              [[ "$current" != */* ]] || words="$words $(compgen -f -- "$current")"
              compopt -o filenames 2>/dev/null || true ;;
        vg) words="$(_mini_lvm_vgs)" ;;
        lv) words="$(_mini_lvm_lvs)" ;;
        vglv) words="$(_mini_lvm_vgs; _mini_lvm_lvs)" ;;
        lvinvg) words="$(_mini_lvm_lvs "${positionals[0]}")" ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
}

complete -F _mini_lvm_completion lvm $_MINI_LVM_TOOLS
