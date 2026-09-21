#!/usr/bin/env python3
"""Generate OtohaChat.xcodeproj from this repository layout.

The generated project is committed so a clone can open it in Xcode without
running this script. Re-run the script after adding app sources and confirm
the project still matches.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "OtohaChat.xcodeproj"

SHARED_SWIFT = sorted((ROOT / "Apps" / "Shared").glob("*.swift"))
MAC_SWIFT = sorted((ROOT / "Apps" / "macOS").glob("*.swift"))
IOS_SWIFT = sorted((ROOT / "Apps" / "iOS").glob("*.swift"))


def hid(name: str) -> str:
    import hashlib

    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def file_ref(path: Path, extra: str = "sourcecode.swift") -> tuple[str, str]:
    ident = hid(f"file:{path.relative_to(ROOT)}")
    rel = path.relative_to(ROOT)
    return ident, f'\t\t{ident} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = {extra}; path = {path.name}; sourceTree = "<group>"; }};'


def build_file(file_id: str, name: str) -> tuple[str, str]:
    ident = hid(f"build:{name}:{file_id}")
    return ident, f"\t\t{ident} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};"


def main() -> None:
    mac_files = [(p, *file_ref(p)) for p in MAC_SWIFT]
    ios_files = [(p, *file_ref(p)) for p in IOS_SWIFT]
    shared_files = [(p, *file_ref(p)) for p in SHARED_SWIFT]

    mac_info = hid("file:Apps/macOS/Info.plist")
    ios_info = hid("file:Apps/iOS/Info.plist")
    mac_ent = hid("file:Apps/macOS/OtohaChat.entitlements")
    mac_pcc_ent = hid("file:Apps/macOS/OtohaChat-PCC.entitlements")
    ios_ent = hid("file:Apps/iOS/OtohaChat.entitlements")
    ios_pcc_ent = hid("file:Apps/iOS/OtohaChat-PCC.entitlements")
    base_xc = hid("file:Config/Base.xcconfig")
    pcc_xc = hid("file:Config/PCC.xcconfig")

    assets = hid("file:Apps/Shared/Assets.xcassets")
    kit_product = hid("product:OtohaChatKit")
    kit_product_ios = hid("product:OtohaChatKit-iOS")
    kit_dep_mac = hid("dep:OtohaChatKit-mac")
    kit_dep_ios = hid("dep:OtohaChatKit-ios")
    local_pkg = hid("pkg:local")

    mac_target = hid("target:mac")
    ios_target = hid("target:ios")
    mac_sources = hid("phase:mac-sources")
    ios_sources = hid("phase:ios-sources")
    mac_frameworks = hid("phase:mac-frameworks")
    ios_frameworks = hid("phase:ios-frameworks")
    mac_resources = hid("phase:mac-resources")
    ios_resources = hid("phase:ios-resources")
    project_id = hid("project")
    main_group = hid("group:main")
    apps_group = hid("group:apps")
    shared_group = hid("group:shared")
    mac_group = hid("group:macos")
    ios_group = hid("group:ios")
    config_group = hid("group:config")
    products_group = hid("group:products")
    mac_product = hid("product:OtohaChat.app")
    ios_product = hid("product:OtohaChat-iOS.app")

    mac_cfg_list = hid("cfgl:mac")
    ios_cfg_list = hid("cfgl:ios")
    proj_cfg_list = hid("cfgl:proj")
    mac_debug = hid("cfg:mac-debug")
    mac_release = hid("cfg:mac-release")
    mac_pcc = hid("cfg:mac-pcc")
    ios_debug = hid("cfg:ios-debug")
    ios_release = hid("cfg:ios-release")
    ios_pcc = hid("cfg:ios-pcc")
    proj_debug = hid("cfg:proj-debug")
    proj_release = hid("cfg:proj-release")
    proj_pcc = hid("cfg:proj-pcc")

    mac_build_files = []
    ios_build_files = []
    build_entries = []
    file_entries = []

    for path, fid, fentry in shared_files + mac_files:
        bid, bentry = build_file(fid, path.name)
        mac_build_files.append((bid, path.name))
        build_entries.append(bentry)
        file_entries.append(fentry)
    for path, fid, fentry in shared_files + ios_files:
        bid, bentry = build_file(fid + "-ios", path.name + "-ios")
        # reuse same file refs for shared
        ident = hid(f"build-ios:{path.relative_to(ROOT)}")
        bentry = f"\t\t{ident} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {path.name} */; }};"
        ios_build_files.append((ident, path.name))
        build_entries.append(bentry)
        if fentry not in file_entries:
            file_entries.append(fentry)
    for path, fid, fentry in shared_files:
        if fentry not in file_entries:
            file_entries.append(fentry)

    # Unique file entries
    seen = set()
    unique_files = []
    for path, fid, fentry in shared_files + mac_files + ios_files:
        if fid not in seen:
            seen.add(fid)
            unique_files.append(fentry)

    unique_files.extend(
        [
            f'\t\t{mac_info} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};',
            f'\t\t{ios_info} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};',
            f'\t\t{mac_ent} /* OtohaChat.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = OtohaChat.entitlements; sourceTree = "<group>"; }};',
            f'\t\t{mac_pcc_ent} /* OtohaChat-PCC.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "OtohaChat-PCC.entitlements"; sourceTree = "<group>"; }};',
            f'\t\t{ios_ent} /* OtohaChat.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = OtohaChat.entitlements; sourceTree = "<group>"; }};',
            f'\t\t{ios_pcc_ent} /* OtohaChat-PCC.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "OtohaChat-PCC.entitlements"; sourceTree = "<group>"; }};',
            f'\t\t{base_xc} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; }};',
            f'\t\t{pcc_xc} /* PCC.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = PCC.xcconfig; sourceTree = "<group>"; }};',
            f'\t\t{assets} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};',
            f'\t\t{mac_product} /* OtohaChat.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OtohaChat.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
            f'\t\t{ios_product} /* OtohaChat.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OtohaChat.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
        ]
    )

    assets_mac_build = hid("build:assets-mac")
    assets_ios_build = hid("build:assets-ios")
    build_entries.append(
        f"\t\t{assets_mac_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets} /* Assets.xcassets */; }};"
    )
    build_entries.append(
        f"\t\t{assets_ios_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets} /* Assets.xcassets */; }};"
    )

    kit_mac_build = hid("build:kit-mac")
    kit_ios_build = hid("build:kit-ios")
    build_entries.append(
        f"\t\t{kit_mac_build} /* OtohaChatKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {kit_dep_mac} /* OtohaChatKit */; }};"
    )
    build_entries.append(
        f"\t\t{kit_ios_build} /* OtohaChatKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {kit_dep_ios} /* OtohaChatKit */; }};"
    )

    shared_ids = "\n".join(f"\t\t\t\t{fid} /* {path.name} */," for path, fid, _ in shared_files)
    mac_ids = "\n".join(
        [
            *(f"\t\t\t\t{fid} /* {path.name} */," for path, fid, _ in mac_files),
            f"\t\t\t\t{mac_info} /* Info.plist */,",
            f"\t\t\t\t{mac_ent} /* OtohaChat.entitlements */,",
            f"\t\t\t\t{mac_pcc_ent} /* OtohaChat-PCC.entitlements */,",
        ]
    )
    ios_ids = "\n".join(
        [
            *(f"\t\t\t\t{fid} /* {path.name} */," for path, fid, _ in ios_files),
            f"\t\t\t\t{ios_info} /* Info.plist */,",
            f"\t\t\t\t{ios_ent} /* OtohaChat.entitlements */,",
            f"\t\t\t\t{ios_pcc_ent} /* OtohaChat-PCC.entitlements */,",
        ]
    )

    mac_src_ids = "\n".join(f"\t\t\t\t{bid} /* {name} in Sources */," for bid, name in mac_build_files)
    ios_src_ids = "\n".join(f"\t\t\t\t{bid} /* {name} in Sources */," for bid, name in ios_build_files)

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_entries)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(unique_files)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{mac_frameworks} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{kit_mac_build} /* OtohaChatKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ios_frameworks} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{kit_ios_build} /* OtohaChatKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{main_group} = {{
			isa = PBXGroup;
			children = (
				{apps_group} /* Apps */,
				{config_group} /* Config */,
				{products_group} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{apps_group} /* Apps */ = {{
			isa = PBXGroup;
			children = (
				{shared_group} /* Shared */,
				{mac_group} /* macOS */,
				{ios_group} /* iOS */,
			);
			path = Apps;
			sourceTree = "<group>";
		}};
		{shared_group} /* Shared */ = {{
			isa = PBXGroup;
			children = (
{shared_ids}
				{assets} /* Assets.xcassets */,
			);
			path = Shared;
			sourceTree = "<group>";
		}};
		{mac_group} /* macOS */ = {{
			isa = PBXGroup;
			children = (
{mac_ids}
			);
			path = macOS;
			sourceTree = "<group>";
		}};
		{ios_group} /* iOS */ = {{
			isa = PBXGroup;
			children = (
{ios_ids}
			);
			path = iOS;
			sourceTree = "<group>";
		}};
		{config_group} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{base_xc} /* Base.xcconfig */,
				{pcc_xc} /* PCC.xcconfig */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{products_group} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{mac_product} /* OtohaChat.app */,
				{ios_product} /* OtohaChat.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{mac_target} /* OtohaChat */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {mac_cfg_list} /* Build configuration list for PBXNativeTarget "OtohaChat" */;
			buildPhases = (
				{mac_sources} /* Sources */,
				{mac_frameworks} /* Frameworks */,
				{mac_resources} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = OtohaChat;
			packageProductDependencies = (
				{kit_dep_mac} /* OtohaChatKit */,
			);
			productName = OtohaChat;
			productReference = {mac_product} /* OtohaChat.app */;
			productType = "com.apple.product-type.application";
		}};
		{ios_target} /* OtohaChat-iOS */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ios_cfg_list} /* Build configuration list for PBXNativeTarget "OtohaChat-iOS" */;
			buildPhases = (
				{ios_sources} /* Sources */,
				{ios_frameworks} /* Frameworks */,
				{ios_resources} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = "OtohaChat-iOS";
			packageProductDependencies = (
				{kit_dep_ios} /* OtohaChatKit */,
			);
			productName = OtohaChat;
			productReference = {ios_product} /* OtohaChat.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "OtohaChat" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {main_group};
			packageReferences = (
				{local_pkg} /* XCLocalSwiftPackageReference "." */,
			);
			productRefGroup = {products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{mac_target} /* OtohaChat */,
				{ios_target} /* OtohaChat-iOS */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{mac_resources} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{assets_mac_build} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ios_resources} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{assets_ios_build} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{mac_sources} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{mac_src_ids}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ios_sources} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{ios_src_ids}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{proj_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			baseConfigurationReference = {base_xc} /* Base.xcconfig */;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{proj_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			baseConfigurationReference = {base_xc} /* Base.xcconfig */;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = Release;
		}};
		{proj_pcc} /* PCC */ = {{
			isa = XCBuildConfiguration;
			baseConfigurationReference = {pcc_xc} /* PCC.xcconfig */;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = PCC;
		}};
		{mac_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Apps/macOS/OtohaChat.entitlements;
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/macOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = YES;
			}};
			name = Debug;
		}};
		{mac_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "Apps/macOS/OtohaChat-PCC.entitlements";
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/macOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = OTOHACHAT_PCC;
				SWIFT_EMIT_LOC_STRINGS = YES;
			}};
			name = Release;
		}};
		{mac_pcc} /* PCC */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "Apps/macOS/OtohaChat-PCC.entitlements";
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/macOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG OTOHACHAT_PCC";
				SWIFT_EMIT_LOC_STRINGS = YES;
			}};
			name = PCC;
		}};
		{ios_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Apps/iOS/OtohaChat.entitlements;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/iOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{ios_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "Apps/iOS/OtohaChat-PCC.entitlements";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/iOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = OTOHACHAT_PCC;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
		{ios_pcc} /* PCC */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "Apps/iOS/OtohaChat-PCC.entitlements";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/iOS/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = co.otoha.OtohaChat;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG OTOHACHAT_PCC";
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = PCC;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{proj_cfg_list} /* Build configuration list for PBXProject "OtohaChat" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{proj_debug} /* Debug */,
				{proj_release} /* Release */,
				{proj_pcc} /* PCC */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
		{mac_cfg_list} /* Build configuration list for PBXNativeTarget "OtohaChat" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{mac_debug} /* Debug */,
				{mac_release} /* Release */,
				{mac_pcc} /* PCC */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
		{ios_cfg_list} /* Build configuration list for PBXNativeTarget "OtohaChat-iOS" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ios_debug} /* Debug */,
				{ios_release} /* Release */,
				{ios_pcc} /* PCC */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{local_pkg} /* XCLocalSwiftPackageReference "." */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = .;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{kit_dep_mac} /* OtohaChatKit */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {local_pkg} /* XCLocalSwiftPackageReference "." */;
			productName = OtohaChatKit;
		}};
		{kit_dep_ios} /* OtohaChatKit */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {local_pkg} /* XCLocalSwiftPackageReference "." */;
			productName = OtohaChatKit;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""

    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(pbx)
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )
    print(f"Wrote {PROJECT / 'project.pbxproj'}")
    print(f"macOS sources: {len(mac_build_files)} iOS sources: {len(ios_build_files)}")


if __name__ == "__main__":
    main()
