// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

/// Stateless single-pass RFC 4648 Base64 encoder and decoder.
library;

import 'package:flutter/foundation.dart';

/// Lookup table mapping ASCII code units (`0..127`) to 6-bit Base64 sextets (`0..63`), or `-1` for invalid characters.
const List<int> _decodeTable = <int>[
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 00-0F
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 10-1F
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, // 20-2F
  52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, // 30-3F
  -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, // 40-4F (A-O)
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, // 50-5F (P-Z)
  -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, // 60-6F (a-o)
  41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, // 70-7F (p-z)
];

/// Lookup table mapping 6-bit Base64 sextets (`0..63`) to canonical RFC 4648 ASCII code units.
const List<int> _encodeTable = <int>[
  0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, // A-H
  0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, // I-P
  0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, // Q-X
  0x59, 0x5A, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, // Y-Z, a-f
  0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, // g-n
  0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, // o-v
  0x77, 0x78, 0x79, 0x7A, 0x30, 0x31, 0x32, 0x33, // w-z, 0-3
  0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x2B, 0x2F, // 4-9, +, /
];

/// Error categories thrown by [Base64Service] during encoding or decoding.
enum Base64ErrorKind {
  /// Input byte length or decoded output byte length exceeds [Base64Service.maxInputBytes].
  inputTooLarge,

  /// Input contains a code unit outside the RFC 4648 Base64 alphabet (`A-Z`, `a-z`, `0-9`, `+`, `/`) or a byte outside `0x00..0xFF`.
  invalidCharacter,

  /// Encoded string length is not a multiple of 4 characters.
  invalidLength,

  /// Padding character (`=`) appears in a non-final quantum or an invalid position within the final quantum.
  invalidPadding,

  /// Non-zero trailing padding bits violate RFC 4648 Section 3.5 canonical encoding rules.
  nonCanonicalPaddingBits,
}

/// Typed exception thrown when [Base64Service] encoding or decoding fails.
@immutable
class Base64Exception implements Exception {
  /// Creates a [Base64Exception] with [kind] and [message].
  const Base64Exception(this.kind, this.message);

  /// Specific Base64 validation or bounds error category.
  final Base64ErrorKind kind;

  /// Human-readable error description.
  final String message;

  @override
  String toString() => message;
}

/// Stateless, bounded, single-pass RFC 4648 Base64 encoder and decoder.
@immutable
class Base64Service {
  /// Creates a [Base64Service] with an explicit [maxInputBytes] resource bound.
  const Base64Service({this.maxInputBytes = defaultMaxInputBytes});

  /// Default maximum allowed input or decoded payload size in bytes (1 MiB).
  static const int defaultMaxInputBytes = 1048576;

  /// ASCII code unit for the Base64 padding character (`=`).
  static const int _equalsCodeUnit = 0x3D;

  /// Maximum allowed raw byte count for encoding and decoding operations.
  final int maxInputBytes;

  /// Decodes a canonical RFC 4648 Base64 string [encoded] into a [Uint8List] in a single pass.
  Uint8List decodeBytes(String encoded) {
    final length = encoded.length;
    final maxEncodedLength = maxInputBytes <= 0
        ? 0
        : ((maxInputBytes + 2) ~/ 3) * 4;
    if (maxInputBytes < 0 || length > maxEncodedLength) {
      throw const Base64Exception(
        Base64ErrorKind.inputTooLarge,
        'Decoded Base64 payload exceeds maximum allowed byte length.',
      );
    }
    if (length == 0) {
      return Uint8List(0);
    }
    if ((length & 3) != 0) {
      throw const Base64Exception(
        Base64ErrorKind.invalidLength,
        'Base64 input length must be a multiple of 4.',
      );
    }

    final decodedLength = _resolveDecodedLength(encoded, length);
    if (decodedLength > maxInputBytes) {
      throw const Base64Exception(
        Base64ErrorKind.inputTooLarge,
        'Decoded Base64 payload exceeds maximum allowed byte length.',
      );
    }

    final output = Uint8List(decodedLength);
    final fullQuadsEnd = (encoded.codeUnitAt(length - 1) == _equalsCodeUnit)
        ? length - 4
        : length;
    var outputIndex = 0;

    for (var i = 0; i < fullQuadsEnd; i += 4) {
      outputIndex = _decodeFullQuad(encoded, i, output, outputIndex);
    }
    if (fullQuadsEnd < length) {
      _decodePaddedFinalQuad(encoded, fullQuadsEnd, output, outputIndex);
    }
    return output;
  }

  /// Encodes [bytes] into a canonical RFC 4648 Base64 ASCII string in a single pass.
  String encodeBytes(List<int> bytes) {
    final inputLength = bytes.length;
    if (inputLength > maxInputBytes) {
      throw const Base64Exception(
        Base64ErrorKind.inputTooLarge,
        'Input byte length exceeds maximum allowed Base64 limit.',
      );
    }
    if (inputLength == 0) {
      return '';
    }

    final outputLength = ((inputLength + 2) ~/ 3) * 4;
    final output = Uint8List(outputLength);
    final fullTripletsEnd = inputLength - (inputLength % 3);
    var outputIndex = 0;

    for (var i = 0; i < fullTripletsEnd; i += 3) {
      outputIndex = _encodeFullTriplet(bytes, i, output, outputIndex);
    }
    if (fullTripletsEnd < inputLength) {
      _encodeRemainder(
        bytes,
        fullTripletsEnd,
        inputLength,
        output,
        outputIndex,
      );
    }
    return String.fromCharCodes(output);
  }

  /// Decodes a 4-character non-padded Base64 quantum at [offset] into 3 bytes in [output].
  static int _decodeFullQuad(
    String encoded,
    int offset,
    Uint8List output,
    int outputIndex,
  ) {
    final sextet0 = _decodeSextet(encoded.codeUnitAt(offset));
    final sextet1 = _decodeSextet(encoded.codeUnitAt(offset + 1));
    final sextet2 = _decodeSextet(encoded.codeUnitAt(offset + 2));
    final sextet3 = _decodeSextet(encoded.codeUnitAt(offset + 3));
    final combined =
        (sextet0 << 18) | (sextet1 << 12) | (sextet2 << 6) | sextet3;

    output[outputIndex] = (combined >> 16) & 0xFF;
    output[outputIndex + 1] = (combined >> 8) & 0xFF;
    output[outputIndex + 2] = combined & 0xFF;
    return outputIndex + 3;
  }

  /// Decodes the final 4-character padded Base64 quantum at [offset] and verifies canonical zero padding bits.
  static void _decodePaddedFinalQuad(
    String encoded,
    int offset,
    Uint8List output,
    int outputIndex,
  ) {
    final sextet0 = _decodeSextet(encoded.codeUnitAt(offset));
    final sextet1 = _decodeSextet(encoded.codeUnitAt(offset + 1));
    final code2 = encoded.codeUnitAt(offset + 2);

    if (code2 == _equalsCodeUnit) {
      if ((sextet1 & 0x0F) != 0) {
        throw const Base64Exception(
          Base64ErrorKind.nonCanonicalPaddingBits,
          'Non-zero trailing bits in 2-pad Base64 quantum.',
        );
      }
      output[outputIndex] = ((sextet0 << 2) | (sextet1 >> 4)) & 0xFF;
      return;
    }

    final sextet2 = _decodeSextet(code2);
    if ((sextet2 & 0x03) != 0) {
      throw const Base64Exception(
        Base64ErrorKind.nonCanonicalPaddingBits,
        'Non-zero trailing bits in 1-pad Base64 quantum.',
      );
    }
    output[outputIndex] = ((sextet0 << 2) | (sextet1 >> 4)) & 0xFF;
    output[outputIndex + 1] = ((sextet1 << 4) | (sextet2 >> 2)) & 0xFF;
  }

  /// Maps a single ASCII [codeUnit] to its 6-bit Base64 sextet or throws [Base64Exception].
  static int _decodeSextet(int codeUnit) {
    if (codeUnit == _equalsCodeUnit) {
      throw const Base64Exception(
        Base64ErrorKind.invalidPadding,
        'Unexpected Base64 padding character.',
      );
    }
    if (codeUnit < 0 || codeUnit >= 128) {
      throw const Base64Exception(
        Base64ErrorKind.invalidCharacter,
        'Non-ASCII character in Base64 input.',
      );
    }
    final sextet = _decodeTable[codeUnit];
    if (sextet < 0) {
      throw const Base64Exception(
        Base64ErrorKind.invalidCharacter,
        'Invalid character in Base64 input.',
      );
    }
    return sextet;
  }

  /// Encodes 3 input bytes at [offset] into 4 Base64 ASCII characters in [output].
  static int _encodeFullTriplet(
    List<int> bytes,
    int offset,
    Uint8List output,
    int outputIndex,
  ) {
    final byte0 = _validateInputByteValue(bytes[offset]);
    final byte1 = _validateInputByteValue(bytes[offset + 1]);
    final byte2 = _validateInputByteValue(bytes[offset + 2]);
    final combined = (byte0 << 16) | (byte1 << 8) | byte2;

    output[outputIndex] = _encodeTable[(combined >> 18) & 0x3F];
    output[outputIndex + 1] = _encodeTable[(combined >> 12) & 0x3F];
    output[outputIndex + 2] = _encodeTable[(combined >> 6) & 0x3F];
    output[outputIndex + 3] = _encodeTable[combined & 0x3F];
    return outputIndex + 4;
  }

  /// Encodes the trailing 1 or 2 remainder bytes at [offset] with `=` padding in [output].
  static void _encodeRemainder(
    List<int> bytes,
    int offset,
    int inputLength,
    Uint8List output,
    int outputIndex,
  ) {
    final remaining = inputLength - offset;
    final byte0 = _validateInputByteValue(bytes[offset]);

    if (remaining == 1) {
      output[outputIndex] = _encodeTable[(byte0 >> 2) & 0x3F];
      output[outputIndex + 1] = _encodeTable[(byte0 << 4) & 0x3F];
      output[outputIndex + 2] = _equalsCodeUnit;
      output[outputIndex + 3] = _equalsCodeUnit;
      return;
    }

    final byte1 = _validateInputByteValue(bytes[offset + 1]);
    final combined = (byte0 << 8) | byte1;
    output[outputIndex] = _encodeTable[(combined >> 10) & 0x3F];
    output[outputIndex + 1] = _encodeTable[(combined >> 4) & 0x3F];
    output[outputIndex + 2] = _encodeTable[(combined << 2) & 0x3F];
    output[outputIndex + 3] = _equalsCodeUnit;
  }

  /// Computes the exact decoded byte length of [encoded] and validates final padding structure.
  static int _resolveDecodedLength(String encoded, int length) {
    final baseBytes = (length >> 2) * 3;
    final lastCode = encoded.codeUnitAt(length - 1);
    final secondLastCode = encoded.codeUnitAt(length - 2);

    if (lastCode != _equalsCodeUnit) {
      if (secondLastCode == _equalsCodeUnit) {
        throw const Base64Exception(
          Base64ErrorKind.invalidPadding,
          'Non-padding character cannot follow Base64 padding.',
        );
      }
      return baseBytes;
    }

    if (encoded.codeUnitAt(length - 4) == _equalsCodeUnit ||
        encoded.codeUnitAt(length - 3) == _equalsCodeUnit) {
      throw const Base64Exception(
        Base64ErrorKind.invalidPadding,
        'Base64 padding cannot appear in the first two positions of a quantum.',
      );
    }
    return secondLastCode == _equalsCodeUnit ? baseBytes - 2 : baseBytes - 1;
  }

  /// Validates that [byteValue] is an unsigned 8-bit integer (`0x00..0xFF`).
  static int _validateInputByteValue(int byteValue) {
    if (byteValue < 0 || byteValue > 0xFF) {
      throw const Base64Exception(
        Base64ErrorKind.invalidCharacter,
        'Input byte value must be between 0 and 255.',
      );
    }
    return byteValue;
  }
}
