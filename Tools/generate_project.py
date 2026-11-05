#!/usr/bin/env python3
from pathlib import Path
import hashlib, plistlib
ROOT=Path(__file__).resolve().parents[1]
objects={}
def ident(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(object_name,**values):
    key=ident(object_name);objects[key]=values;return key
def group(name,path,children):return add(name,isa='PBXGroup',path=path,sourceTree='<group>',children=children)
source_build=[];app_files=[];sensor_files=[];resource_files=[];resource_build=[]
for directory,target_files in [('Sources/SystraApp',app_files),('Sources/SensorBridge',sensor_files)]:
    for file in sorted((ROOT/directory).iterdir()):
        kind={'.swift':'sourcecode.swift','.c':'sourcecode.c.c','.h':'sourcecode.c.h'}.get(file.suffix)
        if not kind:continue
        reference=add(str(file.relative_to(ROOT)),isa='PBXFileReference',lastKnownFileType=kind,path=file.name,sourceTree='<group>');target_files.append(reference)
        if file.suffix!='.h':source_build.append(add('build:'+str(file.relative_to(ROOT)),isa='PBXBuildFile',fileRef=reference))
for name,kind in [('Info.plist','text.plist.xml'),('Systra.icns','image.icns'),('Systra.png','image.png'),('SystraSmall.png','image.png'),('SystraMenu.png','image.png'),('SystraMenu@2x.png','image.png'),('English.json','text.json')]:
    reference=add('Resources/'+name,isa='PBXFileReference',lastKnownFileType=kind,path=name,sourceTree='<group>');resource_files.append(reference)
    if name in ['Systra.icns', 'SystraSmall.png', 'SystraMenu.png', 'SystraMenu@2x.png', 'English.json']:resource_build.append(add('build:resource:'+name,isa='PBXBuildFile',fileRef=reference))
app_group=group('app-group','SystraApp',app_files);sensor_group=group('sensor-group','SensorBridge',sensor_files)
sources=group('sources','Sources',[app_group,sensor_group]);resources=group('resources','Resources',resource_files)
product=add('product',isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='Systra.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products',isa='PBXGroup',name='Products',sourceTree='<group>',children=[product])
root_files=[]
for name,kind in [('README.md','net.daringfireball.markdown'),('build.sh','text.script.sh'),('run.sh','text.script.sh'),('test.sh','text.script.sh')]:
    root_files.append(add('root:'+name,isa='PBXFileReference',lastKnownFileType=kind,path=name,sourceTree='<group>'))
extra_groups=[]
for directory in ['Tests','Tools']:
    refs=[]
    for file in sorted((ROOT/directory).iterdir()):
        if not file.is_file():continue
        kind={'.swift':'sourcecode.swift','.py':'text.script.python'}.get(file.suffix,'text')
        refs.append(add('extra:'+str(file.relative_to(ROOT)),isa='PBXFileReference',lastKnownFileType=kind,path=file.name,sourceTree='<group>'))
    extra_groups.append(group('group:'+directory,directory,refs))
main=add('main',isa='PBXGroup',sourceTree='<group>',children=[sources,resources]+extra_groups+root_files+[products])
sources_phase=add('sources-phase',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=source_build,runOnlyForDeploymentPostprocessing='0')
resources_phase=add('resources-phase',isa='PBXResourcesBuildPhase',buildActionMask='2147483647',files=resource_build,runOnlyForDeploymentPostprocessing='0')
frameworks_phase=add('frameworks-phase',isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
project_configs=[];target_configs=[]
for config in ['Debug','Release']:
    settings=dict(SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET='14.0',CLANG_ENABLE_MODULES='YES',SWIFT_VERSION='5.0')
    project_configs.append(add('project-'+config,isa='XCBuildConfiguration',name=config,buildSettings=settings))
    settings=dict(PRODUCT_NAME='Systra',PRODUCT_BUNDLE_IDENTIFIER='com.arsenkocharyan.systra',INFOPLIST_FILE='Resources/Info.plist',GENERATE_INFOPLIST_FILE='NO',SWIFT_OBJC_BRIDGING_HEADER='Sources/SensorBridge/Sensors.h',HEADER_SEARCH_PATHS=['$(inherited)','$(SRCROOT)/Sources/SensorBridge'],CODE_SIGN_STYLE='Manual',CODE_SIGN_IDENTITY='-',ENABLE_HARDENED_RUNTIME='NO',ENABLE_APP_SANDBOX='NO',CURRENT_PROJECT_VERSION='33',MARKETING_VERSION='0.9.4',ARCHS='arm64',SUPPORTED_PLATFORMS='macosx',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'],OTHER_LDFLAGS=['$(inherited)','-framework','IOKit','-framework','Metal','-framework','ServiceManagement'],SWIFT_OPTIMIZATION_LEVEL='-Onone' if config=='Debug' else '-O',SWIFT_COMPILATION_MODE='singlefile' if config=='Debug' else 'wholemodule',GCC_OPTIMIZATION_LEVEL='0' if config=='Debug' else 's')
    if config=='Debug':settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
    target_configs.append(add('target-'+config,isa='XCBuildConfiguration',name=config,buildSettings=settings))
project_list=add('project-configs',isa='XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
target_list=add('target-configs',isa='XCConfigurationList',buildConfigurations=target_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
target=add('target',isa='PBXNativeTarget',name='Systra',productName='Systra',productType='com.apple.product-type.application',productReference=product,buildConfigurationList=target_list,buildPhases=[sources_phase,frameworks_phase,resources_phase],buildRules=[],dependencies=[])
project=add('project',isa='PBXProject',attributes=dict(LastUpgradeCheck='1600',BuildIndependentTargetsInParallel='YES'),buildConfigurationList=project_list,compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
def quote(s):return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
def encode(value,level=0):
    indent='\t'*level
    if isinstance(value,dict):return '{\n'+''.join(indent+'\t'+quote(k)+' = '+encode(v,level+1)+';\n' for k,v in value.items())+indent+'}'
    if isinstance(value,list):return '('+''.join('\n'+indent+'\t'+encode(v,level+1)+',' for v in value)+'\n'+indent+')'
    return quote(value)
folder=ROOT/'Systra.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=project))+'\n')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Systra.app" BlueprintName="Systra" ReferencedContainer="container:Systra.xcodeproj"/>'
(scheme/'Systra.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><PostActions><ExecutionAction ActionType="Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction"><ActionContent title="Install Systra in Applications" scriptText="python3 &quot;$SRCROOT/Tools/install_app.py&quot; &quot;$TARGET_BUILD_DIR/$WRAPPER_NAME&quot;"><EnvironmentBuildable>{reference}</EnvironmentBuildable></ActionContent></ExecutionAction></PostActions><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(folder)
