#!/usr/bin/env python3
"""Generate a deterministic Xcode project with no third-party generator dependency."""
from pathlib import Path
import hashlib,json
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key, isa, **fields):
    ref = uid(key); objects[ref] = dict(isa=isa, **fields); return ref
def ref(path, filetype): return obj('file:'+path,'PBXFileReference',lastKnownFileType=filetype,path=path,sourceTree='<group>')
def build(key, file=None, product=None):
    return obj('build:'+key,'PBXBuildFile',**({'fileRef':file} if file else {'productRef':product}))
def phase(key, isa, files): return obj(key,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
source_refs=[]; app_sources=[]; tests=[]
for path in sorted((ROOT/'App').rglob('*.swift')):
    rel=path.relative_to(ROOT).as_posix(); f=ref(rel,'sourcecode.swift'); source_refs.append(f); app_sources.append(build(rel,file=f))
for path in sorted((ROOT/'Tests').rglob('*.swift')):
    rel=path.relative_to(ROOT).as_posix(); f=ref(rel,'sourcecode.swift'); source_refs.append(f); tests.append(build(rel,file=f))
assets=ref('App/Resources/Assets.xcassets','folder.assetcatalog')
privacy=ref('App/Resources/PrivacyInfo.xcprivacy','text.xml')
source_refs += [assets,privacy,ref('App/Resources/Info.plist','text.plist.xml'),ref('App/Resources/Xingji.entitlements','text.plist.entitlements')]
config_refs={name:ref('Configuration/'+name+'.xcconfig','text.xcconfig') for name in ['Debug','Release']}
source_refs += list(config_refs.values())
package=obj('local-package','XCLocalSwiftPackageReference',relativePath='.')
products=[obj('swift:'+name,'XCSwiftPackageProductDependency',productName=name,package=package) for name in ['XingjiCore','XingjiData']]
app_product=obj('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Xingji.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=obj('test-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='XingjiTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products_group=obj('products-group','PBXGroup',children=[app_product,test_product],name='Products',sourceTree='<group>')
root_group=obj('root-group','PBXGroup',children=source_refs+[products_group],sourceTree='<group>')
def configs(kind):
    refs=[]
    for name in ['Debug','Release']:
        settings={}
        if kind=='project':
            settings={'SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_STRICT_CONCURRENCY':'targeted','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
        elif kind=='app':
            settings={'PRODUCT_NAME':'Xingji','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','ENABLE_TESTABILITY':'YES' if name=='Debug' else 'NO','OTHER_LDFLAGS':['$(inherited)','-ObjC']}
        else:
            settings={'PRODUCT_NAME':'XingjiTests','PRODUCT_BUNDLE_IDENTIFIER':'$(XINGJI_BUNDLE_ID).tests','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'','CODE_SIGN_ENTITLEMENTS':'','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Xingji.app/Xingji','BUNDLE_LOADER':'$(TEST_HOST)','ASSETCATALOG_COMPILER_APPICON_NAME':'','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0'}
        kwargs={'name':name,'buildSettings':settings}
        if kind!='project': kwargs['baseConfigurationReference']=config_refs[name]
        refs.append(obj(f'config:{kind}:{name}','XCBuildConfiguration',**kwargs))
    return obj('config-list:'+kind,'XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
preflight=obj('preflight','PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=[],outputPaths=[],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/sh',shellScript='"${SRCROOT}/Scripts/check_release_config.sh"\n',name='Validate release configuration',alwaysOutOfDate=1)
app=obj('app-target','PBXNativeTarget',buildConfigurationList=configs('app'),buildPhases=[preflight,phase('app-sources','PBXSourcesBuildPhase',app_sources),phase('app-frameworks','PBXFrameworksBuildPhase',[build('app:'+p,product=p) for p in products]),phase('app-resources','PBXResourcesBuildPhase',[build('assets',file=assets),build('privacy',file=privacy)])],buildRules=[],dependencies=[],name='Xingji',packageProductDependencies=products,productName='Xingji',productReference=app_product,productType='com.apple.product-type.application')
proxy=obj('test-proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=app,remoteInfo='Xingji')
dependency=obj('test-dependency','PBXTargetDependency',target=app,targetProxy=proxy)
test=obj('test-target','PBXNativeTarget',buildConfigurationList=configs('tests'),buildPhases=[phase('test-sources','PBXSourcesBuildPhase',tests),phase('test-frameworks','PBXFrameworksBuildPhase',[build('test:'+p,product=p) for p in products]),phase('test-resources','PBXResourcesBuildPhase',[])],buildRules=[],dependencies=[dependency],name='XingjiTests',packageProductDependencies=products,productName='XingjiTests',productReference=test_product,productType='com.apple.product-type.bundle.unit-test')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{app:{'CreatedOnToolsVersion':'16.0','SystemCapabilities':{'com.apple.iCloud':{'enabled':1},'com.apple.BackgroundModes':{'enabled':1},'com.apple.Push':{'enabled':1}}},test:{'CreatedOnToolsVersion':'16.0','TestTargetID':app}}},buildConfigurationList=configs('project'),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=root_group,packageReferences=[package],productRefGroup=products_group,projectDirPath='',projectRoot='',targets=[app,test])
def render(value,depth=0):
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+ ' = '+render(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(depth+1)+render(v,depth+1)+',\n' for v in value)+'\t'*depth+')'
    return str(value) if isinstance(value,int) else json.dumps(value,ensure_ascii=False)
directory=ROOT/'Xingji.xcodeproj'; directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
scheme=directory/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
(scheme/'Xingji.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Xingji.app" BlueprintName="Xingji" ReferencedContainer="container:Xingji.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test}" BuildableName="XingjiTests.xctest" BlueprintName="XingjiTests" ReferencedContainer="container:Xingji.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Xingji.app" BlueprintName="Xingji" ReferencedContainer="container:Xingji.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Xingji.app" BlueprintName="Xingji" ReferencedContainer="container:Xingji.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Xingji.xcodeproj: app, test target, local packages, shared scheme.')
