class OnboardingData {
  String name;
  int age;
  String gender;
  int heightCm;
  double weightKg;
  String? emergencyContactName;
  String? emergencyContactPhone;
  bool isEditMode;

  OnboardingData({
    this.name = '',
    this.age = 25,
    this.gender = '',
    this.heightCm = 170,
    this.weightKg = 70.0,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.isEditMode = false,
  });
}
