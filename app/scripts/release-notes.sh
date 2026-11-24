#!/bin/zsh
# Prints the install section of the release notes for the zip that `build-app.sh --dist` produced.
# Run it against the exact zip being uploaded: every build has a different checksum.
set -euo pipefail
cd "${0:A:h}/.."
version="${$(<VERSION)//[[:space:]]/}"
[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,3}$' ]] || { print -u2 "VERSION must be a dotted number"; exit 1 }
zip="ARBITER-Activity-Monitor-${version}-macos-arm64.zip"
[[ -f "dist/$zip" ]] || { print -u2 "dist/$zip not found; run scripts/build-app.sh --dist first"; exit 1 }
sum="${$(shasum -a 256 "dist/$zip")%% *}"
url="https://github.com/Tantum-Arbiter/arbiter-activity-monitor/releases/download/v${version}/${zip}"
cat <<NOTES
## Install from Terminal (no macOS warning)

Paste this into Terminal. It downloads the zip, stops unless the checksum matches, unpacks the app into Applications and opens it.

\`\`\`bash
cd "\$(mktemp -d)" \\
  && curl -fLO ${url} \\
  && echo "${sum}  ${zip}" | shasum -a 256 -c \\
  && ditto -x -k ${zip} /Applications \\
  && open /Applications/arbiter-activity-monitor.app
\`\`\`

This is for a first install; after that, use Settings → Updates. The app is not notarized by Apple. Terminal downloads are not marked the way browser downloads are, so macOS does not run its notarization check on this copy. Use it only if you trust this repository.

## Install from the browser download

Unzip, move the app where you want it (for example Applications), and open it. macOS will say Apple could not verify the app is free of malware, because the build is ad-hoc signed and not notarized. Click **Done**, then go to System Settings → Privacy & Security and click **Open Anyway**. This is needed once.

SHA-256: \`${sum}\`
NOTES
