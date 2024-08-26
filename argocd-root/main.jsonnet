// Here we are using jsonnet to load base Applicaitons from each app folder and patching to forward metadata like source, appNamespace and project information,
// this allows us to keep some settings closer to their individual apps and allows most developers to write plain argo apps, but it is ultimately a stylistic choice
// We could also generate each argo app here fully

local defaults = import './defaults.libsonnet';
local utils = import './utils.libsonnet';

// Relative path to navigate to the repo root, must be kept correct for chaining to local apps to work
local relativePathToMyRoot = '..';


// ArgoCD ultimately expects a list of resources
function(_argoCD=defaults._argoCD,_clusterInfo=defaults._clusterInfo) [
  #
  # This is not actually an app-of-apps, but use full patching anyway as an example
  utils.makeAppPatchable(
    app=(std.parseYaml(importstr '../apps/kubesay/app.yaml')),
    _argoCD=_argoCD,
    // The app manifest is in the same repo and not in another vendored repo
    relativePathToAppRepoRoot=relativePathToMyRoot,
    sourceType = "jsonnet"
  )
  + utils.withPatchedLocalApp(),

  # http-echo
  utils.makeAppPatchable(
    app=( std.parseYaml(importstr '../apps/http-echo/app.yaml')),
    _argoCD=_argoCD,
    relativePathToAppRepoRoot=relativePathToMyRoot,
    sourceType="helm"
  )
  + utils.withPatchedLocalApp()
  + {
    // Fixme: Make Helper Method for this or use https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: {
      source+: {
        helm+: {
          //Pass and transform relevant configuration from cluster
          valuesObject+: {
            ingress+: {
              baseDomain: _clusterInfo.baseDomain,
              annotations+: _clusterInfo.ingressAnnotations,
              className: _clusterInfo.ingressClass
            }
          }
        }
      }
    }
  },

  # rollout-example
  utils.makeAppPatchable(
    app=( std.parseYaml(importstr '../apps/rollout-example/app.yaml')),
    _argoCD=_argoCD,
    relativePathToAppRepoRoot=relativePathToMyRoot,
    sourceType="helm"
  )
  + utils.withPatchDestination()
  + utils.withPatchedSource()
  + utils.withPatchedProject()
  + utils.withPatchedNamespace()
  + {
    # Due to the simplicity, this app adds no second layer of indirection, so we template out the full domain here
    local domain = "rollout." + std.lstripChars(_clusterInfo.baseDomain,'.'),
    // Fixme: Make Helper Method for this or use https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: {
      source+: {
        helm+: {
          //Pass and transform relevant configuration from cluster
          valuesObject+: {
            ingress+: {
              annotations+: _clusterInfo.ingressAnnotations,
              hosts+: [domain],
              tls+: [{
                secretName: "rollout-cluster-base-tls",
                hosts: [domain]
              }],
            },
          },
        },
      },
    },
  },
]
