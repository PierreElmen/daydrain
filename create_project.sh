#!/bin/bash
mkdir -p DayDrain.xcodeproj
cd DayDrain.xcodeproj
cat > project.pbxproj << 'PBXPROJ'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		AA1111111111111111111111 /* DayDrainApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB1111111111111111111111 /* DayDrainApp.swift */; };
		AA2222222222222222222222 /* DayManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB2222222222222222222222 /* DayManager.swift */; };
		AA3333333333333333333333 /* StatusBarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB3333333333333333333333 /* StatusBarView.swift */; };
		AA4444444444444444444444 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB4444444444444444444444 /* SettingsView.swift */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		CC1111111111111111111111 /* DayDrain.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DayDrain.app; sourceTree = BUILT_PRODUCTS_DIR; };
		BB1111111111111111111111 /* DayDrainApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DayDrainApp.swift; sourceTree = "<group>"; };
		BB2222222222222222222222 /* DayManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DayManager.swift; sourceTree = "<group>"; };
		BB3333333333333333333333 /* StatusBarView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StatusBarView.swift; sourceTree = "<group>"; };
		BB4444444444444444444444 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		DD1111111111111111111111 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		EE1111111111111111111111 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		FF1111111111111111111111 = {
			isa = PBXGroup;
			children = (
GG1111111111111111111111 /* DayDrain */,
HH1111111111111111111111 /* Products */,
);
			sourceTree = "<group>";
		};
		HH1111111111111111111111 /* Products */ = {
			isa = PBXGroup;
			children = (
CC1111111111111111111111 /* DayDrain.app */,
);
			name = Products;
			sourceTree = "<group>";
		};
		GG1111111111111111111111 /* DayDrain */ = {
			isa = PBXGroup;
			children = (
BB1111111111111111111111 /* DayDrainApp.swift */,
BB2222222222222222222222 /* DayManager.swift */,
BB3333333333333333333333 /* StatusBarView.swift */,
BB4444444444444444444444 /* SettingsView.swift */,
DD1111111111111111111111 /* Info.plist */,
);
			path = DayDrain;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		II1111111111111111111111 /* DayDrain */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = JJ1111111111111111111111 /* Build configuration list for PBXNativeTarget "DayDrain" */;
			buildPhases = (
KK1111111111111111111111 /* Sources */,
EE1111111111111111111111 /* Frameworks */,
LL1111111111111111111111 /* Resources */,
);
			buildRules = (
);
			dependencies = (
);
			name = DayDrain;
			productName = DayDrain;
			productReference = CC1111111111111111111111 /* DayDrain.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		MM1111111111111111111111 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					II1111111111111111111111 = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = NN1111111111111111111111 /* Build configuration list for PBXProject "DayDrain" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
en,
Base,
);
			mainGroup = FF1111111111111111111111;
			productRefGroup = HH1111111111111111111111 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
II1111111111111111111111 /* DayDrain */,
);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		LL1111111111111111111111 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		KK1111111111111111111111 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
AA1111111111111111111111 /* DayDrainApp.swift in Sources */,
AA2222222222222222222222 /* DayManager.swift in Sources */,
AA3333333333333333333333 /* StatusBarView.swift in Sources */,
AA4444444444444444444444 /* SettingsView.swift in Sources */,
);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		OO1111111111111111111111 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
"DEBUG=1",
"$(inherited)",
);
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		PP1111111111111111111111 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = Release;
		};
		QQ1111111111111111111111 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = DayDrain/DayDrain.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"DayDrain/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = DayDrain/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
"$(inherited)",
"@executable_path/../Frameworks",
);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.pierreelmen.DayDrain;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		RR1111111111111111111111 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = DayDrain/DayDrain.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"DayDrain/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = DayDrain/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
"$(inherited)",
"@executable_path/../Frameworks",
);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.pierreelmen.DayDrain;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		NN1111111111111111111111 /* Build configuration list for PBXProject "DayDrain" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
OO1111111111111111111111 /* Debug */,
PP1111111111111111111111 /* Release */,
);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		JJ1111111111111111111111 /* Build configuration list for PBXNativeTarget "DayDrain" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
QQ1111111111111111111111 /* Debug */,
RR1111111111111111111111 /* Release */,
);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = MM1111111111111111111111 /* Project object */;
}
PBXPROJ
