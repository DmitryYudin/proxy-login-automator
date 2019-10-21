set -eu -o pipefail

usage()
{
	cat <<-'EOF'
run_proxy [opt]
Options:
    -h|--help    - Print help
    -p|--proxy   - Proxy settings. Default: 'proxy.default.txt'
    -t|--test    - Test
    -f|--force   - Restart running instance
    -k|--kill    - Kill running instance

EOF
}

proxy_test()
{
	export ALL_PROXY=localhost:$local_port
	curl -k -I --location "http://google.com"
	curl -k -I --location "https://google.com"
}
proxy_kill()
{
	local NODE_PID=$(cat "$PID_FILE" 2>/dev/null | head -n1)
	if [ -z "$NODE_PID" ] ; then
		echo "error: no PID file found" 2>&1 && return 1		
	else
		kill $NODE_PID &>/dev/null
		rm -f "$PID_FILE"
	fi
}

read_proxy_prms()
{
	local have_proxy_file=
	while [ "$#" -gt 0 ]; do
		case $1 in -p|--proxy) 
			echo "reading '$(pwd)/$2'"
			source "$2"; shift
			have_proxy_file=true
		esac
		shift
	done

	if [ -z "$have_proxy_file" ]; then
		. "$DIR/proxy.default.txt"
	fi
	[ -z ${username-} ] && username=$USERNAME
}

entrypoint()
{
	local DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	local PID_FILE="$DIR/proxy-login-automator.pid"
	local LOG_FILE="$DIR/proxy-login-automator.log"

	read_proxy_prms "$@"

	while [ "$#" -gt 0 ]; do
		case $1 in
			-h|--help)
				usage
				return
			;;
			-t|--test)
				proxy_test
				return
			;;
			-k|--kill)
				if ! proxy_kill; then
					echo "error: can't kill, the proxy might be already dead" 2>&1
				fi
				return
			;;
			-f|--force) 
				if proxy_kill; then
					echo "proxy instance succesfully destroyed"
				fi
			;;
			-p|--proxy)  # skip
				shift
			;;
			*) echo "error: unrecognized option $1" 1>&2; return 1;;
		esac
		shift
	done

	local NODE_PID=$(cat "$PID_FILE" 2>/dev/null | head -n1)
	if [ -n "$NODE_PID" -a -e /proc/$NODE_PID ]; then
		echo "error: already running with pid $NODE_PID, use '--force' to restart"
		return 1
	else
		rm -f "$PID_FILE"
	fi

	if ! command -v node &>/dev/null; then
		echo "error: NodeJS not installed (https://nodejs.org)" 1>&2
	return 1
	fi

	if netstat -n -q -p tcp -o | grep $local_port > /dev/null; then
		echo "error: local port $local_port is already in use, can't run" 1>&2
		return 1
	fi	

	echo "Enter password for '$username' user:"
	read -s PASSWORD

	echo "Starting: $local_host:$local_port -> $username:***@$remote_host:$remote_port"
	local script="$DIR/proxy-login-automator.js"
	[ -n ${MSYSTEM:-} ] && script="$(cygpath -m "$script")" 
	node "$script" \
	    -local_host $local_host \
	    -local_port $local_port \
	    -remote_host $remote_host \
	    -remote_port $remote_port \
	    -usr $username \
		-pwd $PASSWORD \
	    -as_pac_server $as_pac_server \
	</dev/null \
	1>"$LOG_FILE" 2>&1 &
	NODE_PID=$!

	echo $NODE_PID > "$PID_FILE"
	cat /proc/$NODE_PID/winpid >> "$PID_FILE" || true

	disown $NODE_PID
	echo "Started in a background"
}

entrypoint "$@"
