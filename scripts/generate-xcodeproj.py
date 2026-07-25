#!/usr/bin/env python3
"""Generate spacemap.xcodeproj from the SPM source files.

Creates an Xcode project with three targets:
  - spacemap (default, matches host architecture)
  - spacemap-arm64 (Apple Silicon only)
  - spacemap-x86_64 (Intel only)
  - spacemap-universal (fat binary, arm64 + x86_64)

Run: python3 scripts/generate-xcodeproj.py
"""

import hashlib
import os
import json

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES_DIR = os.path.join(PROJECT_DIR, "Sources", "spacemap")
XCODEPROJ_DIR = os.path.join(PROJECT_DIR, "spacemap.xcodeproj")
PBXPROJ_PATH = os.path.join(XCODEPROJ_DIR, "project.pbxproj")

# Gather source files
SOURCE_FILES = sorted([
    f for f in os.listdir(SOURCES_DIR)
    if f.endswith(".swift") and not f.startswith(".")
])

PLIST_FILE = "Info.plist"

# xcassets at project root (copied into bundle by build phase)
ASSETS_DIR = os.path.join(PROJECT_DIR, "Assets.xcassets")


def uuid5(name):
    """Deterministic UUID from a name string."""
    h = hashlib.md5(f"spacemap.{name}".encode()).hexdigest()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


# Pre-generate deterministic UUIDs for every entity
def uid(tag, *args):
    key = ".".join(str(a) for a in args)
    return uuid5(f"{tag}.{key}")


# Groups
ROOT_GROUP = uid("group", "root")
SOURCE_GROUP = uid("group", "Sources")
SPACEMAP_GROUP = uid("group", "spacemap")
RESOURCES_GROUP = uid("group", "Resources")
PRODUCTS_GROUP = uid("group", "Products")

# File references
FILE_REFS = {}
for f in SOURCE_FILES:
    FILE_REFS[f] = uid("fileref", f)
PLIST_REF = uid("fileref", PLIST_FILE)
APPICON_REF = uid("fileref", "AppIcon.icns")
SPACEMAP_ICON_REF = uid("fileref", "spacemap.icns")
ASSETS_REF = uid("fileref", "Assets.xcassets")

# Build file refs
BUILD_FILES = {}
for f in SOURCE_FILES:
    BUILD_FILES[f] = uid("buildfile", f)
APPICON_BUILD = uid("buildfile", "AppIcon.icns")
SPACEMAP_ICON_BUILD = uid("buildfile", "spacemap.icns")
ASSETS_BUILD = uid("buildfile", "Assets.xcassets")

# Targets
TARGET_DEFAULT = uid("target", "spacemap")
TARGET_ARM64 = uid("target", "spacemap-arm64")
TARGET_X86 = uid("target", "spacemap-x86_64")
TARGET_UNIVERSAL = uid("target", "spacemap-universal")

# Build configurations
CONFIG_LIST_TARGET = uid("configlist", "target")
CONFIG_LIST_PROJECT = uid("configlist", "project")

CONFIGS = {}
for arch in ["default", "arm64", "x86_64", "universal", "debug", "release"]:
    CONFIGS[arch] = uid("config", arch)

# Native target refs for the build phase
NATIVE_TARGETS = [TARGET_DEFAULT, TARGET_ARM64, TARGET_X86, TARGET_UNIVERSAL]

# Product references
PRODUCT_DEFAULT = uid("product", "spacemap")
PRODUCT_ARM64 = uid("product", "spacemap-arm64")
PRODUCT_X86 = uid("product", "spacemap-x86_64")
PRODUCT_UNIVERSAL = uid("product", "spacemap-universal")


def arch_setting(target_id):
    """Return ARCHS build setting for a given target."""
    if target_id == TARGET_ARM64:
        return "arm64"
    elif target_id == TARGET_X86:
        return "x86_64"
    elif target_id == TARGET_UNIVERSAL:
        return "arm64 x86_64"
    return ""  # default: standard archs


def target_product_name(target_id):
    names = {
        TARGET_DEFAULT: "spacemap",
        TARGET_ARM64: "spacemap-arm64",
        TARGET_X86: "spacemap-x86_64",
        TARGET_UNIVERSAL: "spacemap-universal",
    }
    return names[target_id]


def target_product_ref(target_id):
    refs = {
        TARGET_DEFAULT: PRODUCT_DEFAULT,
        TARGET_ARM64: PRODUCT_ARM64,
        TARGET_X86: PRODUCT_X86,
        TARGET_UNIVERSAL: PRODUCT_UNIVERSAL,
    }
    return refs[target_id]


def generate_build_config(target_id, name, is_debug):
    config_id = uid("config", f"{target_id}.{name}")
    arch = arch_setting(target_id)
    product_name = target_product_name(target_id)
    product_ref = target_product_ref(target_id)

    build_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO" if is_debug else "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if is_debug else "dwarf-with-dsym",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES" if is_debug else "NO",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0" if is_debug else "3",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1"] if is_debug else [],
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE" if is_debug else "NO",
        "ONLY_ACTIVE_ARCH": "YES" if is_debug else "NO",
        "SDKROOT": "macosx",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if is_debug else "RELEASE",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if is_debug else "-O",
        "PRODUCT_NAME": product_name,
        "PRODUCT_BUNDLE_IDENTIFIER": f"com.jsheffie.spacemap" if target_id == TARGET_DEFAULT else f"com.jsheffie.spacemap.{product_name}",
        "INFOPLIST_FILE": f"Sources/spacemap/{PLIST_FILE}",
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/../Frameworks",
        ],
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Manual",
    }

    if arch:
        build_settings["ARCHS"] = arch

    # Swift source files
    swift_files = [f for f in SOURCE_FILES if f.endswith(".swift")]

    lines = []
    lines.append(f"\t\t{config_id} /* {name} */ = {{")
    lines.append(f"\t\t\tisa = XCBuildConfiguration;")
    lines.append(f"\t\t\tbuildSettings = {{")
    for key, val in sorted(build_settings.items()):
        if isinstance(val, list):
            if val:
                arr_str = ", ".join(f'"{v}"' for v in val)
                lines.append(f"\t\t\t\t{key} = ({arr_str});")
        elif isinstance(val, bool):
            lines.append(f"\t\t\t\t{key} = {'YES' if val else 'NO'};")
        else:
            lines.append(f'\t\t\t\t{key} = "{val}";')
    lines.append(f"\t\t\t}};")
    lines.append(f"\t\t\tname = {name};")
    lines.append(f"\t\t}};")
    return "\n".join(lines)


def generate():
    os.makedirs(XCODEPROJ_DIR, exist_ok=True)

    # Generate all config IDs we'll need
    all_target_configs = []
    for tid in NATIVE_TARGETS:
        all_target_configs.append(uid("config", f"{tid}.Debug"))
        all_target_configs.append(uid("config", f"{tid}.Release"))

    lines = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    lines.append("")

    # PBXBuildFile
    lines.append("/* Begin PBXBuildFile section */")
    for f in SOURCE_FILES:
        lines.append(f"\t\t{BUILD_FILES[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REFS[f]} /* {f} */; }};")
    lines.append(f"\t\t{APPICON_BUILD} /* AppIcon.icns in Resources */ = {{isa = PBXBuildFile; fileRef = {APPICON_REF} /* AppIcon.icns */; }};")
    lines.append(f"\t\t{SPACEMAP_ICON_BUILD} /* spacemap.icns in Resources */ = {{isa = PBXBuildFile; fileRef = {SPACEMAP_ICON_REF} /* spacemap.icns */; }};")
    lines.append(f"\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; }};")
    lines.append("/* End PBXBuildFile section */")
    lines.append("")

    # PBXFileReference
    lines.append("/* Begin PBXFileReference section */")
    for f in SOURCE_FILES:
        lines.append(f"\t\t{FILE_REFS[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{PLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{APPICON_REF} /* AppIcon.icns */ = {{isa = PBXFileReference; lastKnownFileType = file.icns; path = AppIcon.icns; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{SPACEMAP_ICON_REF} /* spacemap.icns */ = {{isa = PBXFileReference; lastKnownFileType = file.icns; path = spacemap.icns; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = SOURCE_ROOT; }};")
    for tid in NATIVE_TARGETS:
        pname = target_product_name(tid)
        pref = target_product_ref(tid)
        lines.append(f"\t\t{pref} /* {pname}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"{pname}.app\"; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append("/* End PBXFileReference section */")
    lines.append("")

    # PBXFrameworksBuildPhase
    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    for tid in NATIVE_TARGETS:
        fphase = uid("phase", f"frameworks.{tid}")
        lines.append(f"\t\t{fphase} /* Frameworks */ = {{")
        lines.append(f"\t\t\tisa = PBXFrameworksBuildPhase;")
        lines.append(f"\t\t\tbuildActionMask = 2147483647;")
        lines.append(f"\t\t\tfiles = (")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append(f"\t\t}};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")

    # PBXGroup
    lines.append("/* Begin PBXGroup section */")
    # Root group
    lines.append(f"\t\t{ROOT_GROUP} = {{")
    lines.append(f"\t\t\tisa = PBXGroup;")
    lines.append(f"\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{SOURCE_GROUP} /* Sources */,")
    lines.append(f"\t\t\t\t{ASSETS_REF} /* Assets.xcassets */,")
    lines.append(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t\tsourceTree = \"<group>\";")
    lines.append(f"\t\t}};")

    # Sources group
    lines.append(f"\t\t{SOURCE_GROUP} /* Sources */ = {{")
    lines.append(f"\t\t\tisa = PBXGroup;")
    lines.append(f"\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{SPACEMAP_GROUP} /* spacemap */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t\tpath = Sources;")
    lines.append(f"\t\t\tsourceTree = \"<group>\";")
    lines.append(f"\t\t}};")

    # Spacemap group
    lines.append(f"\t\t{SPACEMAP_GROUP} /* spacemap */ = {{")
    lines.append(f"\t\t\tisa = PBXGroup;")
    lines.append(f"\t\t\tchildren = (")
    for f in SOURCE_FILES:
        lines.append(f"\t\t\t\t{FILE_REFS[f]} /* {f} */,")
    lines.append(f"\t\t\t\t{PLIST_REF} /* Info.plist */,")
    lines.append(f"\t\t\t\t{APPICON_REF} /* AppIcon.icns */,")
    lines.append(f"\t\t\t\t{SPACEMAP_ICON_REF} /* spacemap.icns */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t\tpath = spacemap;")
    lines.append(f"\t\t\tsourceTree = \"<group>\";")
    lines.append(f"\t\t}};")

    # Products group
    lines.append(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
    lines.append(f"\t\t\tisa = PBXGroup;")
    lines.append(f"\t\t\tchildren = (")
    for tid in NATIVE_TARGETS:
        lines.append(f"\t\t\t\t{target_product_ref(tid)} /* {target_product_name(tid)}.app */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t\tname = Products;")
    lines.append(f"\t\t\tsourceTree = \"<group>\";")
    lines.append(f"\t\t}};")
    lines.append("/* End PBXGroup section */")
    lines.append("")

    # PBXNativeTarget
    lines.append("/* Begin PBXNativeTarget section */")
    for tid in NATIVE_TARGETS:
        pname = target_product_name(tid)
        pref = target_product_ref(tid)
        sphase = uid("phase", f"sources.{tid}")
        fphase = uid("phase", f"frameworks.{tid}")
        rphase = uid("phase", f"resources.{tid}")
        clist = uid("configlist", f"target.{tid}")

        lines.append(f"\t\t{tid} /* {pname} */ = {{")
        lines.append(f"\t\t\tisa = PBXNativeTarget;")
        lines.append(f"\t\t\tbuildConfigurationList = {clist} /* Build configuration list for PBXNativeTarget \"{pname}\" */;")
        lines.append(f"\t\t\tbuildPhases = (")
        lines.append(f"\t\t\t\t{sphase} /* Sources */,")
        lines.append(f"\t\t\t\t{fphase} /* Frameworks */,")
        lines.append(f"\t\t\t\t{rphase} /* Resources */,")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\tbuildRules = (")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\tdependencies = (")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\tname = {pname};")
        lines.append(f"\t\t\tproductName = {pname};")
        lines.append(f"\t\t\tproductReference = {pref} /* {pname}.app */;")
        lines.append(f"\t\t\tproductType = \"com.apple.product-type.application\";")
        lines.append(f"\t\t}};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")

    # PBXProject
    lines.append("/* Begin PBXProject section */")
    proj_obj = uid("project", "obj")
    lines.append(f"\t\t{proj_obj} /* Project object */ = {{")
    lines.append(f"\t\t\tisa = PBXProject;")
    lines.append(f"\t\t\tattributes = {{")
    lines.append(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append(f"\t\t\t\tLastSwiftUpdateCheck = 1540;")
    lines.append(f"\t\t\t\tLastUpgradeCheck = 1540;")
    lines.append(f"\t\t\t}};")
    lines.append(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_PROJECT} /* Build configuration list for PBXProject \"spacemap\" */;")
    lines.append(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    lines.append(f"\t\t\tdevelopmentRegion = en;")
    lines.append(f"\t\t\thasScannedForEncodings = 0;")
    lines.append(f"\t\t\tknownRegions = (en, Base);")
    lines.append(f"\t\t\tmainGroup = {ROOT_GROUP};")
    lines.append(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
    lines.append(f"\t\t\tprojectDirPath = \"\";")
    lines.append(f"\t\t\tprojectRoot = \"\";")
    lines.append(f"\t\t\ttargets = (")
    for tid in NATIVE_TARGETS:
        lines.append(f"\t\t\t\t{tid} /* {target_product_name(tid)} */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t}};")
    lines.append("/* End PBXProject section */")
    lines.append("")

    # PBXResourcesBuildPhase
    lines.append("/* Begin PBXResourcesBuildPhase section */")
    for tid in NATIVE_TARGETS:
        rphase = uid("phase", f"resources.{tid}")
        lines.append(f"\t\t{rphase} /* Resources */ = {{")
        lines.append(f"\t\t\tisa = PBXResourcesBuildPhase;")
        lines.append(f"\t\t\tbuildActionMask = 2147483647;")
        lines.append(f"\t\t\tfiles = (")
        lines.append(f"\t\t\t\t{APPICON_BUILD} /* AppIcon.icns in Resources */,")
        lines.append(f"\t\t\t\t{SPACEMAP_ICON_BUILD} /* spacemap.icns in Resources */,")
        lines.append(f"\t\t\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */,")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append(f"\t\t}};")
    lines.append("/* End PBXResourcesBuildPhase section */")
    lines.append("")

    # PBXSourcesBuildPhase
    lines.append("/* Begin PBXSourcesBuildPhase section */")
    for tid in NATIVE_TARGETS:
        sphase = uid("phase", f"sources.{tid}")
        lines.append(f"\t\t{sphase} /* Sources */ = {{")
        lines.append(f"\t\t\tisa = PBXSourcesBuildPhase;")
        lines.append(f"\t\t\tbuildActionMask = 2147483647;")
        lines.append(f"\t\t\tfiles = (")
        for f in SOURCE_FILES:
            lines.append(f"\t\t\t\t{BUILD_FILES[f]} /* {f} in Sources */,")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append(f"\t\t}};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")

    # XCBuildConfiguration
    lines.append("/* Begin XCBuildConfiguration section */")

    # Project-level configs
    for name in ["Debug", "Release"]:
        is_debug = name == "Debug"
        cid = uid("config", f"project.{name}")
        lines.append(f"\t\t{cid} /* {name} */ = {{")
        lines.append(f"\t\t\tisa = XCBuildConfiguration;")
        lines.append(f"\t\t\tbuildSettings = {{")
        lines.append(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        lines.append(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        lines.append(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = {'0' if is_debug else '3'};")
        lines.append(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;")
        lines.append(f"\t\t\t\tSDKROOT = macosx;")
        lines.append(f"\t\t\t\tSWIFT_VERSION = 5.0;")
        lines.append(f"\t\t\t}};")
        lines.append(f"\t\t\tname = {name};")
        lines.append(f"\t\t}};")

    # Target-level configs
    for tid in NATIVE_TARGETS:
        for name in ["Debug", "Release"]:
            is_debug = name == "Debug"
            cid = uid("config", f"{tid}.{name}")
            pname = target_product_name(tid)
            arch = arch_setting(tid)
            bid = uid("buildfile", f"swift.{tid}.{name}")

            lines.append(f"\t\t{cid} /* {name} */ = {{")
            lines.append(f"\t\t\tisa = XCBuildConfiguration;")
            lines.append(f"\t\t\tbuildSettings = {{")
            lines.append(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
            lines.append(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
            lines.append(f"\t\t\t\tCODE_SIGN_IDENTITY = \"-\";")
            lines.append(f"\t\t\t\tCODE_SIGN_STYLE = Manual;")
            lines.append(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
            lines.append(f"\t\t\t\tCOPY_PHASE_STRIP = {'NO' if is_debug else 'YES'};")
            lines.append(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = {'dwarf' if is_debug else 'dwarf-with-dsym'};")
            lines.append(f"\t\t\t\tENABLE_HARDENED_RUNTIME = NO;")
            lines.append(f"\t\t\t\tENABLE_TESTABILITY = {'YES' if is_debug else 'NO'};")
            lines.append(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = {'0' if is_debug else '3'};")
            lines.append(f"\t\t\t\tINFOPLIST_FILE = Sources/spacemap/Info.plist;")
            lines.append(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/../Frameworks\";")
            lines.append(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;")
            if arch:
                lines.append(f"\t\t\t\tARCHS = \"{arch}\";")
            lines.append(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jsheffie.spacemap;")
            lines.append(f"\t\t\t\tPRODUCT_NAME = {pname};")
            lines.append(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = {'DEBUG' if is_debug else 'RELEASE'};")
            lines.append(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = {'-Onone' if is_debug else '-O'};")
            lines.append(f"\t\t\t\tSWIFT_VERSION = 5.0;")
            lines.append(f"\t\t\t\tVERSIONING_SYSTEM = \"apple-generic\";")
            lines.append(f"\t\t\t\tMARKETING_VERSION = 1.0.0;")
            lines.append(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
            lines.append(f"\t\t\t}};")
            lines.append(f"\t\t\tname = {name};")
            lines.append(f"\t\t}};")

    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")

    # XCConfigurationList
    lines.append("/* Begin XCConfigurationList section */")

    # Project config list
    debug_proj = uid("config", "project.Debug")
    release_proj = uid("config", "project.Release")
    lines.append(f"\t\t{CONFIG_LIST_PROJECT} /* Build configuration list for PBXProject \"spacemap\" */ = {{")
    lines.append(f"\t\t\tisa = XCConfigurationList;")
    lines.append(f"\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{debug_proj} /* Debug */,")
    lines.append(f"\t\t\t\t{release_proj} /* Release */,")
    lines.append(f"\t\t\t);")
    lines.append(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append(f"\t\t\tdefaultConfigurationName = Release;")
    lines.append(f"\t\t}};")

    # Target config lists
    for tid in NATIVE_TARGETS:
        pname = target_product_name(tid)
        clist = uid("configlist", f"target.{tid}")
        debug_cid = uid("config", f"{tid}.Debug")
        release_cid = uid("config", f"{tid}.Release")
        lines.append(f"\t\t{clist} /* Build configuration list for PBXNativeTarget \"{pname}\" */ = {{")
        lines.append(f"\t\t\tisa = XCConfigurationList;")
        lines.append(f"\t\t\tbuildConfigurations = (")
        lines.append(f"\t\t\t\t{debug_cid} /* Debug */,")
        lines.append(f"\t\t\t\t{release_cid} /* Release */,")
        lines.append(f"\t\t\t);")
        lines.append(f"\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append(f"\t\t\tdefaultConfigurationName = Release;")
        lines.append(f"\t\t}};")

    lines.append("/* End XCConfigurationList section */")
    lines.append("")

    lines.append("\t};")
    lines.append(f"\trootObject = {proj_obj} /* Project object */;")
    lines.append("}")

    with open(PBXPROJ_PATH, "w") as f:
        f.write("\n".join(lines))

    print(f"Generated {PBXPROJ_PATH}")
    print(f"Targets:")
    print(f"  spacemap         — default (host architecture)")
    print(f"  spacemap-arm64   — Apple Silicon only")
    print(f"  spacemap-x86_64  — Intel only")
    print(f"  spacemap-universal — fat binary (arm64 + x86_64)")
    print(f"\nOpen with: open spacemap.xcodeproj")


if __name__ == "__main__":
    generate()
