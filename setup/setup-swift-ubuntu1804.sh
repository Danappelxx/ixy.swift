set -euxo pipefail

# Install Necessary Swift Components
sudo apt-get update
sudo apt-get install -y \
          binutils \
          git \
          libc6-dev \
          libcurl4 \
          libedit2 \
          libgcc-5-dev \
          libpython2.7 \
          libsqlite3-0 \
          libstdc++-5-dev \
          libxml2 \
          pkg-config \
          tzdata \
          zlib1g-dev

SWIFT_PACKAGE="swift-5.5.3-RELEASE-ubuntu18.04"
SWIFT_URL="https://download.swift.org/swift-5.5.3-release/ubuntu1804/swift-5.5.3-RELEASE/swift-5.5.3-RELEASE-ubuntu18.04.tar.gz"
SWIFT_FOLDER="${HOME}/.swift"

# Create Swift Folder
mkdir -p "${SWIFT_FOLDER}"
cd "${SWIFT_FOLDER}"

# Download and Unpack
wget "${SWIFT_URL}"
tar xzf "${SWIFT_PACKAGE}.tar.gz"
if [ -f "${SWIFT_FOLDER}/current" ]
then
	rm "${SWIFT_FOLDER}/current"
	echo "removed old symlink"
fi
ln -s "${SWIFT_FOLDER}/${SWIFT_PACKAGE}" "${SWIFT_FOLDER}/current"
