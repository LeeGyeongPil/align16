/// Programmatic access to align16's checks.
///
/// This API is not stable before 1.0; the command line is the supported
/// interface.
library;

export 'src/allowlist.dart' show Allowlist;
export 'src/artifact.dart' show ArtifactKind, InputError, LibraryFile;
export 'src/attribution.dart' show Confidence, Owner;
export 'src/checker.dart'
    show CheckOptions, PackageFinding, Report, Summary, checkArtifact;
export 'src/elf.dart' show ElfInfo, parseElf;
export 'src/verdict.dart' show CheckId, CheckResult, LibraryVerdict, Status;
