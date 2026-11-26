import 'dart:async';

import '../core/jobs/compute_job.dart';

/// Runs heavy jobs (hints, rescue checks, endless boards) in short
/// slices between frames, so animations stay smooth on every platform —
/// including the web, which has no background isolates.
class ComputeScheduler {
  ComputeScheduler({this.slice = const Duration(milliseconds: 7)});

  final Duration slice;

  Future<T> run<T>(ComputeJob<T> job, {int units = 400}) async {
    final sw = Stopwatch();
    while (true) {
      sw
        ..reset()
        ..start();
      while (sw.elapsed < slice) {
        if (job.step(units)) return job.result;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }
}
