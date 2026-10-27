# Sourced by the other scripts: locates the current Connect IQ SDK and the
# developer key. Not meant to be run on its own.

case "$(uname -s)" in
    Darwin) CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ" ;;
    *)      CIQ_HOME="$HOME/.Garmin/ConnectIQ" ;;
esac

if [ ! -f "$CIQ_HOME/current-sdk.cfg" ]; then
    echo "No Connect IQ SDK selected. Install one with the SDK Manager (see README.md)." >&2
    exit 1
fi
SDK="$(tr -d '\n' < "$CIQ_HOME/current-sdk.cfg")"
SDK="${SDK%/}"

if [ ! -d "$CIQ_HOME/Devices/fenix8pro47mm" ]; then
    echo "Device files for fenix8pro47mm are missing in $CIQ_HOME/Devices." >&2
    echo "Download them with the SDK Manager or: connect-iq-sdk-manager device download --manifest apps/field/manifest.xml" >&2
fi

KEY="${CIQ_DEVELOPER_KEY:-$HOME/.garmin/developer_key.der}"
if [ ! -f "$KEY" ]; then
    echo "Developer key not found at $KEY. Generate one as described in README.md." >&2
    exit 1
fi
