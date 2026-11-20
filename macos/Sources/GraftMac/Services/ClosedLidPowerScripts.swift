import Foundation

/// A single machine-wide lease. The LaunchDaemon, not Graft, owns the power
/// change and the on-disk record needed to undo it after a crash or reboot.
enum ClosedLidPowerScripts {
    static let label = "com.itsasheruwu.graft.closed-lid"
    static let directory = "/private/var/db/\(label)"
    static let statusPath = "\(directory)/status"
    static let journalPath = "\(directory)/restore"
    static let maximumDuration: TimeInterval = 4 * 60 * 60

    static func releaseMarker(for token: UUID) -> String {
        "/private/tmp/\(label)-\(token.uuidString)"
    }

    static func installArguments(token: UUID, owner: pid_t, deadline: Int64) throws -> [String] {
        let pid = String(owner)
        let epoch = String(deadline)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/env", "-i", "/bin/sh", "-c", common + "\n" + watch,
                label, token.uuidString, pid, epoch,
            ],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 3,
            "ProcessType": "Background",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return [common + "\n" + install, token.uuidString, pid, epoch, String(decoding: data, as: UTF8.self)]
    }

    // The AppleScript receives only fixed script source and typed arguments.
    // Each argument is quoted separately before passing it to the root shell.
    static let authorization = """
    on run argv
        set commandLine to "/usr/bin/env -i /bin/sh -c " & (quoted form of (item 1 of argv)) & " graft-closed-lid"
        repeat with i from 2 to count of argv
            set commandLine to commandLine & " " & (quoted form of (item i of argv))
        end repeat
        do shell script commandLine with prompt "Allow Graft to keep this MacBook awake with the lid closed for the rest of this session?" with administrator privileges
    end run
    """

    private static let common = #"""
    set -u
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C TZ=UTC
    umask 022
    label='\#(label)'
    base='\#(directory)'
    journal='\#(journalPath)'
    service="system/$label"
    plist="/Library/LaunchDaemons/$label.plist"
    pending="$base/pending"
    status='\#(statusPath)'
    token="$1"
    owner_pid="$2"
    deadline="$3"
    release="/private/tmp/$label-$token"

    sleep_disabled() {
        /usr/sbin/ioreg -rad1 -c IOPMrootDomain |
            /usr/bin/plutil -extract 0.SleepDisabled raw -expect bool - 2>/dev/null
    }

    power_state() {
        if ! snapshot="$(/usr/bin/pmset -g batt)"; then
            printf '%s\n' power
            return
        fi
        printf '%s\n' "$snapshot" | /usr/bin/awk '
            NR == 1 { supported = ($0 ~ /^Now drawing from \047(AC|Battery) Power\047$/) }
            /InternalBattery/ && match($0, /[0-9]+%/) {
                battery = substr($0, RSTART, RLENGTH - 1)
            }
            END {
                if (!supported || battery == "" || (battery + 0) > 100) print "power"
                else if ((battery + 0) <= 10) print "battery"
                else print "ready"
            }'
    }

    owner_identity() {
        /bin/ps -p "$owner_pid" -o uid=,lstart=
    }

    marker_identity() {
        /usr/bin/stat -f '%HT:%u:%Lp:%i' "$release" 2>/dev/null
    }

    lock_lease() {
        exec 9>"$base/lock"
        /usr/bin/lockf -s -t "$1" 9
    }

    publish() {
        printf '%s\n%s\n' "$token" "$1" > "$status.new" &&
            /bin/mv -f "$status.new" "$status"
    }
    """#

    private static let install = #"""
    fail() { printf 'GRAFT_%s\n' "$1" >&2; exit 1; }

    if [ "$(/usr/bin/id -u)" != 0 ]; then fail authorization; fi
    if ! /bin/mkdir -m 0755 "$base" 2>/dev/null; then
        [ "$(/usr/bin/stat -f '%HT:%u:%Lp' "$base")" = 'Directory:0:755' ] || fail setup
    fi
    lock_lease 0 || fail busy
    [ ! -e "$journal" ] || fail restoring
    case "$token" in
        ""|*[!A-F0-9-]*) fail setup ;;
    esac
    case "$owner_pid:$deadline" in
        :*|*:|*[!0-9:]*) fail setup ;;
    esac
    remaining=$((deadline - $(/bin/date +%s)))
    [ "$remaining" -gt 0 ] && [ "$remaining" -le \#(Int(maximumDuration)) ] || fail expired
    power="$(power_state)"
    [ "$power" = ready ] || fail "$power"
    [ "$(sleep_disabled)" = false ] || fail settings

    identity="$(owner_identity)" || fail cancelled
    owner_uid="$(printf '%s\n' "$identity" | /usr/bin/awk '{ print $1 }')"
    marker="$(marker_identity)" || fail cancelled
    case "$marker" in
        "Directory:$owner_uid:700:"*) ;;
        *) fail cancelled ;;
    esac

    # A prior successfully completed job may remain loaded until this start.
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
        /bin/launchctl bootout "$service" || fail setup
    fi

    # Put the plist on disk before enabling the job. A crash before bootstrap
    # cannot disable sleep, and a job launched at boot still checks its owner.
    temp="$(/usr/bin/mktemp "/Library/LaunchDaemons/.$label.XXXXXXXX")" || fail setup
    trap '/bin/rm -f "$temp"' EXIT
    printf '%s\n' "$4" > "$temp" && /bin/chmod 0644 "$temp" &&
        /usr/bin/plutil -lint "$temp" >/dev/null && /bin/mv -f "$temp" "$plist" || fail setup
    printf '%s\n%s\n' "$identity" "$marker" > "$pending" || fail setup
    publish waiting || fail setup
    if ! /bin/launchctl bootstrap system "$plist"; then
        /bin/rm -f "$pending" "$plist"
        fail setup
    fi
    """#

    private static let watch = #"""
    lock_lease 15 || exit 1

    finish() {
        # Keep the restore record through faults, including an interrupted pmset.
        # launchd restarts on failure and the reboot path uses this same record.
        trap '' TERM INT HUP
        if [ -f "$journal" ]; then
            publish restoring || true
            if ! /usr/bin/pmset -a disablesleep 0; then
                publish restore-failed || true
                exit 1
            fi
            for attempt in 1 2 3 4 5; do
                [ "$(sleep_disabled)" = false ] && break
                /bin/sleep 1
            done
            if [ "$(sleep_disabled)" != false ]; then
                publish restore-failed || true
                exit 1
            fi
            /bin/rm -f "$journal" || exit 1
        fi
        publish "$1" || true
        /bin/rm -f "$pending" "$plist" || exit 1
        exit 0
    }

    # A new worker with a restore record only restores. It never resumes the
    # override after power loss, reboot, or a watchdog failure.
    if [ -f "$journal" ]; then finish stopped; fi
    [ -f "$pending" ] || finish cancelled
    {
        IFS= read -r expected_owner &&
        IFS= read -r expected_marker
    } < "$pending" || finish setup

    owner_is_current() {
        [ "$(owner_identity)" = "$expected_owner" ] &&
            [ "$(marker_identity)" = "$expected_marker" ]
    }

    remaining=$((deadline - $(/bin/date +%s)))
    [ "$remaining" -gt 0 ] && [ "$remaining" -le \#(Int(maximumDuration)) ] || finish expired
    owner_is_current || finish cancelled
    power="$(power_state)"
    [ "$power" = ready ] || finish "$power"
    [ "$(sleep_disabled)" = false ] || finish settings

    trap 'finish stopped' TERM INT HUP
    /bin/mv -f "$pending" "$journal" || finish setup
    /bin/sync || finish setup
    owner_is_current || finish cancelled
    power="$(power_state)"
    [ "$power" = ready ] || finish "$power"
    /usr/bin/pmset -a disablesleep 1 || finish setup
    for attempt in 1 2 3 4 5; do
        [ "$(sleep_disabled)" = true ] && break
        /bin/sleep 1
    done
    [ "$(sleep_disabled)" = true ] || finish setup
    publish active || finish setup

    # The relative timer also bounds the override if the wall clock goes back.
    # launchd cleans up this child process when the worker exits.
    /bin/sleep "$remaining" 9>&- &
    timer="$!"
    while [ "$(/bin/date +%s)" -lt "$deadline" ] && kill -0 "$timer" 2>/dev/null; do
        owner_is_current || finish stopped
        power="$(power_state)"
        [ "$power" = ready ] || finish "$power"
        [ "$(sleep_disabled)" = true ] || finish settings
        /bin/sleep 2
    done
    finish expired
    """#
}
