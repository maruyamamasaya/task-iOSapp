# Widget signing setup

In Xcode, enable **App Groups** for both `CalendarTaskApp` and `CalendarTaskWidget` and select the value of the shared `APP_GROUP_IDENTIFIER` build setting. The checked-in entitlements reference that build setting rather than duplicating the identifier in source code. A paid Apple Developer team/provisioning profile is required for device distribution.
