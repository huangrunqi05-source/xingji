#!/usr/bin/env python3
import json,subprocess,plistlib,xml.etree.ElementTree as ET
from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(r/'Xingji.xcodeproj/project.pbxproj')]))
objects=p['objects']
for k,o in objects.items():
 if o['isa']=='PBXFileReference' and o.get('sourceTree')=='<group>': assert (r/o['path']).exists(),o['path']
 for field in ['children','files','buildPhases','buildConfigurations','targets','packageReferences','packageProductDependencies','dependencies']:
  for ref in o.get(field,[]): assert ref in objects,(k,field,ref)
 for field in ['fileRef','productRef','buildConfigurationList','mainGroup','productReference','baseConfigurationReference','target','targetProxy','package']:
  if field in o: assert o[field] in objects,(k,field,o[field])
ET.parse(r/'Xingji.xcodeproj/xcshareddata/xcschemes/Xingji.xcscheme')
for path in (r/'App/Resources/Assets.xcassets').rglob('Contents.json'):
 for item in json.loads(path.read_text()).get('images',[]):
  if 'filename' in item: assert (path.parent/item['filename']).exists()
with (r/'App/Resources/Info.plist').open('rb') as f: info=plistlib.load(f)
assert 'location' in info['UIBackgroundModes'] and 'remote-notification' in info['UIBackgroundModes']
assert info['CKSharingSupported']
assert 'NSLocationAlwaysAndWhenInUseUsageDescription' in info
print('Project references, resources, shared scheme and required capability declarations: OK')
