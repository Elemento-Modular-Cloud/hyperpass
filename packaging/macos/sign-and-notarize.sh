#!/usr/bin/env bash
set -euo pipefail

# Open installer package, codesign its contents, then signs and notarizes it

### check that we have all required tools
for i in codesign pkgbuild productsign xcrun xmllint ; do
    if [ ! -x "$(which ${i})" ]; then
        echo "Unable to execute command $i, cannot continue"
        exit 1
    fi
done

# handle arguments
POSITIONAL=()

function help_and_exit {
    echo "Usage:"
    echo " $(basename "$0") --app-signer <identity> --installer-signer <identity> --notarize-id <apple-id> --notarize-password <password> PKGFILE"
    echo ""
    echo "This utility takes a MacOS installer package to expands it, codesign its contents, repack and sign."
    echo "It can also submit the signed package to Apple's notarization facility, retrieve the result and if successful, update the package."
    echo ""
    echo "Argument details are as follows:"
    echo "    --app-signer <identity> --installer-signer <identity>"
    echo "These identities are SHA1 keys identifying cert+private-key pairs provided by Apple. Use 'security find-identity -v' to see which you have available"
    echo "Note there are separate identities for application signing and installer signing"
    echo ""
    echo "Optional notarization requires:"
    echo "    --notarize-id <apple-id> --notarize-password <password>"
    echo "These are your Apple ID and the app-specific password for 'altool' - refer to this doc for details:"
    echo "https://developer.apple.com/documentation/security/notarizing_your_app_before_distribution/customizing_the_notarization_workflow "
    echo ""
    echo "You may also need to pass --notarize-provider <ProviderShortName>, see \`xcrun altool --list-providers\` if you have more than one."
    exit 1
}

while [[ $# -gt 0 ]]; do
    key=$1
    case $key in
    --app-signer)
        SIGN_APP="$2"
        shift 2
        ;;
    --installer-signer)
        SIGN_PKG="$2"
        shift 2
        ;;
    --notarize-id)
        NOTARIZE_ID="$2"
        shift 2
        ;;
    --notarize-password)
        NOTARIZE_PASSWORD="$2"
        shift 2
        ;;
    --notarize-provider)
        NOTARIZE_PROVIDER="$2"
        shift 2
        ;;
    -h|--help)
        help_and_exit
        ;;
    *) # unknown option
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ ${#POSITIONAL[@]} != 1 ]]; then
    help_and_exit
fi
PKGFILE="$1"


if [ -z "${SIGN_APP+x}" ]; then
    echo "Missing --app-signer argument"
    help_and_exit
fi

if [ "${SIGN_APP}" != "-" ] && [ -z "${SIGN_PKG+x}" ]; then
    echo "Missing --installer-signer argument"
    help_and_exit
fi

if [ ! -f "${PKGFILE}" ]; then
    echo "${PKGFILE}: file not found"
    exit 1
fi

if [ -n "${NOTARIZE_ID+x}" ] && [ -z "${NOTARIZE_PASSWORD:-}" ]; then
    echo -n "Apple Developer account password: "
    read -s NOTARIZE_PASSWORD
    echo
fi

function check_already_signed
{
    PKG="$1"
    spctl --assess --type install "$PKG" &> /dev/null
    status1=$?
    codesign --verify --deep "$PKG" &> /dev/null
    status2=$?
    [ $status1 -eq 0 ] && [ $status2 -eq 0 ]
}

if check_already_signed "${PKGFILE}"; then
    echo "${PKGFILE} is already signed, aborting"
    exit 1
fi


PKGFILENAME=$(basename "${PKGFILE}")
if [ -f "${PKGFILENAME}" ]; then
    echo "Making backup copy of ${PKGFILE}"
    cp -v "${PKGFILE}" "${PKGFILENAME}.orig"
fi

function sign_installer {
    local src="$1"
    local dest="$2"
    productsign --sign "${SIGN_PKG}" "${src}" "${dest}"
}

function entitlements {
    FILE="$( mktemp -u ).plist"
    ENTITLEMENTS=( "$@" )
    [ "${SIGN_APP}" == "-" ] && ENTITLEMENTS+=( "com.apple.security.cs.disable-library-validation" )
    [ ${#ENTITLEMENTS[@]} -eq 0 ] && return

    ARGS=()
    for entitlement in "${ENTITLEMENTS[@]}"; do
        ARGS+=( "-c" "Add :${entitlement} bool true" )
    done;

    /usr/libexec/PlistBuddy "${ARGS[@]}" ${FILE} > /dev/null
    echo --entitlements ${FILE}
}

# Apple timestamp server is unreachable from some environments (CI sandbox).
# Set ELP_NO_TIMESTAMP=1 to sign without a secure timestamp.
TIMESTAMP_ARGS=(--timestamp)
if [ "${ELP_NO_TIMESTAMP:-0}" = "1" ]; then
    TIMESTAMP_ARGS=(--timestamp=none)
fi

function codesign_each {
    local extra_args=( "$@" )
    local path
    while IFS= read -r -d '' path; do
        codesign -v "${TIMESTAMP_ARGS[@]}" --options runtime --force --strict \
            "${extra_args[@]}" \
            --sign "${SIGN_APP}" \
            "${path}"
    done
}

function codesign_binaries {
    DIR="$1"

    # AppleDouble / Finder metadata in the payload makes codesign --deep fail with
    # "unsealed contents present in the root directory of an embedded framework".
    find "${DIR}" \( -name '._*' -o -name '.DS_Store' \) -delete

    # sign every file in the directory
    find "${DIR}" -type f ! -name '._*' -print0 | codesign_each \
            $( entitlements ) \
            --prefix com.elemento.elp.

    # sign qemu with the right entitlements
    find "${DIR}" -type f -name 'qemu-system-*' -print0 | codesign_each \
            $( entitlements com.apple.security.hypervisor \
                            com.apple.security.cs.disable-executable-page-protection ) \
            --identifier com.elemento.elp.qemu

    # sign elpd with additional entitlements for using the Apple Virtualization framework
    find "${DIR}" -type f -name elpd -print0 | codesign_each \
            $( entitlements com.apple.security.virtualization ) \
            --identifier com.elemento.elp.elpd

    # sign every bundle in the directory
    find "${DIR}" -type d -name '*.app' -print0 | codesign_each \
            --deep \
            $( entitlements ) \
            --prefix com.elemento.elp.
}

SCRIPTDIR=$(perl -MCwd=realpath -e "print realpath '$0/..'")

WORKDIR=$(mktemp -d)
function clean_workdir
{
    rm -rf "${WORKDIR}"
}
trap clean_workdir EXIT

echo "Work directory: ${WORKDIR}"
PKG_ROOT="${WORKDIR}/root"

# Extract main package
pkgutil --expand "${PKGFILE}" "${PKG_ROOT}"

# For each component in the package, extract their Payloads
pushd "${PKG_ROOT}"
for i in *.pkg ; do
    mkdir "${WORKDIR}/${i}"
    COPYFILE_DISABLE=1 tar xzvpf "${i}/Payload" -C "${WORKDIR}/${i}"

    codesign_binaries "${WORKDIR}/${i}"

    rm "${i}/Payload"
    COPYFILE_DISABLE=1 tar -czv --format cpio -f "${i}/Payload" -C "${WORKDIR}/${i}" .
done
popd

# Flatten into the work directory (cwd may be read-only).
FLAT_PKG="${WORKDIR}/${PKGFILENAME}"
pkgutil --flatten "${PKG_ROOT}" "${FLAT_PKG}"

SIGNED_PKG="${FLAT_PKG}"
if [ -n "${SIGN_PKG+x}" ]; then
  PRODUCT_OUT="${WORKDIR}/signed-${PKGFILENAME}"
  PRODUCTSIGN_ARGS=(--sign "${SIGN_PKG}")
  if [ "${ELP_NO_TIMESTAMP:-0}" = "1" ]; then
    PRODUCTSIGN_ARGS+=(--timestamp=none)
  fi
  if productsign "${PRODUCTSIGN_ARGS[@]}" "${FLAT_PKG}" "${PRODUCT_OUT}"; then
    SIGNED_PKG="${PRODUCT_OUT}"
    echo "Signed install package: ${SIGNED_PKG}"
  else
    echo "warning: productsign failed (often Keychain/sandbox EPERM)." >&2
    echo "warning: using flattened pkg whose inner binaries are already codesigned." >&2
    echo "Flattened package: ${FLAT_PKG}"
  fi
else
  echo "Flattened unsigned package: ${FLAT_PKG}"
fi

# Copy out before the EXIT trap deletes WORKDIR.
COPY_TARGETS=(
  "$(dirname "${PKGFILE}")/${PKGFILENAME%.pkg}.signed.pkg"
  "/tmp/${PKGFILENAME}"
  "${HOME}/Desktop/${PKGFILENAME}"
)
COPIED=""
for dest in "${COPY_TARGETS[@]}"; do
  if cp -f "${SIGNED_PKG}" "${dest}" 2>/dev/null; then
    echo "Copied to ${dest}"
    COPIED="${dest}"
  fi
done
if [ -z "${COPIED}" ]; then
  echo "error: signed package was created but could not be copied out of ${WORKDIR}" >&2
  exit 1
fi

####
#### Notarization ######
####

if [ -z "${NOTARIZE_ID+x}" ] || [ -z "${NOTARIZE_PASSWORD+x}" ]; then
    echo "Required Notarization credentials not supplied (--notarize-id, --notarize-password), bailing"
    exit 0
fi


# Extract necessary metadata from pkg
TITLE=$(xmllint --xpath "string(//title)" "${PKG_ROOT}/Distribution")
VERSION=$(xmllint --xpath "string(//product/@version)" "${PKG_ROOT}/Distribution")
echo "Title: '${TITLE}'"
echo "Version: '${VERSION}'"

# Generate a unique bundle id for this submission (replacing + with -)
BUNDLE_ID="${TITLE}.${VERSION//+/-}.$(date +%s)"

# send notarization
echo -n "Sending ${PKGFILENAME} for notarization..."
_tmpout=$(mktemp)

# optional notarization provider (now "team ID" in notarytool)
NOTARIZE_OPTS=()
if [ -n "${NOTARIZE_PROVIDER:-}" ]; then
    NOTARIZE_OPTS=( --team-id "${NOTARIZE_PROVIDER}" )
fi

xcrun notarytool submit \
             --wait \
             --apple-id "${NOTARIZE_ID}" \
             --password "${NOTARIZE_PASSWORD}" \
             "${NOTARIZE_OPTS[@]}" "${PKGFILENAME}" 2>&1 | tee "${_tmpout}"

# check the request uuid
_requuid=$(cat "${_tmpout}" | grep "RequestUUID" | awk '{ print $3 }')
echo "RequestUUID: ${_requuid}"

if [ -z "${_requuid}" ]; then
    echo "There was an error:"
    echo "==================================================================="
    cat "${_tmpout}"
    echo "==================================================================="
    echo "Error getting RequestUUID, notarization unsuccessful"
    exit 3
fi

echo "Waiting for notarization to be complete (this could take up to an hour, depending on Apple's servers).."

function print_tasks
{
    echo "Waiting cancelled!"
    echo ""
    echo "To manually monitor notarization process with"
    echo "    xcrun altool --notarization-info '${_requuid}' --username '${NOTARIZE_ID}' --password '${NOTARIZE_PASSWORD}'"
    echo "and if successful, staple the notarization to the package with"
    echo "    xcrun stapler staple -v '${PKGFILENAME}'"
}
trap print_tasks SIGINT


for c in {80..0}; do
    sleep 60
    xcrun notarytool info \
                 --username "${NOTARIZE_ID}" \
                 --password "${NOTARIZE_PASSWORD}" \
                 "${_requuid}" 2>&1 | tee ${_tmpout}
    _status=$(cat "${_tmpout}" | grep "Status:" | awk '{ print $2 }')
    if [ "${_status}" == "invalid" ]; then
        echo "Error: Got invalid notarization!"
        echo "==================================================================="
        cat "${_tmpout}"
        echo "==================================================================="
        exit 4
    fi

    if [ "${_status}" == "success" ]; then
        echo -n "Notarization successful! Stapling..."
        xcrun stapler staple -v "${PKGFILENAME}"
        break
    fi
    echo "Notarization in progress, waiting..."
done

# Verifying notarized
if ! xcrun stapler validate "${PKGFILENAME}" | grep worked ; then
    echo "Error: final package verification failed";
    exit 5
fi

echo "..done. ${PKGFILENAME} is notarized and ready to upload"
