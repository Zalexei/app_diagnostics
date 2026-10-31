import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_diagnostics/src/ios_messages.g.dart' as ios;
import 'package:app_diagnostics/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goes through the real EventChannel: several Dart listeners must share one
/// native subscription instead of taking the channel from each other.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Records native listen/cancel calls on [channel]; returns a way to emit.
  (List<String>, Future<void> Function(Object?)) fakeNative(
    String channel,
    MethodCodec codec,
  ) {
    final calls = <String>[];
    messenger.setMockMessageHandler(channel, (message) async {
      calls.add(codec.decodeMethodCall(message).method);
      return codec.encodeSuccessEnvelope(null);
    });
    Future<void> emit(Object? event) async {
      await messenger.handlePlatformMessage(
        channel,
        codec.encodeSuccessEnvelope(event),
        (_) {},
      );
      await pumpEventQueue();
    }

    return (calls, emit);
  }

  test('profiling results reach every listener', () async {
    const channel =
        'dev.flutter.pigeon.app_diagnostics.AndroidDiagnosticsEventApi.profilingResults';
    final (calls, emit) = fakeNative(channel, pigeonMethodCodec);
    AndroidDiagnosticsPlatform.instance = PigeonAndroidDiagnostics();

    final a = <ProfilingResult>[];
    final b = <ProfilingResult>[];
    final subA = AndroidDiagnostics.profilingResults.listen(a.add);
    final subB = AndroidDiagnostics.profilingResults.listen(b.add);
    await pumpEventQueue();
    await emit(
      ProfilingResultMessage(
        errorCode: 0,
        resultFilePath: '/f',
        triggerType: 2,
      ),
    );
    expect((a.length, b.length), (1, 1));

    await subB.cancel();
    await emit(ProfilingResultMessage(errorCode: 0, triggerType: 0));
    expect(a, hasLength(2));
    expect(calls, ['listen']);

    await subA.cancel();
    await pumpEventQueue();
    expect(calls, ['listen', 'cancel']);
  });

  test('MetricKit arrivals reach every listener', () async {
    const channel =
        'dev.flutter.pigeon.app_diagnostics.IosDiagnosticsEventApi.reportsArrived';
    final (calls, emit) = fakeNative(channel, ios.pigeonMethodCodec);
    IosDiagnosticsPlatform.instance = PigeonIosDiagnostics();

    final a = <MetricKitReportKind>[];
    final b = <MetricKitReportKind>[];
    final subA = IosDiagnostics.reportsArrived.listen(a.add);
    final subB = IosDiagnostics.reportsArrived.listen(b.add);
    await pumpEventQueue();
    await emit(0);
    expect(a, [MetricKitReportKind.diagnostic]);
    expect(b, [MetricKitReportKind.diagnostic]);
    expect(calls, ['listen']);
    await subA.cancel();
    await subB.cancel();
  });
}
