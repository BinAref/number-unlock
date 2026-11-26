/// A long computation that can be advanced a slice at a time.
///
/// Hints, rescue analysis and board generation implement this, so the
/// app can run them in small slices between frames (the web has no
/// background isolates) while tools and tests simply run them to the end.
abstract interface class ComputeJob<T> {
  /// Performs up to [units] of work. Returns true once finished.
  bool step(int units);

  /// The outcome; only meaningful once [step] returned true.
  T get result;
}

/// Runs [job] synchronously until it finishes.
T runToCompletion<T>(ComputeJob<T> job, {int slice = 1 << 14}) {
  while (!job.step(slice)) {}
  return job.result;
}
