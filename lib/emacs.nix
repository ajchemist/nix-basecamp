# Shared by the standalone app and the Home Manager module.
{ lib }:
{
  package = { pkgs, gui ? false }: if gui then pkgs.emacs else pkgs.emacs-nox;

  warmProgram = pkgs: pkgs.writeShellScript "eln-warm" ''
    exec /usr/bin/perl -MDynaLoader -MFile::Find -MCwd=abs_path -e '
      @ARGV = map { abs_path $_ } grep { -d } @ARGV or exit;
      find({ no_chdir => 1, wanted => sub {
        /\.eln\z/ or return;
        my $h = DynaLoader::dl_load_file($File::Find::name, 0) or return;
        DynaLoader::dl_unload_file($h) } }, @ARGV)' -- "$@"
  '';

  warmActivation = { package, program }: ''
    mark="$HOME/.cache/emacs/eln-warmed.${baseNameOf "${package}"}"
    if [ ! -e "$mark" ] && ! kill -0 "$(cat "$mark.pid" 2>/dev/null)" 2>/dev/null; then
      run mkdir -p "$HOME/.cache/emacs"
      run nohup sh -c 'echo $$ >"$2.pid"; "$0" "$1" && mv "$2.pid" "$2"' ${program} ${package}/lib/emacs "$mark" >/dev/null 2>&1 </dev/null &
    fi
  '';
}
