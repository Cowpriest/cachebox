class FileModel {
  final String id;
  final String fileName;
  final String fileUrl;
  final String uploadedByUid;
  final String uploadedByName;
  final String storagePath;
  final String? mimeType;
  FileModel({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.uploadedByUid,
    required this.uploadedByName,
    required this.storagePath,
    this.mimeType,
  });
  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        fileUrl: json['fileUrl'] as String,
        uploadedByUid: json['uploadedByUid'] as String,
        uploadedByName: json['uploadedByName'] as String,
        storagePath: json['storagePath'] as String,
        mimeType: json['mimeType'] as String?,
      );
}

class FolderModel {
  final String name;
  final String path;
  final int? childrenCount;
  FolderModel({required this.name, required this.path, this.childrenCount});
  factory FolderModel.fromJson(Map<String, dynamic> json) => FolderModel(
        name: json['name'] as String,
        path: json['path'] as String,
        childrenCount:
            json['childrenCount'] is int ? json['childrenCount'] as int : null,
      );
}

class DirectoryListing {
  final List<FolderModel> folders;
  final List<FileModel> files;
  const DirectoryListing({required this.folders, required this.files});
}
