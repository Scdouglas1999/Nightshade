/// Timing-attack-resistant string comparison.
///
/// Why: Plain `Map[]` lookup or `==` comparison is observable on the network.
/// An attacker on a slow link can extract bearer tokens character-by-character
/// by measuring response timings. This loop runs in constant time relative to
/// the input length.
///
/// Both inputs must be the same length and ASCII-encoded (which is true for
/// our hex/alphanumeric tokens). For UTF-16 strings, code units are XORed to
/// avoid materializing both byte arrays. The early-out on length mismatch is
/// acceptable because token length is not secret in our threat model.
library;

bool constantTimeCompareStrings(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}
