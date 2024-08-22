{
  // This really should have been in the standard lib or at least https://github.com/jsonnet-libs/xtd
  cleanPath(pathString, sep='/'):
    local _recurse(accumulator, remainingSegments) =
      if std.length(remainingSegments) == 0 then
        accumulator
      else
        local head = remainingSegments[0];
        local tail = remainingSegments[1:];
        if std.isEmpty(head) || head == '.' then
          // ignore current path element (was /./ or //)
          _recurse(accumulator, tail)
        else if head == '..' && !(std.length(accumulator) == 0 || accumulator[std.length(accumulator) - 1] == '..') then
          // Remove last pathSegment from the accumulator
          _recurse(accumulator[:std.length(accumulator) - 1], tail)
        else
          // Put current path segent in the accumulator
          _recurse(accumulator + [head], tail)
    ;
    // Fixme: Whitespace regex?
    local trimmedString = std.stripChars(pathString, ' \n\t');
    local segments = std.split(trimmedString, sep);
    local processedPath = std.join(sep, _recurse([], segments));

    // Special case handling
    if std.isEmpty(processedPath) then
      './'
    else if trimmedString[0] == '/' then
      '/' + processedPath
    else
      processedPath
  ,


  patchJsonnetTLAs(tlas, patch): (
    local tlaName = '_argoCD';
    local asDict = {
      [item.key]: {
        value: item.value,
        code: item.code,
      }
      for item in tlas
    };
    // We cannot load the jsonnet itself, so instead append the patch inside the variable
    local patchedValue = std.get(asDict, tlaName, default={value:'{}'}) + { value+: '+' + std.toString(patch) };

    // Patch the value inside the dict and transform the dict back to the name/value format
    [
      {
        name: item.key,
        value: item.value.value,
        code: item.value.code
      }
      for item in std.objectKeysValues(asDict { [tlaName]: patchedValue })
    ]

  ),

  // Return parameters or null
  getHelmParameters(app): (
    if std.objectHas(app, 'spec') then
      if std.objectHas(app, 'spec.source') then
        if std.objectHas(app, 'spec.source.helm') then
          if std.objectHas(app, 'spec.source.helm.parameters') then
            app.spec.source.helm.parameters
  ),

  // Returns tlas or null
  getTLAs(app): (
    if std.objectHas(app, 'spec') then
      if std.objectHas(app, 'spec.source') then
        if std.objectHas(app, 'spec.source.directory') then
          if std.objectHas(app, 'spec.source.directory.jsonnet') then
            if std.objectHas(app, 'spec.source.directory.jsonnet.tlas') then
              app.spec.source.directory.jsonnet.tlas
  ),

  // Helper function with allows for easy patching with withers
  makeAppPatchable(
    app,
    _argoCD,
    // relative Path to the root of the git repo containing the targeted app
    // If the app is in a vendored repo, then it is the relative path to the vendored repo in this repo
    // If the app is in this repo, then it should be the relative path from this file to its repo root (default)
    relativePathToAppRepoRoot,
    sourceType= error("makeAppPatchable: Must set 'sourceType' to one of ([helm,jsonnet]) to automatically set correct metadata format. \n Alternatively use withSourceType('jsonnet') or withSourceType('helm') BEFORE withPatchedXXXMetadata")
  ): app {
    // Add in relevant hidden fields for patching, they will not be rendered
    // The withers will reference these
    parentMetadata:: _argoCD,
    relativePathToAppRepoRoot:: relativePathToAppRepoRoot,
    patchedMetadata:: {},
    sourceType:: sourceType,
  },

  // Sets path in the metadata, and patch the source path to made relative to the repo root within this repo
  // This is necessary when vendoring app manifests that still assume to be relative to their old repo root
  withPatchedPath(): {
    local this = self,
    patchedMetadata+:: {
      path: '$ARGOCD_APP_SOURCE_PATH',
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: { source+: { path: $.cleanPath(this.parentMetadata.path + '/' + this.relativePathToAppRepoRoot + '/' + super.path) } },
  },

  withSourceType(type):{
    sourceType:: type,
  },

  // Set spec.source.revision to the revision of the parent and add the resolved or unresolved revision to the path
  // Resolved revisions are concrete pinned commits, while unresolved revisions might be commit, branch, or tag reference. In the case of a branch, this decouples the app from the parent
  withPatchedRevision(resolvedRevision=true): {
    local this = self,
    patchedMetadata+:: {
      targetRevision: if resolvedRevision then '$ARGOCD_APP_REVISION' else '$ARGOCD_APP_SOURCE_TARGET_REVISION',
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: { source+: { targetRevision: this.parentMetadata.targetRevision } },
  },

  // Set spec.source.repoURL to the repoURL of the parent and add the repoURL to the metadata that will be passed down
  withPatchedRepoURL(): {
    local this = self,
    patchedMetadata+:: {
      repoURL: '$ARGOCD_APP_SOURCE_REPO_URL',
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: { source+: { repoURL: this.parentMetadata.repoURL } },
  },

  // Convenience method combining the 3 operations on spec.source, which are used together most of the time
  withPatchedSource():
    $.withPatchedRevision(resolvedRevision=true)
    + $.withPatchedPath()
    + $.withPatchedRepoURL()
  ,

  # Patches destination.name or destination.server depending on what is present in the parents metadata
  # If both are specified, name takes precedence
  withPatchedDestinationNameServer():{
    local name = std.get(self.parentMetadata, "destinationName"),
    local server = std.get(self.parentMetadata, "destinationServer"),

    // Destination can be specified either via server or name, but setting both is not allowed
    patchedMetadata+:: if name != null then 
    # Shadow server in the patched metadata to avoid passing both
    { destinationName: name, destinationServer:: null} 
    else
    # Shadow name in the patched metadata to avoid passing both
    { destinationName:: null, destinationServer: server},

    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    // Name, if present, takes precedence over
    spec+: {destination+: if name != null then { name:  name, server:: null } else { name:: null, server: server}}
  },

  withPatchedDestinationNamespace(): {
    local this = self,
    patchedMetadata+:: { deployNamespace: "$ARGOCD_APP_NAMESPACE"},

    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: { destination+: {namespace: this.parentMetadata.deployNamespace }}
  },

  # Convenience method to patch all destination fields
  withPatchDestination(): (
    $.withPatchedDestinationNameServer()
    + $.withPatchedDestinationNamespace()
  ),

  // Set spec.project to the parent's project and add it to the metadata to be passed down to the app
  withPatchedProject(): {
    local this = self,
    local newAppProject = this.parentMetadata.appProject,
    patchedMetadata+:: {
      appProject: newAppProject,
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: { project: newAppProject },
  },

  // Set metadata.namespace to the parent's appNamespace and add it to the metadata to be passed down to the app
  withPatchedNamespace(): {
    local this = self,
    local newAppNamespace = this.parentMetadata.appNamespace,
    patchedMetadata+:: {
      appNamespace: newAppNamespace,
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    metadata+: { namespace: newAppNamespace },
  },


  // Add or overwrite all patched metadata field to the metadata passed via jsonnet tlas
  // Note that currently this can only correctly overwrite flat metadata structs, nested structures might get incorrectly overwritten
  withPatchedJsonnetMetadata(): {
    local this = self,
    local tlas = $.getTLAs(this),
    local patchedTLAs = if tlas != null then
      $.patchJsonnetTLAs(tlas)
    else
      [{
        name: '_argoCD',
        value: std.toString(this.patchedMetadata),
        code: true,
      }],

    // The overlay must be conditional to avoid situations where we output both (which argoCD detects as two source types)
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: if this.sourceType == "jsonnet" then { source+: { directory+: { jsonnet+: { tlas: patchedTLAs } } } } else {},
  },

  // Add or overwrite all patched metadata field to the metadata passed via helm parameters
  withPatchedHelmMetadata(): {
    local this = self,
    local parameters = $.getHelmParameters(this),
    local parametersAsDict = {
      [item.name]: item.value
      for item in if parameters != null then parameters else []
    },
    // The parameters are specified flat, therefore we need to prefix our metadata with the name of the object containing it
    local prefixedMetadata = {
      ['_argoCD.' + item.key]: item.value
      for item in std.objectKeysValues(this.patchedMetadata)
    },
    local patchedParameters = parametersAsDict + prefixedMetadata,

    local patchedParametersAsList = [
      {
        name: item.key,
        value: item.value,
      }
      for item in std.objectKeysValues(patchedParameters)
    ],

    // The overlay must be conditional to avoid situations where we output both (which argoCD detects as two source types)
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    spec+: if this.sourceType == "helm" then { source+: { helm+: { parameters: patchedParametersAsList } } } else {},
  },

  // Convenience Method that combines all patches for chaining into an app in the same repo that uses either helm or jsonnet
  withPatchedLocalApp(): (
    $.withPatchedSource()
    + $.withPatchedProject()
    + $.withPatchedNamespace()
    + $.withPatchedHelmMetadata()
    + $.withPatchedJsonnetMetadata()
    + $.withPatchDestination()
  ),
}
