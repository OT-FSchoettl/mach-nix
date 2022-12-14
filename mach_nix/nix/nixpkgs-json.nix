{
  pkgs ? import (import ./nixpkgs-src.nix) { config = {}; overlays = []; },
  python ? pkgs.python3,
  overrides ? []
}:

let
  mergeOverrides = with pkgs.lib; foldl composeExtensions (self: super: { });

  pnamePassthruOverride = pySelf: pySuper: {
    fetchPypi = args: (pySuper.fetchPypi args).overrideAttrs (oa: {
      passthru = { inherit (args) pname; };
    });
  };

  nameMap = {
    pytorch = "torch";
  };

  py = pkgs.lib.recursiveUpdate python { packageOverrides = mergeOverrides ( overrides ++ [ pnamePassthruOverride ] ); };

  l = import ./lib.nix { inherit (pkgs) lib; inherit pkgs; };
in

with pkgs;
with lib;
with builtins;
let
  pname_and_version = python: attrname:
    let
      p = python.pkgs."${attrname}";
      pname = get_pname p;
      requirements = p.requirements or null;
      res = if pname != "" && p ? version then
        {
          inherit pname requirements;
          version = (toString p.version);
        }
      else
        null;
    in
      { "${attrname}" = res; };

  get_pname = pkg:
    let
      res = tryEval (
        if pkg ? src.pname then
          pkg.src.pname
        else if pkg ? pname then
          let pname = pkg.pname; in
            if nameMap ? "${pname}" then nameMap."${pname}" else pname
          else ""
      );
    in
      toString res.value;

  not_usable = pkg:
    (tryEval (
      if pkg == null
      then true
      else if hasAttrByPath ["meta" "broken"] pkg
      then pkg.meta.broken
      else false
    )).value;

  usable_pkgs = python_pkgs: filterAttrs (name: val: ! (not_usable val)) python_pkgs;
  all_pkgs = python: map (pname: pname_and_version python pname) (attrNames (usable_pkgs python.pkgs));
  merged = python: mapAttrs (name: val: elemAt val 0) (zipAttrs (all_pkgs python));
in
writeText "nixpkgs-py-pkgs-json" (toJSON (merged py))
