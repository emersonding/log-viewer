class Lumen < Formula
  desc "macOS log reviewer with color rendering and large file support"
  homepage "https://github.com/emersonding/lumen-log-viewer"
  url "https://github.com/emersonding/lumen-log-viewer/releases/download/v2.1.0/lumen-2.1.0-arm64.tar.gz"
  sha256 "7d12edc44c3dbbf810a8af136d6c8a187d8ed2b89233522ff939328dca482349"
  license "MIT"
  version "2.1.0"

  depends_on :macos
  depends_on macos: :sonoma
  depends_on arch: :arm64

  def install
    bin.install "lumen"
    prefix.install "Lumen.app"
  end

  def caveats
    <<~EOS
      To add Lumen to your Applications folder (Launchpad, Dock, Spotlight):
        sudo ln -sf #{prefix}/Lumen.app /Applications/Lumen.app

      Run from the terminal:
        lumen

      On first launch, macOS Gatekeeper may block the app.
      Go to System Settings > Privacy & Security > click "Open Anyway".
    EOS
  end

  test do
    assert_predicate bin/"lumen", :exist?
    assert_predicate prefix/"Lumen.app/Contents/MacOS/Lumen", :exist?
  end
end
