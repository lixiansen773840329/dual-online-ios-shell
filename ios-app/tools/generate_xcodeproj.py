# -*- coding: utf-8 -*-
"""生成可在 Mac Xcode 打开的 DualOnline.xcodeproj。"""

from __future__ import annotations

import uuid
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[1]
SRC = IOS_ROOT / "DualOnline"
PROJ = IOS_ROOT / "DualOnline.xcodeproj"


def _id() -> str:
    return uuid.uuid4().hex[:24].upper()


def generate() -> Path:
    swift_files = sorted(SRC.glob("*.swift"))
    if not swift_files:
        raise FileNotFoundError(f"未找到 Swift 源码: {SRC}")

    project_id = _id()
    target_id = _id()
    sources_phase = _id()
    resources_phase = _id()
    frameworks_phase = _id()
    config_list_proj = _id()
    config_list_target = _id()
    debug_proj = _id()
    release_proj = _id()
    debug_target = _id()
    release_target = _id()
    product_id = _id()
    group_main = _id()
    group_src = _id()
    group_products = _id()
    www_ref = _id()
    info_ref = _id()

    file_refs = {}
    build_files = {}
    for sf in swift_files:
        file_refs[sf.name] = _id()
        build_files[sf.name] = _id()

    frameworks = ["UIKit.framework", "WebKit.framework", "Foundation.framework", "UserNotifications.framework"]
    fw_refs = {name: _id() for name in frameworks}
    fw_builds = {name: _id() for name in frameworks}

    sources_children = "".join(f"\t\t\t\t{file_refs[s.name]} /* {s.name} */,\n" for s in swift_files)
    sources_build = "".join(f"\t\t\t\t{build_files[s.name]} /* {s.name} in Sources */,\n" for s in swift_files)
    fw_children = "".join(f"\t\t\t\t{fw_refs[n]} /* {n} */,\n" for n in frameworks)
    fw_build = "".join(f"\t\t\t\t{fw_builds[n]} /* {n} in Frameworks */,\n" for n in frameworks)

    file_ref_sections = []
    for s in swift_files:
        file_ref_sections.append(
            f"\t\t{file_refs[s.name]} /* {s.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {s.name}; sourceTree = \"<group>\"; }};"
        )
    file_ref_sections.append(
        f"\t\t{info_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    file_ref_sections.append(
        f"\t\t{www_ref} /* www */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = www; path = www; sourceTree = SOURCE_ROOT; }};"
    )
    file_ref_sections.append(
        f"\t\t{product_id} /* DualOnline.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DualOnline.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    for n in frameworks:
        file_ref_sections.append(
            f"\t\t{fw_refs[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {n}; path = System/Library/Frameworks/{n}; sourceTree = SDKROOT; }};"
        )

    build_file_sections = []
    for s in swift_files:
        build_file_sections.append(
            f"\t\t{build_files[s.name]} /* {s.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[s.name]} /* {s.name} */; }};"
        )
    www_build = _id()
    build_file_sections.append(
        f"\t\t{www_build} /* www in Resources */ = {{isa = PBXBuildFile; fileRef = {www_ref} /* www */; }};"
    )
    for n in frameworks:
        build_file_sections.append(
            f"\t\t{fw_builds[n]} /* {n} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fw_refs[n]} /* {n} */; }};"
        )

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_sections)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_sections)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fw_build}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{group_main} = {{
			isa = PBXGroup;
			children = (
				{group_src} /* DualOnline */,
				{group_products} /* Products */,
{fw_children}			);
			sourceTree = "<group>";
		}};
		{group_src} /* DualOnline */ = {{
			isa = PBXGroup;
			children = (
{sources_children}				{info_ref} /* Info.plist */,
				{www_ref} /* www */,
			);
			path = DualOnline;
			sourceTree = "<group>";
		}};
		{group_products} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{product_id} /* DualOnline.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{target_id} /* DualOnline */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {config_list_target} /* Build configuration list for PBXNativeTarget "DualOnline" */;
			buildPhases = (
				{sources_phase} /* Sources */,
				{frameworks_phase} /* Frameworks */,
				{resources_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = DualOnline;
			productName = DualOnline;
			productReference = {product_id} /* DualOnline.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
			}};
			buildConfigurationList = {config_list_proj} /* Build configuration list for PBXProject "DualOnline" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = "zh-Hans";
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = {group_main};
			productRefGroup = {group_products} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{target_id} /* DualOnline */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{resources_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{www_build} /* www in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_build}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{debug_proj} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				IPHONEOS_DEPLOYMENT_TARGET = 13.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{release_proj} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				IPHONEOS_DEPLOYMENT_TARGET = 13.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{debug_target} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = 10000;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = DualOnline/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "双端随行录";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.dual.online;
				PRODUCT_NAME = DualOnline;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{release_target} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = 10000;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = DualOnline/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "双端随行录";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.dual.online;
				PRODUCT_NAME = DualOnline;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{config_list_proj} /* Build configuration list for PBXProject "DualOnline" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_proj} /* Debug */,
				{release_proj} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{config_list_target} /* Build configuration list for PBXNativeTarget "DualOnline" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_target} /* Debug */,
				{release_target} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""
    PROJ.mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(pbx, encoding="utf-8")
    # 修正源码路径：pbx 中 DualOnline 组 path=DualOnline，但 www 在上一级
    # 将 swift 文件放在 DualOnline/ 下，www 使用 SOURCE_ROOT/www —— 已设置
    # 需要把 group DualOnline 的文件路径对齐：工程根为 ios-app，源码在 DualOnline/
    print(f"已生成 {PROJ}")
    return PROJ


if __name__ == "__main__":
    generate()
