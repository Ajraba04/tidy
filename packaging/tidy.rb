# Homebrew Cask template for a future `homebrew-tidy` tap.
#
# Not yet submitted anywhere. To cut a release:
#   1. Tag and push (e.g. `v1.5.0`) to trigger .github/workflows/release.yml.
#   2. Download the release zip and compute its checksum:
#        shasum -a 256 Tidy-v1.5.0.zip
#   3. Fill in `version` and `sha256` below and copy this file into your
#      tap's Casks/ directory as `tidy.rb`.

cask "tidy" do
  version "1.5.0"
  sha256 "REPLACE_WITH_RELEASE_ZIP_SHA256"

  url "https://github.com/ajraba04/tidy/releases/download/v#{version}/Tidy-v#{version}.zip"
  name "Tidy"
  desc "Menu bar app for reclaiming disk space"
  homepage "https://github.com/ajraba04/tidy"

  depends_on macos: ">= :sonoma"

  app "Tidy.app"

  zap trash: [
    "~/Library/Application Support/Tidy",
  ]
end
