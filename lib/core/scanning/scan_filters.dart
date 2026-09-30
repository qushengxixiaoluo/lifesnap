/// 扫描过滤规则（纯 Dart，无平台依赖，io 与 Web 扫描器共用）。
///
/// 抽成独立文件的原因：folder_scanner 在 Isolate 里遍历、web_pick_scanner 在
/// 浏览器递归目录句柄，两边必须用同一套「隐藏/系统目录 + 扩展名白名单」规则，
/// 否则同一块盘在桌面和网页端会扫出不同的结果，增量签名跟着漂移。
library;

/// 扩展名白名单（小写、不含点）：只收常见照片格式，HEIC 覆盖 iPhone 原片。
const photoExtensions = <String>{'jpg', 'jpeg', 'png', 'heic', 'webp', 'bmp'};

/// Windows 系统目录（小写比较）：扫描用户盘根目录时必须跳过，否则几十万个系统文件会拖死扫描。
const _systemDirNames = <String>{
  'system volume information',
  '\$recycle.bin',
  'recycler',
  'windows',
};

/// 是否是隐藏/系统目录名：以 '.' 开头（.git/.Trash 等）或命中 Windows 系统目录。
bool isHiddenOrSystemName(String name) =>
    name.startsWith('.') || _systemDirNames.contains(name.toLowerCase());

/// 相对路径里任意一段命中隐藏/系统规则即整体跳过（根目录自身除外，由调用方只传相对段）。
bool isHiddenOrSystemPath(String relativePath) =>
    relativePath.split(RegExp(r'[\\/]')).any(isHiddenOrSystemName);

/// 文件名是否在照片扩展名白名单内（大小写不敏感；无扩展名返回 false）。
bool isPhotoFileName(String name) {
  final lower = name.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot <= 0) return false;
  return photoExtensions.contains(lower.substring(dot + 1));
}
