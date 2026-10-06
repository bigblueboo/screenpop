cask "screenpop" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/@REPO@/releases/download/v#{version}/Screenpop-#{version}.zip"
  name "Screenpop"
  desc "Menu bar screenshots with background removal and AI file names"
  homepage "https://github.com/@REPO@"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Screenpop.app"

  uninstall quit: "com.bigblueboo.screenpop"

  zap trash: "~/Library/Preferences/com.bigblueboo.screenpop.plist"
end
