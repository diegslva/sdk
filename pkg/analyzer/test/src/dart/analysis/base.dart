// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/dart/analysis/status.dart';
import 'package:analyzer/src/file_system/file_system.dart';
import 'package:analyzer/src/generated/engine.dart' show AnalysisOptionsImpl;
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/source/package_map_resolver.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:front_end/src/api_prototype/byte_store.dart';
import 'package:front_end/src/base/performance_logger.dart';
import 'package:test/test.dart';

import '../../context/mock_sdk.dart';

/**
 * Finds an [Element] with the given [name].
 */
Element findChildElement(Element root, String name, [ElementKind kind]) {
  Element result = null;
  root.accept(new _ElementVisitorFunctionWrapper((Element element) {
    if (element.name != name) {
      return;
    }
    if (kind != null && element.kind != kind) {
      return;
    }
    result = element;
  }));
  return result;
}

typedef bool Predicate<E>(E argument);

/**
 * A function to be called for every [Element].
 */
typedef void _ElementVisitorFunction(Element element);

class BaseAnalysisDriverTest {
  final MemoryResourceProvider provider = new MemoryResourceProvider();
  DartSdk sdk;
  final ByteStore byteStore = new MemoryByteStore();
  final FileContentOverlay contentOverlay = new FileContentOverlay();

  final StringBuffer logBuffer = new StringBuffer();
  PerformanceLog logger;

  final _GeneratedUriResolverMock generatedUriResolver =
      new _GeneratedUriResolverMock();
  AnalysisDriverScheduler scheduler;
  AnalysisDriver driver;
  final List<AnalysisStatus> allStatuses = <AnalysisStatus>[];
  final List<AnalysisResult> allResults = <AnalysisResult>[];
  final List<ExceptionResult> allExceptions = <ExceptionResult>[];

  String testProject;
  String testFile;
  String testCode;

  /**
   * Whether to enable the Dart 2.0 Common Front End.
   */
  bool useCFE = false;

  bool get disableChangesAndCacheAllResults => false;

  void addTestFile(String content, {bool priority: false}) {
    testCode = content;
    provider.newFile(testFile, content);
    driver.addFile(testFile);
    if (priority) {
      driver.priorityFiles = [testFile];
    }
  }

  AnalysisDriver createAnalysisDriver({SummaryDataStore externalSummaries}) {
    return new AnalysisDriver(
        scheduler,
        logger,
        provider,
        byteStore,
        contentOverlay,
        null,
        new SourceFactory([
          new DartUriResolver(sdk),
          generatedUriResolver,
          new PackageMapUriResolver(provider, <String, List<Folder>>{
            'test': [provider.getFolder(testProject)],
            'aaa': [provider.getFolder(_p('/aaa/lib'))],
            'bbb': [provider.getFolder(_p('/bbb/lib'))],
          }),
          new ResourceUriResolver(provider)
        ], null, provider),
        createAnalysisOptions(),
        disableChangesAndCacheAllResults: disableChangesAndCacheAllResults,
        externalSummaries: externalSummaries,
        enableKernelDriver: useCFE);
  }

  AnalysisOptionsImpl createAnalysisOptions() => new AnalysisOptionsImpl()
    ..strongMode = true
    ..useFastaParser = useCFE;

  int findOffset(String search) {
    int offset = testCode.indexOf(search);
    if (offset < 0) {
      fail("Did not find '$search' in\n$testCode");
    }
    return offset;
  }

  int getLeadingIdentifierLength(String search) {
    int length = 0;
    while (length < search.length) {
      int c = search.codeUnitAt(length);
      if (c >= 'a'.codeUnitAt(0) && c <= 'z'.codeUnitAt(0)) {
        length++;
        continue;
      }
      if (c >= 'A'.codeUnitAt(0) && c <= 'Z'.codeUnitAt(0)) {
        length++;
        continue;
      }
      if (c >= '0'.codeUnitAt(0) && c <= '9'.codeUnitAt(0)) {
        length++;
        continue;
      }
      break;
    }
    return length;
  }

  void setUp() {
    sdk = new MockSdk(resourceProvider: provider);
    testProject = _p('/test/lib');
    testFile = _p('/test/lib/test.dart');
    logger = new PerformanceLog(logBuffer);
    scheduler = new AnalysisDriverScheduler(logger);
    driver = createAnalysisDriver();
    scheduler.start();
    scheduler.status.listen(allStatuses.add);
    driver.results.listen(allResults.add);
    driver.exceptions.listen(allExceptions.add);
  }

  void tearDown() {}

  String _p(String path) => provider.convertPath(path);
}

/**
 * Wraps an [_ElementVisitorFunction] into a [GeneralizingElementVisitor].
 */
class _ElementVisitorFunctionWrapper extends GeneralizingElementVisitor {
  final _ElementVisitorFunction function;

  _ElementVisitorFunctionWrapper(this.function);

  visitElement(Element element) {
    function(element);
    super.visitElement(element);
  }
}

class _GeneratedUriResolverMock implements UriResolver {
  Source Function(Uri, Uri) resolveAbsoluteFunction;

  Uri Function(Source) restoreAbsoluteFunction;

  @override
  noSuchMethod(Invocation invocation) {
    throw new StateError('Unexpected invocation of ${invocation.memberName}');
  }

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    if (resolveAbsoluteFunction != null) {
      return resolveAbsoluteFunction(uri, actualUri);
    }
    return null;
  }

  @override
  Uri restoreAbsolute(Source source) {
    if (restoreAbsoluteFunction != null) {
      return restoreAbsoluteFunction(source);
    }
    return null;
  }
}
