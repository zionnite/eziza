class Location {
  final int    id;
  final String state;
  final String city;
  final String area;

  const Location({
    required this.id,
    required this.state,
    required this.city,
    required this.area,
  });

  factory Location.fromJson(Map<String, dynamic> j) => Location(
        id:    j['id']    as int,
        state: j['state'] as String,
        city:  j['city']  as String,
        area:  j['area']  as String,
      );

  String get shortDisplay => '$area, $city';
  String get fullDisplay  => '$area, $city, $state';

  @override
  bool operator ==(Object other) =>
      other is Location && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
