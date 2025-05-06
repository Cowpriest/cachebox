// lib/services/file_model.dart

class FileModel {
  final String id;
  final String fileName;
  final String fileUrl;
  final String uploadedByUid;
  final String uploadedByName;
  final String storagePath;

  FileModel({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.uploadedByUid,
    required this.uploadedByName,
    required this.storagePath,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    fileUrl: json['fileUrl'] as String,
    uploadedByUid: json['uploadedByUid'] as String,
    uploadedByName: json['uploadedByName'] as String,
    storagePath: json['storagePath'] as String,
  );
}
