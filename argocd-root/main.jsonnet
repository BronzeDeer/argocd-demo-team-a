// Here we are using jsonnet to load base Applicaitons from each app folder and patching to forward metadata like source, appNamespace and project information,
// this allows us to keep some settings closer to their individual apps and allows most developers to write plain argo apps, but it is ultimately a stylistic choice
// We could also generate each argo app here fully

local defaults = import './defaults.libsonnet';
local utils = import './utils.libsonnet';

// Relative path to navigate to the repo root, must be kept correct for chaining to local apps to work
local relativePathToMyRoot = '..';


// ArgoCD ultimately expects a list of resources
function(_argoCD=defaults._argoCD) [
  utils.makeAppPatchable(
    app=(std.parseYaml(importstr '../apps/kubesay/app.yaml')),
    _argoCD=_argoCD,
    // The app manifest is in the same repo and not in another vendored repo
    relativePathToAppRepoRoot=relativePathToMyRoot,
    sourceType = "jsonnet"
  )
  + utils.withPatchedLocalApp(),
]
