library hop_runner.git;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:meta/meta.dart';
import 'package:html5lib/dom.dart';
import 'package:bot/bot.dart';
import 'package:bot/bot_git.dart';
import 'package:bot/bot_io.dart';
import 'package:bot/hop.dart';

const _docsBranch = 'gh-pages';
const _ghPagesBranch = 'x-gh-pages';
const _docsTagPrefix = 'docs-v';
const _latestCommit = 'latest-commit';
const _latestRelease = 'latest-pub';

Task gitGitDocExperimentTask() {

  return new Task.async((ctx) {

    final dir = new Directory.current();

    GitDir gd;
    Map<String, String> docTreeShas;
    String newTreeSha;
    String newCommitSha;
    String commitMsg = 'Yay!';

    return GitDir.fromExisting(dir.path)
        .then((GitDir value) {

          gd = value;

          return _getTreeShas(gd);
        })
        .then((Map<String, String> values) {
          docTreeShas = values;

          return _hashBlob(_getRootPage(docTreeShas), write: true);
        })
        .then((String indexFileSha) {
          print(indexFileSha);

          final lines = new List<TreeEntry>();

          docTreeShas.forEach((name, treeSha) {
            final te = new TreeEntry('040000', 'tree', treeSha, name);
            lines.add(te);
          });

          lines.add(new TreeEntry('100644', 'blob', indexFileSha, 'index.html'));

          final treeString = lines.join('\n');

          return Process.run('bash', ['-c', 'git mktree <<< "$treeString"']);
        })
        .then((ProcessResult pr) {

          newTreeSha = pr.stdout.trim();
          assert(Git.isValidSha(newTreeSha));

          return gd.createOrUpdateBranch(_ghPagesBranch, newTreeSha, commitMsg);
        })
        .then((String newCommitSha) {

          if(newCommitSha == null) {
            ctx.info('Nothing updated');
          } else {
            ctx.info('Branch $_ghPagesBranch updated to commit $newCommitSha');
          }

          return true;
        });
  });
}

String _getRootPage(Map<String, String> items) {
  final nameList = items.keys.toList()
      ..sort();

  final doc = new Document.html(_bodyContent);

  final table = doc.query('tbody');

  for(final name in nameList) {
    final row = new Element.tag('tr');

    var td = new Element.tag('td');

    var link = new Element.tag('a')
      ..innerHtml = name
      ..attributes['href'] = name;

    td.children.add(link);

    row.children.add(td);

    table.children.add(row);
    table.insertBefore(new Text('\n'), null);
  }

  return doc.outerHtml;
}

const _bodyContent =
'''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>BOT Documentation</title>
  </head>
  <body>
    <table><tbody>
    </tbody></table>
  </body>
</html>
''';

Future<String> _hashBlob(String contents, {bool write: false} ) {
  final args = ['git', 'hash-object', '-t', 'blob'];

  if(write) {
    args.add('-w');
  }

  // using single quotes to write to standard output
  // make sure all instances of single quote are escaped
  contents = contents.replaceAll("'", r"'\''");

  args.addAll(['--stdin', '<<<', "'$contents'"]);
  final bashArgs = ['-c', args.join(' ')];
  return Process.run('bash', bashArgs)
      .then((ProcessResult pr) {
        _throwIfProcessFailed(pr, 'bash', bashArgs);
        return pr.stdout.trim();
      });
}

/*
 * Copied from bot_git - git.dart
 * TODO: a nice util in bot_io?
 */
void _throwIfProcessFailed(ProcessResult pr, String process, List<String> args) {
  assert(pr != null);
  if(pr.exitCode != 0) {

    final message =
'''

stdout:
${pr.stdout}
stderr:
${pr.stderr}''';

throw new ProcessException('git', args, message, pr.exitCode);
  }
}

// key: name of tree
// value: sha of tree
Future<Map<String, String>> _getTreeShas(GitDir gd) {

  final tagRefs = new List<Tag>();

  final docCommitShas = new Map<String, String>();
  final docCommits = new Map<String, Commit>();
  final versions = new Map<Version, String>();

  return gd.getTags()
      .then((List value) {

        tagRefs.addAll(value);

        for(final tagRef in tagRefs) {


          if(tagRef.tag.startsWith(_docsTagPrefix)) {
            var name = tagRef.tag.substring(_docsTagPrefix.length);

            final version = new Version.parse(name);

            name = 'v'.concat(name)
                .replaceAll('.', '_')
                .replaceAll('+', '_');

            versions[version] = name;
            docCommitShas[name] = tagRef.objectSha;

          }
        }

        //
        // Now figure out the last released version
        //
        final primaryVersion = Version.primary(versions.keys.toList());

        if(primaryVersion != null) {
          final primaryName = versions[primaryVersion];
          docCommitShas[_latestRelease] = docCommitShas[primaryName];
        }

        return gd.getBranchReference(_docsBranch);
      })
      .then((BranchReference br) {

        assert(!docCommitShas.containsKey(_latestCommit));
        docCommitShas[_latestCommit] = br.sha;

        return Future.forEach(docCommitShas.keys, (String key) {
          final sha = docCommitShas[key];
          return gd.getCommit(sha)
              .then((Commit commit) {
                docCommits[key] = commit;
              });
        });
      })
      .then((_) {
        return $(docCommits.keys).toMap((String name) => docCommits[name].treeSha);
      });
}

// Stolen without shame from Dart - at rev 19799
// dart/utils/pub/version.dart

/// Regex that matches a version number at the beginning of a string.
final _START_VERSION = new RegExp(
    r'^'                                        // Start at beginning.
    r'(\d+).(\d+).(\d+)'                        // Version number.
    r'(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?'    // Pre-release.
    r'(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?'); // Build.

/// Like [_START_VERSION] but matches the entire string.
final _COMPLETE_VERSION = new RegExp("${_START_VERSION.pattern}\$");

/// A parsed semantic version number.
class Version implements Comparable<Version> {
  /// No released version: i.e. "0.0.0".
  static Version get none => new Version(0, 0, 0);
  /// The major version number: "1" in "1.2.3".
  final int major;

  /// The minor version number: "2" in "1.2.3".
  final int minor;

  /// The patch version number: "3" in "1.2.3".
  final int patch;

  /// The pre-release identifier: "foo" in "1.2.3-foo". May be `null`.
  final String preRelease;

  /// The build identifier: "foo" in "1.2.3+foo". May be `null`.
  final String build;

  /// Creates a new [Version] object.
  Version(this.major, this.minor, this.patch, {String pre, this.build})
    : preRelease = pre {
    if (major < 0) throw new ArgumentError(
        'Major version must be non-negative.');
    if (minor < 0) throw new ArgumentError(
        'Minor version must be non-negative.');
    if (patch < 0) throw new ArgumentError(
        'Patch version must be non-negative.');
  }

  /// Creates a new [Version] by parsing [text].
  factory Version.parse(String text) {
    final match = _COMPLETE_VERSION.firstMatch(text);
    if (match == null) {
      throw new FormatException('Could not parse "$text".');
    }

    try {
      int major = int.parse(match[1]);
      int minor = int.parse(match[2]);
      int patch = int.parse(match[3]);

      String preRelease = match[5];
      String build = match[8];

      return new Version(major, minor, patch, pre: preRelease, build: build);
    } on FormatException catch (ex) {
      throw new FormatException('Could not parse "$text".');
    }
  }

  /// Returns the primary version out of a list of candidates. This is the
  /// highest-numbered stable (non-prerelease) version. If there are no stable
  /// versions, it's just the highest-numbered version.
  static Version primary(List<Version> versions) {
    var primary;
    for (var version in versions) {
      if (primary == null || (!version.isPreRelease && primary.isPreRelease) ||
          (version.isPreRelease == primary.isPreRelease && version > primary)) {
        primary = version;
      }
    }
    return primary;
  }

  bool operator ==(other) {
    if (other is! Version) return false;
    return compareTo(other) == 0;
  }

  bool operator <(Version other) => compareTo(other) < 0;
  bool operator >(Version other) => compareTo(other) > 0;
  bool operator <=(Version other) => compareTo(other) <= 0;
  bool operator >=(Version other) => compareTo(other) >= 0;

  bool get isAny => false;
  bool get isEmpty => false;

  /// Whether or not this is a pre-release version.
  bool get isPreRelease => preRelease != null;

  /// Tests if [other] matches this version exactly.
  bool allows(Version other) => this == other;

  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    if (preRelease != other.preRelease) {
      // Pre-releases always come before no pre-release string.
      if (preRelease == null) return 1;
      if (other.preRelease == null) return -1;

      return _compareStrings(preRelease, other.preRelease);
    }

    if (build != other.build) {
      // Builds always come after no build string.
      if (build == null) return -1;
      if (other.build == null) return 1;

      return _compareStrings(build, other.build);
    }

    return 0;
  }

  int get hashCode => toString().hashCode;

  String toString() {
    var buffer = new StringBuffer();
    buffer.write('$major.$minor.$patch');
    if (preRelease != null) buffer.write('-$preRelease');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }

  /// Compares the string part of two versions. This is used for the pre-release
  /// and build version parts. This follows Rule 12. of the Semantic Versioning
  /// spec.
  int _compareStrings(String a, String b) {
    var aParts = _splitParts(a);
    var bParts = _splitParts(b);

    for (int i = 0; i < max(aParts.length, bParts.length); i++) {
      var aPart = (i < aParts.length) ? aParts[i] : null;
      var bPart = (i < bParts.length) ? bParts[i] : null;

      if (aPart != bPart) {
        // Missing parts come before present ones.
        if (aPart == null) return -1;
        if (bPart == null) return 1;

        if (aPart is int) {
          if (bPart is int) {
            // Compare two numbers.
            return aPart.compareTo(bPart);
          } else {
            // Numbers come before strings.
            return -1;
          }
        } else {
          if (bPart is int) {
            // Strings come after numbers.
            return 1;
          } else {
            // Compare two strings.
            return aPart.compareTo(bPart);
          }
        }
      }
    }
  }

  /// Splits a string of dot-delimited identifiers into their component parts.
  /// Identifiers that are numeric are converted to numbers.
  List _splitParts(String text) {
    return text.split('.').map((part) {
      try {
        return int.parse(part);
      } on FormatException catch (ex) {
        // Not a number.
        return part;
      }
    }).toList();
  }
}
