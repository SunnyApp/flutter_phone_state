//extension DateTimeExt on DateTime {
//  Duration sinceNow() => -(this.difference(DateTime.now()));
//}
//
//extension IterableExtension<X> on List<X> {
//  X find([bool filter(X input)]) {
//    return this?.firstWhere(filter, orElse: () => null);
//  }
//
//  X lastOrNull([bool filter(X input)]) {
//    return this?.lastWhere(filter, orElse: () => null);
//  }
//
//  X firstOrNull([bool filter(X input)]) {
//    return this?.firstWhere(filter, orElse: () => null);
//  }
//}
//
//extension StringExt on String {
//  String truncate(int length) {
//    if (this == null) return this;
//    if (this.length <= length) {
//      return this;
//    } else {
//      return this.substring(0, length);
//    }
//  }
//
//  bool get isNullOrEmpty => this?.isNotEmpty != true;
//
//  bool get isNotNullOrEmpty => !isNullOrEmpty;
//
//  bool get isNullOrBlank => this == null || this.trim().isEmpty == true;
//
//  bool get isNotNullOrBlank => !isNullOrBlank;
//
//  String orEmpty() {
//    if (this == null) return "";
//    return this;
//  }
//}
//
//extension EnumExtension on Object {
//  String get value => "$this".replaceAll(RegExp(".*\\."), "");
//}
