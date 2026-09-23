class Profile {
  final String id;
  final String name;
  final String email;
  final String role;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.createdAt,
  });

  // --------------------------------------------------
  // Role helpers
  // --------------------------------------------------

  bool get isMerchant => role == 'merchant';

  bool get isUser => role == 'user';

  // --------------------------------------------------
  // Convert Supabase data → Profile
  // --------------------------------------------------

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // --------------------------------------------------
  // Convert Profile → database data
  //
  // IMPORTANT:
  // Do not include role here.
  // A user's role must not be changed from the
  // normal profile-edit flow.
  // --------------------------------------------------

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'email': email};
  }

  // --------------------------------------------------
  // Create a modified copy
  // --------------------------------------------------

  Profile copyWith({String? name, String? email}) {
    return Profile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role,
      createdAt: createdAt,
    );
  }
}
