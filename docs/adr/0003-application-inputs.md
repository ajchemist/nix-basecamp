# ADR 0003: Applications take upstream inputs, not basecamp

- Status: accepted
- Date: 2026-10-16
- Amends: [ADR 0002](0002-application-ownership.md) ("builds on basecamp's
  `lib.mkDarwin` / `lib.mkHome`", "Applications depend on basecamp")

## Context

After ADR 0002, emacs-camp and agent-camp kept basecamp as an input only for
its nixpkgs and its builders, which their checks used. Their fixtures then
carried basecamp's Homebrew and Karabiner setup, a basecamp lock update was
what moved their nixpkgs, and anyone using an application without basecamp
still fetched it.

## Decision

An application flake takes `nixpkgs`, `home-manager` and `nix-darwin` from
upstream, at the URLs basecamp uses, and builds its checks with the upstream
builders. It does not depend on basecamp. A personal setup composes them:
basecamp's `lib.mkDarwin` / `lib.mkHome` with the applications' modules in
`modules`, and each application's three inputs pointed at basecamp's:

```nix
emacs-camp = {
  url = "github:ajchemist/emacs-camp";
  inputs.nixpkgs.follows = "basecamp/nixpkgs";
  inputs.home-manager.follows = "basecamp/home-manager";
  inputs.nix-darwin.follows = "basecamp/nix-darwin";
};
```

## Consequences

- One lock, the setup's, pins nixpkgs, Home Manager and nix-darwin for
  basecamp and every application. A missing `follows` shows up as a second
  copy in that lock (`home-manager_2`).
- Basecamp's builders and options stay its downstream contract; nothing in
  basecamp changes for this.
