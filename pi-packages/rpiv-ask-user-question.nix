{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "rpiv-ask-user-question";
  npmName = "@juicesharp/rpiv-ask-user-question";
  version = "2.7.0";
  hash = "sha256-5sTTFu5B0U2IaNxOvmkQ0jH1hTLljqHg48p742fPBZ8=";
  lock = ./rpiv-ask-user-question-lock.json;
  # Per system: covers the lockfile + npm version + platform prebuilds.
  npmDepsHash = {
    aarch64-darwin = "sha256-aw+nN28sdjS1vVu0V464EJfRD3ySOZV9l6c3YpSIuvY=";
  };
  description = "Ask the user a question from within pi";
  homepage = "https://pi.dev/packages/@juicesharp/rpiv-ask-user-question";
}
