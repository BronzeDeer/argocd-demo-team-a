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

  listToObj(l): {
    [std.toString(item.key)]: item.value
    for item in std.mapWithIndex(function(idx,val){key: idx, value: val}, l)
  },

  // Helper function with allows for easy patching with withers
  makeAppPatchable(
    app,
    _argoCD,
    // relative Path to the root of the git repo containing the targeted app
    // If the app is in a vendored repo, then it is the relative path to the vendored repo in this repo
    // If the app is in this repo, then it should be the relative path from this file to its repo root (default)
    relativePathToAppRepoRoot,
    sourceType= error("makeAppPatchable: Must set 'sourceType' to one of ([helm,jsonnet]) to automatically set correct metadata format. \n Alternatively use withSourceType('jsonnet') or withSourceType('helm') BEFORE withPatchedXXXMetadata")
  ):
  # This needs to be lifted outside of the patch, since it is used by conditional fields, which are evaluated before the patch object is constructed
  local _isMultiSource = std.objectHas(app.spec, "sources");
  app {
    local this = self,
    // Add in relevant hidden fields for patching, they will not be rendered
    // The withers will reference these
    parentMetadata:: _argoCD,
    relativePathToAppRepoRoot:: relativePathToAppRepoRoot,
    patchedMetadata:: {},
    sourceType:: sourceType,

    # When `spec.sources` is present, spec.source is ignored
    isMultiSource:: _isMultiSource,
    # Transform sources into a dict to allow easier patching by idx
    _sources:: if _isMultiSource then
      $.listToObj(app.spec.sources)
    else
      error ("This is not a multi-source app, please patch `spec.source` directly"),
    # When the app gets rendered out, transform the internal (patched) source dict back to the correct format in the original field (source/sources)
    spec+: {
      [if _isMultiSource then "sources"]: std.objectValues(this._sources),

      # Ensure that no direct patching happened to the fields, which would break our internal mechanism and break the principle of least surprise
      # Otherwise, if an outside patch uses something like super.source(s) in a conditional field, it would render the field early and make subsequent util withers on the source no-op
      # Used by our escape hatch withSourcedRendered() to bypass the assert
      _sourcesRendered:: false,

      #Provide sort function to normalize source arrays for comparison
      local keyFunction = function(srcObj) "%s:%s:%s" % [srcObj.repoURL,srcObj.targetRevision,srcObj.path],
      assert this.spec._sourcesRendered || !_isMultiSource || std.sort(this.spec.sources,keyFunction) == std.sort(std.objectValues(this._sources),keyFunction): "Error `spec.sources` was patched directly. Please use the util methods or patch _sources[std.toString(idx)] for the source you want to modify  \n If you want to use existing functions that target spec.sources directly. You can also use \"withRenderedSource()\"\n Please note that some source-modifiying util methods out of this library cannot be used on this app anymore and will error",

    },
  },

  # Util method to detach the _sources mechanism that we use for easy directed patching and restore compatibility with existing methods targeting spec.source and spec.sources directly for patching
  withRenderedSource(): {
    local this = self,

    # Detach the existing _sources object and replace _sources with an empty object to assert against
    # This is to ensure that our own util methods relying on it have not been used after
    _sources:: {},
    assert self._sources == {}: "withRenderedSource() was used on this app, some source-modifying util methods cannot be used anymore, please patch the spec.source(s) field directly",
    local _sourcesToRender = super._sources,

    #Disable the original asserts and render sources from the new field
    local _isMultiSource = super.isMultiSource,
    spec+: {
      _sourcesRendered:: true,
      [if _isMultiSource then "sources"]: std.objectValues(_sourcesToRender),
    },
  },

  local multiSourceError = "Error: Need to specify `sourceIdx` when App has multiple sources",

  // Sets path in the metadata, and patch the source path to made relative to the repo root within this repo
  // This is necessary when vendoring app manifests that still assume to be relative to their old repo root
  // If this is multiSource app, then need to set `sourceIdx` to indicate which source to patch
  withPatchedPath(sourceIdx = error("withPatchedPath: "+ multiSourceError)): {
    local this = self,
    patchedMetadata+:: {
      path: '$ARGOCD_APP_SOURCE_PATH',
    },

    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    local sourcePatch = { path: $.cleanPath(this.parentMetadata.path + '/' + this.relativePathToAppRepoRoot + '/' + super.path) },

    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},
  },

  withSourceType(type):{
    sourceType:: type,
  },

  // Set spec.source.revision to the revision of the parent and add the resolved or unresolved revision to the path
  // Resolved revisions are concrete pinned commits, while unresolved revisions might be commit, branch, or tag reference. In the case of a branch, this decouples the app from the parent
  // If this is multiSource app, then need to set `sourceIdx` to indicate which source to patch
  withPatchedRevision(resolvedRevision=true, sourceIdx = error("withPatchedRevision: "+multiSourceError)): {
    local this = self,
    patchedMetadata+:: {
      targetRevision: if resolvedRevision then '$ARGOCD_APP_REVISION' else '$ARGOCD_APP_SOURCE_TARGET_REVISION',
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    local sourcePatch = { targetRevision: this.parentMetadata.targetRevision },

    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},
  },

  // Set spec.source.repoURL to the repoURL of the parent and add the repoURL to the metadata that will be passed down
  // If this is multiSource app, then need to set `sourceIdx` to indicate which source to patch
  withPatchedRepoURL(sourceIdx = error("withPatchedRepoURL: " + multiSourceError)): {
    local this = self,
    patchedMetadata+:: {
      repoURL: '$ARGOCD_APP_SOURCE_REPO_URL',
    },
    // Fixme: Replace with https://github.com/jsonnet-libs/argo-cd-libsonnet
    local sourcePatch = { repoURL: this.parentMetadata.repoURL },

    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},
  },

  // Apply the patch`defined by `sourcePatch` to source at idx `sourceIdx` or spec.source if not multi-source
  withSourcePatchByIdx(sourcePatch, sourceIdx=error("withSourcePatchByIdx: "+ multiSourceError)): {
    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},
  },

  // Convenience method combining the 3 operations on spec.source, which are used together most of the time
  // If this is multiSource app, then need to set `sourceIdx` to indicate which source to patch
  withPatchedSource(sourceIdx = error("withPatchedSource: "+multiSourceError)):
    $.withPatchedRevision(resolvedRevision=true,sourceIdx=sourceIdx)
    + $.withPatchedPath(sourceIdx=sourceIdx)
    + $.withPatchedRepoURL(sourceIdx=sourceIdx)
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
  withPatchedJsonnetMetadata(sourceIdx= error ("withPatchedJsonnetMetadata: "+ multiSourceError)): {
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

    local sourcePatch = if this.sourceType == "jsonnet" then { directory+: { jsonnet+: { tlas: patchedTLAs } } } else {},

    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},
  },

  // Add or overwrite all patched metadata field to the metadata passed via helm parameters
  withPatchedHelmMetadata(sourceIdx = error ("withPatchHelmMetadata: "+multiSourceError)): {
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
    local sourcePatch = if this.sourceType == "helm" then { helm+: { parameters: patchedParametersAsList } } else {},

    # Patch singular source or desired source (based on sourceIdx) in the source dict
    local _isMultiSource = super.isMultiSource,
    _sources+:: { [if _isMultiSource then std.toString(sourceIdx)]+: sourcePatch},
    spec+: {[if !_isMultiSource then "source"]+: sourcePatch},

  },

  // Convenience Method that combines all patches for chaining into an app in the same repo that uses either helm or jsonnet
  withPatchedLocalApp(sourceIdx = error("withPatchedLocalApp: " + multiSourceError)): (
    $.withPatchedSource(sourceIdx=sourceIdx)
    + $.withPatchedProject()
    + $.withPatchedNamespace()
    + $.withPatchedHelmMetadata(sourceIdx=sourceIdx)
    + $.withPatchedJsonnetMetadata(sourceIdx=sourceIdx)
    + $.withPatchDestination()
  ),
}
