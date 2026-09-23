# Android, Gradle, and Flutter integration

Supported metadata contract: bounded UTF-8 AVD INI data with unique keys and fixed field limits. Missing runtime instance tokens remain unknown. Project Gradle markers and project-local `build`/`.gradle` directories are treated as data; wrappers and project scripts are never executed.

SDK, NDK, AVD, and global Gradle storage are report-only. AVD names do not identify running instances. Custom cache paths require separately approved roots. No `gradle --stop`, wrapper execution, guessed `adb` kill, SDK deletion, or emulator mutation is allowed. No supported producer identity/completion protocol is currently registered.
