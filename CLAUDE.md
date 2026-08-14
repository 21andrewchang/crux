# CLAUDE.md

## Reinstall after every change

After ANY code change in this project, rebuild and reinstall the app on Andrew's iPhone ("andrew", device id `B912DCD3-C247-58B4-98AA-A014D4C521B4`) without being asked:

```sh
xcodebuild -project Climb.xcodeproj -scheme Climb \
  -destination 'id=B912DCD3-C247-58B4-98AA-A014D4C521B4' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device B912DCD3-C247-58B4-98AA-A014D4C521B4 \
  ~/Library/Developer/Xcode/DerivedData/Climb-*/Build/Products/Debug-iphoneos/Crux.app
xcrun devicectl device process launch --device B912DCD3-C247-58B4-98AA-A014D4C521B4 com.andrewchang.Crux
```

Batch a multi-file edit into one reinstall at the end of the turn, not one per file. If the device is unavailable, say so and skip the install rather than failing the whole task.
