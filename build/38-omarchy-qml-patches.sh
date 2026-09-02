#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy shell — EL10/Qt 6.10 QML source patches
###############################################################################
# Qt 6.10's QML parser still rejects the ECMAScript-3 future reserved words as
# identifiers, so `var transient` and `var byte` are hard syntax errors here.
# Upstream omarchy is developed against Arch's older Qt where they parse, so
# the payload ships them broken on EL10:
#
#   - plugins/notifications/Service.qml fails to load, and with it the entire
#     notification service — nothing ever claims org.freedesktop.Notifications,
#     so the desktop has no notifications at all. Verified with `qs -p`:
#     `var transient` gives "Expected token `identifier'", `var isTransient`
#     parses.
#   - plugins/panels/network/Model.js is latent — the parse error surfaces when
#     decoding an SSID containing an escaped hex byte.
#
# Both are fixed in the pneuma-el10 omedora fork. These seds stay as a
# self-heal so the image is correct whether or not the COPR has rebuilt yet,
# and the assertion below fails the build if a payload bump reintroduces the
# pattern anywhere in the shell.
###############################################################################

OMARCHY_SHELL=/usr/share/omarchy/shell

echo "::group:: Patch QML reserved-word identifiers"

# Substitutions are anchored per line so the freedesktop `transient` hint key
# (notification.hints["transient"]) and the surrounding prose keep the word.
sed -i \
    -e 's/^\( *\)var transient = false$/\1var isTransient = false/' \
    -e 's/^\( *\)transient = !!(/\1isTransient = !!(/' \
    -e 's/{ transient = false }/{ isTransient = false }/' \
    -e 's/^\( *\)return transient ||/\1return isTransient ||/' \
    "${OMARCHY_SHELL}/plugins/notifications/Service.qml"

sed -i \
    -e 's/^\( *\)var byte = parseInt(hex, 16)$/\1var byteValue = parseInt(hex, 16)/' \
    -e 's/byte < 32 || byte === 127/byteValue < 32 || byteValue === 127/' \
    "${OMARCHY_SHELL}/plugins/panels/network/Model.js"

echo "::endgroup::"

echo "::group:: Smoke checks"

# No ES3 reserved word may survive as a declared identifier anywhere in the
# shell — a single one takes down whichever plugin declares it.
if grep -rqE '\b(var|let|const)[[:space:]]+(transient|byte|char|double|final|int|long|short|public|abstract|boolean|float|goto|implements|interface|native|package|private|protected|synchronized|throws|volatile|enum)\b' \
    --include='*.qml' --include='*.js' "${OMARCHY_SHELL}/"; then
    echo "ERROR: QML reserved-word identifier in the omarchy shell — Qt 6.10 will not parse it" >&2
    exit 1
fi

# The notification service is the one that fails at load rather than lazily;
# assert the rename actually landed rather than trusting the sed silently.
grep -q 'var isTransient = false' "${OMARCHY_SHELL}/plugins/notifications/Service.qml"

echo "::endgroup::"

echo "Omarchy QML patches applied!"
