import SwiftUI

#if DEBUG || REDLAMP_PROFILING
    if DebugPhotosCensus.isRequested(LaunchArguments.all) {
        DebugPhotosCensus.run(arguments: LaunchArguments.all)
    }
#endif
RedlampApp.main()
